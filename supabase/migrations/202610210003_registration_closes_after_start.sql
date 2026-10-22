-- ═════════════════════════════════════════════════════════════════════════════
-- Registration stays open until 2 hours after the event starts.
--
-- Before: registration closed the moment the event started (unless the event
-- had a registration deadline, which no form sets). Now a student can still
-- register up to 2 hours into the event — never after it ends. A deadline,
-- when one is set, still wins.
--
-- The app shows the same rule: kRegistrationClosesAfterStart and
-- registrationClosesAt in lib/core/app_colors.dart — keep the two the same.
--
-- Same function as 202610180011_capacity_from_students.sql with only the
-- "started" check changed. Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

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
  ELSIF now() >= public.event_starts_at(ev) + interval '2 hours' THEN
    RAISE EXCEPTION 'Registration is closed — it closes 2 hours after the event starts.';
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

NOTIFY pgrst, 'reload schema';
