-- ═════════════════════════════════════════════════════════════════════════════
-- Re-applies 202610230003_archive_records.sql — safely.
--
-- Run this when supabase/checks/migration_status.sql shows ✗ for
-- 202610230003_archive_records. Do NOT rerun 202610230003 itself any more:
-- it also redefines enforce_registration_update_rules(), and
-- 202610280001_checkin_windows_final_attendance.sql has since replaced that
-- with a newer version (scan windows, final attendance, reasons) that still
-- includes 202610230003's archive exception. Rerunning 202610230003 would put
-- the older check-in rules back.
--
-- So this file holds everything else from 202610230003, unchanged — the
-- functions whose newest version is in that file:
--   • event_archive_rules()          only approved events with registrations
--                                    can be archived; archived = read-only
--   • block_archived_event_delete()  archived records survive account deletion
--   • registration_archive_guard()
--   • admin_delete_unused_event()    delete a finished event with nothing to keep
--   • notify_archive_changes()       organizer bell notice on archive / restore
--     + trigger trg_notify_archive_changes
--
-- The ✗ means one of those was missing or older: 202610230003 never ran to
-- the end (one error in the SQL editor undoes the whole script), or
-- 202610180010_event_archives.sql was run again later, which puts back its
-- older event_archive_rules().
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── What can be archived ─────────────────────────────────────────────────────
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
      IF COALESCE(NEW.approval_status, 'approved') <> 'approved' THEN
        RAISE EXCEPTION 'This event was never approved, so there''s nothing to archive. Delete it instead.';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.registrations WHERE event_id = NEW.event_id) THEN
        RAISE EXCEPTION 'Nobody registered for this event, so there''s nothing to archive. Delete it instead.';
      END IF;
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

-- ── Archived records survive account deletion ────────────────────────────────
-- auth.uid() IS NULL is the service role (the delete-student and
-- delete-organizer Edge Functions) or a cascade from deleting an account:
-- no longer allowed to remove archived events or their registrations.
CREATE OR REPLACE FUNCTION public.block_archived_event_delete()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.archived_at IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'This event is archived, so it can''t be deleted. Archived records are kept — deactivate the organizer''s account instead of deleting it.';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.registration_archive_guard()
RETURNS TRIGGER AS $$
DECLARE
  ev_id uuid := CASE WHEN TG_OP = 'DELETE' THEN OLD.event_id ELSE NEW.event_id END;
  is_admin boolean := EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid());
  archived boolean := EXISTS (SELECT 1 FROM public.events
                              WHERE event_id = ev_id AND archived_at IS NOT NULL);
