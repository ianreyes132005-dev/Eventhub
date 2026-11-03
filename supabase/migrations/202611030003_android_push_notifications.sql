-- Android push registration and server-side delivery for EventHub notices.
-- Store eventhub_push_function_url and eventhub_push_webhook_secret in Vault
-- after deploying the send-push Edge Function.

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS public.push_tokens (
  token text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  platform text NOT NULL DEFAULT 'android' CHECK (platform = 'android'),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_tokens FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.register_push_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in before registering a push token.';
  END IF;
  IF p_token IS NULL OR btrim(p_token) = '' OR length(p_token) > 4096 THEN
    RAISE EXCEPTION 'A valid push token is required.';
  END IF;

  INSERT INTO public.push_tokens (token, user_id, platform, updated_at)
  VALUES (p_token, auth.uid(), 'android', now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        platform = EXCLUDED.platform,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in before unregistering a push token.';
  END IF;
  DELETE FROM public.push_tokens
  WHERE token = p_token AND user_id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.register_push_token(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unregister_push_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_token(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.dispatch_eventhub_push(
  p_user_ids uuid[],
  p_title text,
  p_body text,
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  endpoint text;
  webhook_secret text;
  recipients jsonb;
BEGIN
  SELECT jsonb_agg(DISTINCT user_id::text)
  INTO recipients
  FROM unnest(COALESCE(p_user_ids, ARRAY[]::uuid[])) AS users(user_id)
  WHERE user_id IS NOT NULL;
  IF recipients IS NULL THEN
    RETURN;
  END IF;

  SELECT decrypted_secret INTO endpoint
  FROM vault.decrypted_secrets
  WHERE name = 'eventhub_push_function_url';
  SELECT decrypted_secret INTO webhook_secret
  FROM vault.decrypted_secrets
  WHERE name = 'eventhub_push_webhook_secret';

  IF COALESCE(endpoint, '') = '' OR COALESCE(webhook_secret, '') = '' THEN
    RAISE WARNING 'Push delivery is not configured in Supabase Vault.';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := endpoint,
    body := jsonb_build_object(
      'user_ids', recipients,
      'title', COALESCE(NULLIF(btrim(p_title), ''), 'EventHub update'),
      'body', COALESCE(p_body, ''),
      'data', COALESCE(p_data, '{}'::jsonb)
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-eventhub-push-secret', webhook_secret
    ),
    timeout_milliseconds := 5000
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_eventhub_push(uuid[], text, text, jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.push_new_announcement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  recipients uuid[];
BEGIN
  SELECT COALESCE(array_agg(s.user_id), ARRAY[]::uuid[])
  INTO recipients
  FROM public.students s
  WHERE s.is_active IS TRUE AND s.user_id IS NOT NULL;

  PERFORM public.dispatch_eventhub_push(
    recipients,
    NEW.title,
    NEW.message,
    jsonb_build_object('type', 'announcement', 'announcement_id', NEW.id::text)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_new_announcement ON public.announcements;
CREATE TRIGGER trg_push_new_announcement
  AFTER INSERT ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.push_new_announcement();

CREATE OR REPLACE FUNCTION public.push_new_saved_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  recipient uuid;
BEGIN
  IF NEW.user_type = 'organizer' THEN
    SELECT o.user_id INTO recipient
    FROM public.organizers o
    WHERE o.organizer_id::text = NEW.user_id;
  ELSIF NEW.user_type = 'student' THEN
    SELECT s.user_id INTO recipient
    FROM public.students s
    WHERE s.user_id::text = NEW.user_id;
  END IF;

  PERFORM public.dispatch_eventhub_push(
    CASE WHEN recipient IS NULL THEN ARRAY[]::uuid[] ELSE ARRAY[recipient] END,
    NEW.title,
    NEW.message,
    jsonb_build_object(
      'type', COALESCE(NEW.notification_type, 'notification'),
      'notification_id', NEW.id::text
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_new_saved_notification ON public.notifications;
CREATE TRIGGER trg_push_new_saved_notification
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.push_new_saved_notification();

CREATE OR REPLACE FUNCTION public.push_event_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  recipients uuid[];
  organizer_user_id uuid;
  event_title text := COALESCE(NULLIF(btrim(NEW.title), ''), 'An event');
BEGIN
  IF NEW.event_status = 'cancelled'
     AND OLD.event_status IS DISTINCT FROM 'cancelled' THEN
    SELECT COALESCE(array_agg(r.student_user_id), ARRAY[]::uuid[])
    INTO recipients
    FROM public.registrations r
    WHERE r.event_id = NEW.event_id
      AND r.status <> 'rejected'
      AND r.student_user_id IS NOT NULL;

    PERFORM public.dispatch_eventhub_push(
      recipients,
      'Event cancelled',
      format('"%s" has been cancelled by the organizer.%s',
        event_title,
        CASE WHEN NULLIF(btrim(NEW.cancel_reason), '') IS NULL THEN ''
             ELSE E'\n\nReason: ' || btrim(NEW.cancel_reason) END),
      jsonb_build_object('type', 'event_cancelled', 'event_id', NEW.event_id::text)
    );
  ELSIF NEW.schedule_changed_at IS NOT NULL
     AND NEW.schedule_changed_at IS DISTINCT FROM OLD.schedule_changed_at
     AND NEW.event_status IS DISTINCT FROM 'cancelled' THEN
    SELECT COALESCE(array_agg(r.student_user_id), ARRAY[]::uuid[])
    INTO recipients
    FROM public.registrations r
    WHERE r.event_id = NEW.event_id
      AND r.status <> 'rejected'
      AND r.registered_at < NEW.schedule_changed_at
      AND r.student_user_id IS NOT NULL;

    PERFORM public.dispatch_eventhub_push(
      recipients,
      'Event updated',
      format('"%s" has new event details. Check EventHub for the updated schedule and venue.',
        event_title),
      jsonb_build_object('type', 'event_updated', 'event_id', NEW.event_id::text)
    );
  ELSIF NEW.approval_status IS DISTINCT FROM OLD.approval_status
     AND NEW.approval_status IN ('approved', 'rejected') THEN
    SELECT o.user_id INTO organizer_user_id
    FROM public.organizers o
    WHERE o.organizer_id = NEW.organizer_id;

    PERFORM public.dispatch_eventhub_push(
      CASE WHEN organizer_user_id IS NULL THEN ARRAY[]::uuid[]
           ELSE ARRAY[organizer_user_id] END,
      CASE WHEN NEW.approval_status = 'approved'
           THEN 'Event approved' ELSE 'Event rejected' END,
      format('Your event "%s" was %s.%s',
        event_title,
        NEW.approval_status,
        CASE WHEN NEW.approval_status = 'rejected'
                  AND NULLIF(btrim(NEW.rejection_reason), '') IS NOT NULL
             THEN E'\n\nReason: ' || btrim(NEW.rejection_reason)
             ELSE '' END),
      jsonb_build_object('type', 'event_' || NEW.approval_status,
                         'event_id', NEW.event_id::text)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_event_updates ON public.events;
CREATE TRIGGER trg_push_event_updates
  AFTER UPDATE OF event_status, schedule_changed_at, approval_status
  ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.push_event_updates();

CREATE OR REPLACE FUNCTION public.push_new_event_registration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  organizer_user_id uuid;
  organizer_id text;
  event_title text;
  signup_notices_enabled boolean;
BEGIN
  SELECT e.organizer_id, e.title, o.user_id,
         COALESCE(o.notification_preferences ->> 'signups', 'true') <> 'false'
  INTO organizer_id, event_title, organizer_user_id, signup_notices_enabled
  FROM public.events e
  JOIN public.organizers o ON o.organizer_id = e.organizer_id
  WHERE e.event_id = NEW.event_id;

  IF organizer_user_id IS NULL OR NOT COALESCE(signup_notices_enabled, true) THEN
    RETURN NEW;
  END IF;

  PERFORM public.dispatch_eventhub_push(
    ARRAY[organizer_user_id],
    'New student registration',
    format('A student registered for "%s".',
      COALESCE(NULLIF(btrim(event_title), ''), 'your event')),
    jsonb_build_object('type', 'new_registration',
                       'event_id', NEW.event_id::text,
                       'registration_id', NEW.id::text,
                       'organizer_id', organizer_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_new_event_registration ON public.registrations;
CREATE TRIGGER trg_push_new_event_registration
  AFTER INSERT ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.push_new_event_registration();

CREATE OR REPLACE FUNCTION public.push_event_revision_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  organizer_user_id uuid;
  event_title text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT o.user_id, e.title
  INTO organizer_user_id, event_title
  FROM public.organizers o
  LEFT JOIN public.events e ON e.event_id = NEW.event_id
  WHERE o.organizer_id = NEW.organizer_id;

  PERFORM public.dispatch_eventhub_push(
    CASE WHEN organizer_user_id IS NULL THEN ARRAY[]::uuid[]
         ELSE ARRAY[organizer_user_id] END,
    CASE WHEN NEW.status = 'approved'
         THEN 'Event changes approved' ELSE 'Event changes rejected' END,
    format('Your changes to "%s" were %s.%s',
      COALESCE(NULLIF(btrim(event_title), ''), 'your event'),
      NEW.status,
      CASE WHEN NEW.status = 'rejected'
                AND NULLIF(btrim(NEW.rejection_reason), '') IS NOT NULL
           THEN E'\n\nReason: ' || btrim(NEW.rejection_reason)
           ELSE '' END),
    jsonb_build_object('type', 'event_changes_' || NEW.status,
                       'event_id', NEW.event_id::text)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_event_revision_decision ON public.event_revisions;
CREATE TRIGGER trg_push_event_revision_decision
  AFTER UPDATE OF status ON public.event_revisions
  FOR EACH ROW EXECUTE FUNCTION public.push_event_revision_decision();

CREATE OR REPLACE FUNCTION public.push_registration_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  event_title text;
  notice_title text;
  notice_body text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('photo_required', 'photo_submitted', 'checked_in', 'rejected') THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'checked_in'
     AND EXISTS (
       SELECT 1 FROM public.user_settings s
       WHERE s.user_id = NEW.student_user_id
         AND 'checkins' = ANY(s.disabled_notifications)
     ) THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(e.title), ''), 'an event')
  INTO event_title
  FROM public.events e
  WHERE e.event_id = NEW.event_id;
  event_title := COALESCE(event_title, 'an event');

  IF NEW.status = 'photo_required' THEN
    notice_title := 'Selfie required';
    notice_body := format('Your organizer needs a selfie to verify your attendance at "%s".',
                          event_title);
  ELSIF NEW.status = 'photo_submitted' THEN
    notice_title := 'Photo received';
    notice_body := format('Your selfie for "%s" was submitted — awaiting organizer confirmation.',
                          event_title);
  ELSIF NEW.status = 'checked_in' THEN
    notice_title := 'Check-in confirmed!';
    notice_body := format('You have been checked in to "%s". Enjoy the event!', event_title);
  ELSE
    notice_title := 'Registration declined';
    notice_body := format('Your registration for "%s" was not approved by the organizer.%s',
      event_title,
      CASE WHEN NULLIF(btrim(NEW.rejection_reason), '') IS NULL THEN ''
           ELSE E'\n\nReason: ' || btrim(NEW.rejection_reason) END);
  END IF;

  PERFORM public.dispatch_eventhub_push(
    ARRAY[NEW.student_user_id],
    notice_title,
    notice_body,
    jsonb_build_object('type', 'registration_' || NEW.status,
                       'registration_id', NEW.id::text,
                       'event_id', NEW.event_id::text)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_registration_status_change ON public.registrations;
CREATE TRIGGER trg_push_registration_status_change
  AFTER UPDATE OF status ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.push_registration_status_change();

NOTIFY pgrst, 'reload schema';
