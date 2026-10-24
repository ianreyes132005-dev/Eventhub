-- ═════════════════════════════════════════════════════════════════════════════
-- Organizers can delete registrations; declined ones stop counting.
--
-- 1. "Delete registration" (app Registrations tab, web Registrations page)
--    had no DELETE policy, so it removed nothing and the row came back on the
--    next reload. Organizers may now delete registrations for their OWN
--    events, except checked-in ones: those are the attendance record.
--    Archived events stay frozen (registration_archive_guard) and deactivated
--    organizers stay blocked (block_inactive_organizer_changes).
--
-- 2. events.current_participants counted declined registrations (status
--    'rejected'), because the counter only ran on insert and delete. It now
--    also runs when a registration is declined (or un-declined), and every
--    event is recounted once. The app counts the same way: countsAsRegistered
--    in lib/core/app_colors.dart.
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── 1. Delete rule ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "organizer_delete_own_event_registrations" ON public.registrations;
CREATE POLICY "organizer_delete_own_event_registrations"
  ON public.registrations
  FOR DELETE
  USING (
    status <> 'checked_in'
    AND EXISTS (
      SELECT 1
      FROM public.events e
      JOIN public.organizers o ON o.organizer_id = e.organizer_id
      WHERE e.event_id = registrations.event_id
        AND o.user_id = auth.uid()
    )
  );

-- ── 2. Participant count: every registration but a declined one ──────────────
CREATE OR REPLACE FUNCTION public.maintain_participant_count()
RETURNS TRIGGER AS $$
BEGIN
  -- A status change that doesn't decline or un-decline (e.g. a selfie step)
  -- leaves the count alone.
  IF TG_OP = 'UPDATE'
     AND NEW.event_id = OLD.event_id
     AND (NEW.status = 'rejected') = (OLD.status = 'rejected') THEN
    RETURN NULL;
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.status <> 'rejected' THEN
    UPDATE public.events
       SET current_participants = GREATEST(current_participants - 1, 0)
     WHERE event_id = OLD.event_id;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.status <> 'rejected' THEN
    UPDATE public.events
       SET current_participants = current_participants + 1
     WHERE event_id = NEW.event_id;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_maintain_participant_count ON public.registrations;
CREATE TRIGGER trg_maintain_participant_count
  AFTER INSERT OR DELETE OR UPDATE OF status, event_id ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.maintain_participant_count();

-- One-time recount, so events with declined registrations show the right
-- number now. Only rows that are off are touched.
UPDATE public.events e
   SET current_participants = c.n
  FROM (
    SELECT ev.event_id,
           (SELECT count(*)
              FROM public.registrations r
             WHERE r.event_id = ev.event_id
               AND r.status <> 'rejected')::int AS n
      FROM public.events ev
  ) c
 WHERE e.event_id = c.event_id
   AND e.current_participants IS DISTINCT FROM c.n;

NOTIFY pgrst, 'reload schema';