BEGIN
  IF archived AND NOT is_admin THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'This registration is part of an archived event''s attendance record, so it can''t be deleted. Deactivate the account instead of deleting it.';
    END IF;
    IF auth.uid() IS NOT NULL THEN
      RAISE EXCEPTION 'This event is archived — its registrations and attendance can''t be changed.';
    END IF;
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ── Deleting an event that had nothing to keep ───────────────────────────────
-- Finished (cancelled, or check-in closed), not archived, no registrations:
-- an event that never went live, or that nobody registered for.
CREATE OR REPLACE FUNCTION public.admin_delete_unused_event(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  ev       public.events%ROWTYPE;
  org_name text;
  approved boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only the administrator can delete events here.';
  END IF;

  SELECT * INTO ev FROM public.events WHERE event_id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This event no longer exists — it may already have been deleted.';
  END IF;
  IF ev.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'This event is archived. Delete it permanently from the Archived list instead.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.registrations WHERE event_id = p_event_id) THEN
    RAISE EXCEPTION 'This event has registrations, so its attendance is kept. Archive it instead.';
  END IF;
  IF ev.event_status IS DISTINCT FROM 'cancelled'
     AND now() <= public.event_ends_at(ev) + interval '2 hours' THEN
    RAISE EXCEPTION 'Only finished events can be deleted here: cancelled ones, or ones whose check-in has closed.';
  END IF;

  approved := COALESCE(ev.approval_status, 'approved') = 'approved';
  SELECT full_name INTO org_name FROM public.organizers WHERE organizer_id = ev.organizer_id;

  -- Change requests are removed by ON DELETE CASCADE.
  DELETE FROM public.events WHERE event_id = p_event_id;

  -- event_id left NULL: the event row no longer exists.
  INSERT INTO public.event_logs
    (event_id, event_title, organizer_id, organizer_name, action, details, performed_by)
  VALUES (NULL, ev.title, ev.organizer_id, org_name, 'deleted',
          CASE WHEN approved THEN 'Deleted from Archives — nobody registered'
               ELSE 'Deleted from Archives — never approved' END,
          auth.uid());

  IF ev.organizer_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, user_type, title, message, notification_type)
    VALUES (ev.organizer_id::text, 'organizer', 'Event deleted',
            format('“%s” was deleted by the administrator. %s',
                   COALESCE(NULLIF(btrim(ev.title), ''), 'Untitled event'),
                   CASE WHEN approved THEN 'Nobody registered for it, so there was no attendance to keep.'
                        ELSE 'It was never approved, so there was no attendance to keep.' END),
            'event_deleted');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_unused_event(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_unused_event(uuid) TO authenticated;

-- ── Bell notices for archive / restore ───────────────────────────────────────
-- Statement-level, so archiving 12 events at once sends each organizer one
-- notice ("3 events archived"), not 12.
CREATE OR REPLACE FUNCTION public.notify_archive_changes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.notifications (user_id, user_type, title, message, notification_type)
  SELECT g.organizer_id::text,
         'organizer',
         CASE WHEN g.n = 1
              THEN CASE WHEN g.archived THEN 'Event archived' ELSE 'Event restored' END
              ELSE g.n || CASE WHEN g.archived THEN ' events archived' ELSE ' events restored' END
         END,
         CASE WHEN g.archived
              THEN g.names || CASE WHEN g.n = 1 THEN ' was' ELSE ' were' END
                   || ' moved to Archives by the administrator. The attendance is kept and stays'
                   || ' read-only; check-in photos are deleted.'
              ELSE g.names || CASE WHEN g.n = 1 THEN ' was' ELSE ' were' END
                   || ' restored from Archives and ' || CASE WHEN g.n = 1 THEN 'is' ELSE 'are' END
                   || ' back in your event lists.'
         END,
         CASE WHEN g.archived THEN 'event_archived' ELSE 'event_restored' END
  FROM (
    SELECT c.organizer_id, c.archived, c.n,
           CASE WHEN c.n = 1 THEN c.titles[1]
                WHEN c.n = 2 THEN c.titles[1] || ' and ' || c.titles[2]
                WHEN c.n = 3 THEN c.titles[1] || ', ' || c.titles[2] || ' and ' || c.titles[3]
                ELSE c.titles[1] || ', ' || c.titles[2] || ', ' || c.titles[3]
                     || ' and ' || (c.n - 3) || ' more'
           END AS names
    FROM (
      SELECT n.organizer_id,
             n.archived_at IS NOT NULL AS archived,
             count(*)::int AS n,
             array_agg('“' || COALESCE(NULLIF(btrim(n.title), ''), 'Untitled event') || '”'
                       ORDER BY n.title) AS titles
      FROM new_rows n
      JOIN old_rows o ON o.event_id = n.event_id
      WHERE (n.archived_at IS NULL) <> (o.archived_at IS NULL)
        AND n.organizer_id IS NOT NULL
      GROUP BY n.organizer_id, n.archived_at IS NOT NULL
    ) c
  ) g;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_archive_changes ON public.events;
CREATE TRIGGER trg_notify_archive_changes
  AFTER UPDATE ON public.events
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION public.notify_archive_changes();

NOTIFY pgrst, 'reload schema';
