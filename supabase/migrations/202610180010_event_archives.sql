-- ═════════════════════════════════════════════════════════════════════════════
-- Event archives — the admin moves finished events out of everyday lists.
--
--   • Archiving / restoring is admin-only. Only cancelled events, or ended
--     events whose check-in has closed (2 h after the end), can be archived.
--     Archived events disappear from students' Events tab and organizers'
--     everyday lists (the apps filter on archived_at); students still see
--     their own registrations and attendance, organizers see them under an
--     "Archived" filter.
--   • Archived events and their registrations are frozen records: organizers
--     and students can't change or delete them.
--   • The admin can permanently delete an ARCHIVED event (and, by cascade, its
--     registrations / attendance and change requests) through
--     admin_delete_archived_event(), which requires the event title as
--     confirmation and writes an event_logs entry.
--   • Archive / restore / delete are logged in event_logs automatically.
--
-- Requires 202610180005_event_timing_rules.sql (event_ends_at). Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid;

CREATE INDEX IF NOT EXISTS idx_events_archived_at ON public.events (archived_at);

-- ── Archive rules on events ───────────────────────────────────────────────────
-- auth.uid() IS NULL = service role (Edge Functions, e.g. account deletion):
-- not restricted here.
CREATE OR REPLACE FUNCTION public.event_archive_rules()
RETURNS TRIGGER AS $$
DECLARE
  is_admin boolean := EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid());
BEGIN
  IF NEW.archived_at IS DISTINCT FROM OLD.archived_at THEN
    IF auth.uid() IS NOT NULL AND NOT is_admin THEN
      RAISE EXCEPTION 'Only the administrator can archive or restore events.';
    END IF;
    IF OLD.archived_at IS NULL THEN
      -- Archive
      IF NEW.event_status IS DISTINCT FROM 'cancelled'
         AND now() <= public.event_ends_at(NEW) + interval '2 hours' THEN
        RAISE EXCEPTION 'Only cancelled events, or events whose check-in has closed (2 hours after the end), can be archived.';
      END IF;
      NEW.archived_at := now();
      NEW.archived_by := auth.uid();
    ELSIF NEW.archived_at IS NULL THEN
      -- Restore
      NEW.archived_by := NULL;
    END IF;
    RETURN NEW;
  END IF;

  -- archived_by only moves together with archived_at.
  NEW.archived_by := OLD.archived_by;

  -- Archived events are read-only for everyone but the admin.
  IF OLD.archived_at IS NOT NULL AND auth.uid() IS NOT NULL AND NOT is_admin THEN
    RAISE EXCEPTION 'This event is archived, so it can''t be changed. Ask the administrator to restore it first.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_event_archive_rules ON public.events;
CREATE TRIGGER trg_event_archive_rules
  BEFORE UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.event_archive_rules();

-- Archived events can't be deleted by organizers either (the admin uses
-- admin_delete_archived_event).
CREATE OR REPLACE FUNCTION public.block_archived_event_delete()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.archived_at IS NOT NULL
     AND auth.uid() IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'This event is archived, so it can''t be deleted.';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_archived_event_delete ON public.events;
CREATE TRIGGER trg_block_archived_event_delete
  BEFORE DELETE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.block_archived_event_delete();

-- ── Registrations of archived events are frozen ───────────────────────────────
CREATE OR REPLACE FUNCTION public.registration_archive_guard()
RETURNS TRIGGER AS $$
DECLARE
  ev_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.event_id ELSE NEW.event_id END;
BEGIN
  IF auth.uid() IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
     AND EXISTS (SELECT 1 FROM public.events
                 WHERE event_id = ev_id AND archived_at IS NOT NULL) THEN
    RAISE EXCEPTION 'This event is archived — its registrations and attendance can''t be changed.';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_registration_archive_guard ON public.registrations;
CREATE TRIGGER trg_registration_archive_guard
  BEFORE UPDATE OR DELETE ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.registration_archive_guard();

-- ── Audit trail ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.log_event_archive_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.archived_at IS DISTINCT FROM OLD.archived_at THEN
    INSERT INTO public.event_logs
      (event_id, event_title, organizer_id, organizer_name, action, details, performed_by)
    VALUES (
      NEW.event_id, NEW.title, NEW.organizer_id,
      (SELECT full_name FROM public.organizers WHERE organizer_id = NEW.organizer_id),
      CASE WHEN NEW.archived_at IS NULL THEN 'unarchived' ELSE 'archived' END,
      CASE WHEN NEW.archived_at IS NULL THEN 'Restored from archives'
           ELSE 'Moved to archives' END,
      auth.uid());
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_log_event_archive_change ON public.events;
CREATE TRIGGER trg_log_event_archive_change
  AFTER UPDATE OF archived_at ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.log_event_archive_change();

-- ── Attendance totals per event (admin Archives table) ────────────────────────
-- security_invoker: the caller's own RLS on registrations applies.
CREATE OR REPLACE VIEW public.event_attendance_summary
WITH (security_invoker = true) AS
SELECT event_id,
       count(*)::int                                        AS registered,
       count(*) FILTER (WHERE status = 'checked_in')::int   AS present,
       count(*) FILTER (WHERE status = 'rejected')::int     AS rejected
FROM public.registrations
GROUP BY event_id;

REVOKE ALL ON public.event_attendance_summary FROM anon;
GRANT SELECT ON public.event_attendance_summary TO authenticated;

-- ── Permanent delete (archived events only) ───────────────────────────────────
-- Returns how many registrations were deleted. The app removes the check-in
-- selfie files from Storage afterwards (Storage files can't be deleted from
-- SQL).
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
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_archived_event(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_archived_event(uuid, text) TO authenticated;

-- ── Storage: admin may remove check-in selfies and event banners ──────────────
DROP POLICY IF EXISTS "admin_delete_selfies" ON storage.objects;
CREATE POLICY "admin_delete_selfies" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'selfies'
    AND EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "admin_select_event_banners" ON storage.objects;
CREATE POLICY "admin_select_event_banners" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "admin_delete_event_banners" ON storage.objects;
CREATE POLICY "admin_delete_event_banners" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
  );
