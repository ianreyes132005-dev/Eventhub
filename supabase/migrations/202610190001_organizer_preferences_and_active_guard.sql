ALTER TABLE public.organizers
  ADD COLUMN IF NOT EXISTS notification_preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS theme_mode text NOT NULL DEFAULT 'light'
    CHECK (theme_mode IN ('light', 'dark'));

CREATE OR REPLACE FUNCTION public.set_organizer_notification_preference(
  p_category text,
  p_enabled boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_category NOT IN ('signups', 'live', 'today', 'tomorrow') THEN
    RAISE EXCEPTION 'Unknown organizer notification category.';
  END IF;

  UPDATE public.organizers
  SET notification_preferences = jsonb_set(
    COALESCE(notification_preferences, '{}'::jsonb),
    ARRAY[p_category],
    to_jsonb(p_enabled),
    true
  )
  WHERE user_id = auth.uid()
    AND is_active IS TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active organizer account not found.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_organizer_theme_mode(p_theme_mode text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_theme_mode NOT IN ('light', 'dark') THEN
    RAISE EXCEPTION 'Invalid organizer theme mode.';
  END IF;

  UPDATE public.organizers
  SET theme_mode = p_theme_mode
  WHERE user_id = auth.uid()
    AND is_active IS TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active organizer account not found.';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_organizer_notification_preference(text, boolean)
  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_organizer_theme_mode(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_organizer_notification_preference(text, boolean)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_organizer_theme_mode(text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.block_inactive_organizer_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.admins WHERE user_id = auth.uid()
     )
     AND EXISTS (
       SELECT 1 FROM public.organizers
       WHERE user_id = auth.uid()
         AND is_active IS NOT TRUE
     ) THEN
    RAISE EXCEPTION 'Your account has been deactivated. Contact the administrator.';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_inactive_organizer_events ON public.events;
CREATE TRIGGER trg_block_inactive_organizer_events
  BEFORE INSERT OR UPDATE OR DELETE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.block_inactive_organizer_changes();

DROP TRIGGER IF EXISTS trg_block_inactive_organizer_registrations ON public.registrations;
CREATE TRIGGER trg_block_inactive_organizer_registrations
  BEFORE INSERT OR UPDATE OR DELETE ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.block_inactive_organizer_changes();

DROP TRIGGER IF EXISTS trg_block_inactive_organizer_announcements ON public.announcements;
CREATE TRIGGER trg_block_inactive_organizer_announcements
  BEFORE INSERT OR UPDATE OR DELETE ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.block_inactive_organizer_changes();

DROP TRIGGER IF EXISTS trg_block_inactive_organizer_event_logs ON public.event_logs;
CREATE TRIGGER trg_block_inactive_organizer_event_logs
  BEFORE INSERT OR UPDATE OR DELETE ON public.event_logs
  FOR EACH ROW EXECUTE FUNCTION public.block_inactive_organizer_changes();

-- Event change requests are optional on deployments that have not applied
-- 202610180007_event_change_requests.sql yet.
DO $$
BEGIN
  IF to_regclass('public.event_revisions') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_block_inactive_organizer_revisions ON public.event_revisions';
    EXECUTE 'CREATE TRIGGER trg_block_inactive_organizer_revisions
      BEFORE INSERT OR UPDATE OR DELETE ON public.event_revisions
      FOR EACH ROW EXECUTE FUNCTION public.block_inactive_organizer_changes()';
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_inactive_organizer_profile ON public.organizers;
CREATE TRIGGER trg_block_inactive_organizer_profile
  BEFORE UPDATE OR DELETE ON public.organizers
  FOR EACH ROW EXECUTE FUNCTION public.block_inactive_organizer_changes();

DROP TRIGGER IF EXISTS trg_block_inactive_organizer_storage ON storage.objects;
CREATE TRIGGER trg_block_inactive_organizer_storage
  BEFORE INSERT OR UPDATE OR DELETE ON storage.objects
  FOR EACH ROW EXECUTE FUNCTION public.block_inactive_organizer_changes();
