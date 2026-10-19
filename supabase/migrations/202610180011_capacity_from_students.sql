-- ═════════════════════════════════════════════════════════════════════════════
-- Event capacity = the number of active students.
--
-- Every student can register for every event, so an event's capacity is the
-- school's current student count: 200 active students → 200 spots. Adding
-- students (Add Student, registrar import) or reactivating them raises every
-- event's capacity with them; deactivating lowers it. Organizers no longer
-- set a capacity.
--
--   • active_student_count(): students with is_active = true — the "Active"
--     number on the admin dashboard. Deactivated stuadents can't sign in, so
--     they can't take a spot. Any signed-in user may call it (students can't
--     read other students' rows; this only returns the count).
--   • Registration no longer checks events.max_participants. One registration
--     per student per event is now enforced here, so a student who hasn't
--     registered always has a spot and the count can never pass the number
--     of students. max_participants is kept, unused, so the old per-event
--     values aren't lost.
--
-- Requires 202610180008_remove_walk_in.sql. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.active_student_count()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::integer FROM public.students WHERE is_active IS TRUE;
$$;

REVOKE EXECUTE ON FUNCTION public.active_student_count() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.active_student_count() TO authenticated;

COMMENT ON COLUMN public.events.max_participants IS
  'Legacy — capacity is the number of active students (active_student_count()). Not read by any rule.';

-- Registration rules: as in 202610180008, minus the capacity check, plus the
-- one-registration-per-student check. The event row is locked first, so two
-- registrations for the same event are checked one after the other (a double
-- tap can't create two). The existing trigger
-- trg_enforce_registration_insert_rules points at this function by name.
CREATE OR REPLACE FUNCTION public.enforce_registration_insert_rules()
RETURNS TRIGGER AS $$
DECLARE
  ev public.events%ROWTYPE;
BEGIN
  SELECT * INTO ev
    FROM public.events
    WHERE event_id = NEW.event_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event not found.';
  END IF;

  IF ev.approval_status != 'approved' THEN
    RAISE EXCEPTION 'Registration is closed — this event has not been approved yet.';
  END IF;

  IF ev.event_status = 'cancelled' THEN
    RAISE EXCEPTION 'Registration is closed — this event was cancelled.';
  END IF;

  IF now() >= public.event_ends_at(ev) THEN
    RAISE EXCEPTION 'Registration is closed — this event has already ended.';
  END IF;

  IF ev.registration_deadline IS NOT NULL THEN
    IF now() > ev.registration_deadline THEN
      RAISE EXCEPTION 'Registration is closed — the deadline has passed.';
    END IF;
  ELSIF now() >= public.event_starts_at(ev) THEN
    RAISE EXCEPTION 'Registration is closed — this event has already started.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.registrations
    WHERE event_id = NEW.event_id
      AND student_user_id = NEW.student_user_id
  ) THEN
    RAISE EXCEPTION 'You''re already registered for this event.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
