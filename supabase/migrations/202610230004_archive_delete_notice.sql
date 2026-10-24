-- ═════════════════════════════════════════════════════════════════════════════
-- The organizer is told when the admin permanently deletes an archived event.
--
-- 202610230003 notifies organizers when their events are archived, restored,
-- or deleted for having nothing to keep. A permanent delete from Archives
-- removed the event and its attendance record without a word; now it leaves
-- the same "Event deleted" bell notice (notifications.notification_type
-- 'event_deleted', shown by OrganizerNotices.adminNotices).
--
-- Same function as 202610180010_event_archives.sql with the notice added.
-- Run once in the Supabase SQL editor, after 202610230003. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_delete_archived_event(
  p_event_id uuid, p_confirm_title text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  ev       public.events%ROWTYPE;
  n        integer;
  org_name text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only the administrator can permanently delete events.';
  END IF;

  SELECT * INTO ev FROM public.events WHERE event_id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This event no longer exists — it may already have been deleted.';
  END IF;
  IF ev.archived_at IS NULL THEN
    RAISE EXCEPTION 'Archive this event before deleting it permanently.';
  END IF;
  IF lower(btrim(COALESCE(p_confirm_title, ''))) <> lower(btrim(COALESCE(ev.title, ''))) THEN
    RAISE EXCEPTION 'The title you typed doesn''t match the event title.';
  END IF;

  SELECT count(*) INTO n FROM public.registrations WHERE event_id = p_event_id;
  SELECT full_name INTO org_name FROM public.organizers WHERE organizer_id = ev.organizer_id;

  -- Registrations and change requests are removed by ON DELETE CASCADE.
  DELETE FROM public.events WHERE event_id = p_event_id;

  -- event_id left NULL: the event row no longer exists.
  INSERT INTO public.event_logs
    (event_id, event_title, organizer_id, organizer_name, action, details, performed_by)
  VALUES (NULL, ev.title, ev.organizer_id, org_name, 'deleted',
          format('Permanently deleted from archives with %s registration(s) and their attendance records', n),
          auth.uid());

  -- The organizer's bell: their archived event and its record are gone.
  IF ev.organizer_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, user_type, title, message, notification_type)
    VALUES (ev.organizer_id::text, 'organizer', 'Event deleted',
            CASE WHEN n = 0
                 THEN format('“%s” was permanently deleted from Archives by the administrator. It had no registrations.',
                             COALESCE(NULLIF(btrim(ev.title), ''), 'Untitled event'))
                 ELSE format('“%s” was permanently deleted from Archives by the administrator, together with its attendance record (%s registration%s).',
                             COALESCE(NULLIF(btrim(ev.title), ''), 'Untitled event'),
                             n, CASE WHEN n = 1 THEN '' ELSE 's' END)
            END,
            'event_deleted');
  END IF;

  RETURN n;
END;
$$;

NOTIFY pgrst, 'reload schema';
