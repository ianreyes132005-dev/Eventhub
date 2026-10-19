-- ═════════════════════════════════════════════════════════════════════════════
-- Remove walk-in registration.
--
-- Registration now always closes at the deadline when one is set, otherwise
-- when the event starts — same as registrationState() in
-- lib/core/app_colors.dart. The organizer apps no longer offer the option.
--
-- events.allow_walk_in is kept as an inert legacy column (always false,
-- ignored here) because the change-request functions from
-- 202610180007_event_change_requests.sql still name it; dropping it would
-- make those functions fail at runtime.
--
-- Requires 202610180005_event_timing_rules.sql. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- Turn the option off on every event that had it.
UPDATE public.events
SET    allow_walk_in = false
WHERE  allow_walk_in IS DISTINCT FROM false;

COMMENT ON COLUMN public.events.allow_walk_in IS
  'Legacy — walk-in registration was removed. Always false; not read by any rule.';

-- Registration rules without the walk-in exception. The existing trigger
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

  IF ev.max_participants IS NOT NULL AND ev.max_participants > 0
     AND ev.current_participants >= ev.max_participants THEN
    RAISE EXCEPTION 'This event is full — no spots remaining.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
