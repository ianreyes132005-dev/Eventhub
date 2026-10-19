-- ═════════════════════════════════════════════════════════════════════════════
-- Event timing rules — the clock decides an event's lifecycle.
--
-- Mirrors the client rules in lib/core/app_colors.dart (eventWindow,
-- registrationState, checkInBlockedReason, approvalExpired). Times are the
-- school's local time (Asia/Manila); missing start/end times default to
-- 08:00 / 23:59:59, same as the app.
--
--   1. allow_walk_in       per-event "registration stays open during the event"
--   2. stored status       only 'cancelled' is meaningful; legacy values reset
--   3. registration        closes at the deadline, else at the event start
--                          (or at the end with walk-ins), never after the end
--   4. check-in            QR scan → selfie → check-in only from 1 h before the
--                          start to 2 h after the end, never for cancelled events
--   5. approval            an event that already started can't be approved
-- Safe to run more than once.
-- ═════════════════════════════════════════════════════════════════════════════

-- 1. Walk-in registration option (off by default).
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS allow_walk_in boolean NOT NULL DEFAULT false;

-- 2. Lifecycle is computed from the schedule; only a cancellation is stored.
--    Reset legacy 'ongoing' / 'completed' / 'active' / … values, which used to
--    force an event to look ongoing/ended regardless of its dates.
UPDATE public.events
SET    event_status = 'upcoming'
WHERE  event_status IS DISTINCT FROM 'cancelled'
  AND  event_status IS DISTINCT FROM 'upcoming';

-- Event start / end as real instants in school time.
CREATE OR REPLACE FUNCTION public.event_starts_at(e public.events)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT (e.event_date + COALESCE(e.start_time, time '08:00'))
         AT TIME ZONE 'Asia/Manila'
$$;

CREATE OR REPLACE FUNCTION public.event_ends_at(e public.events)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT (COALESCE(e.end_date, e.event_date) + COALESCE(e.end_time, time '23:59:59'))
         AT TIME ZONE 'Asia/Manila'
$$;

-- 3. Registration rules (replaces the Section 18 version — same checks plus
--    timing). The existing trigger trg_enforce_registration_insert_rules
--    points at this function by name, so it picks up the new body.
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
  ELSIF NOT COALESCE(ev.allow_walk_in, false)
        AND now() >= public.event_starts_at(ev) THEN
    RAISE EXCEPTION 'Registration is closed — this event has already started.';
  END IF;

  IF ev.max_participants IS NOT NULL AND ev.max_participants > 0
     AND ev.current_participants >= ev.max_participants THEN
    RAISE EXCEPTION 'This event is full — no spots remaining.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Check-in window. SECURITY DEFINER so the event is readable whichever
--    role triggers the update (organizer scanning, student sending a selfie).
--    Returns NULL when check-in is allowed, otherwise the reason.
CREATE OR REPLACE FUNCTION public.event_checkin_problem(p_event_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  ev public.events%ROWTYPE;
BEGIN
  SELECT * INTO ev FROM public.events WHERE event_id = p_event_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  IF ev.event_status = 'cancelled' THEN
    RETURN 'Check-in is closed — this event was cancelled.';
  END IF;
  IF now() < public.event_starts_at(ev) - interval '1 hour' THEN
    RETURN 'Check-in opens 1 hour before the event starts.';
  END IF;
  IF now() > public.event_ends_at(ev) + interval '2 hours' THEN
    RETURN 'Check-in closed 2 hours after the event ended.';
  END IF;
  RETURN NULL;
END;
$$;

-- Same rules as before (organizers may make any legitimate transition; a
-- student may only submit their selfie) — plus: moving a registration INTO a
-- check-in step is only possible inside the check-in window. Rejecting, or
-- anything that isn't a step forward in check-in, is unaffected.
CREATE OR REPLACE FUNCTION public.enforce_registration_update_rules()
RETURNS TRIGGER AS $$
DECLARE
  problem text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('qr_scanned', 'photo_required', 'photo_submitted', 'checked_in')
  THEN
    problem := public.event_checkin_problem(NEW.event_id);
    IF problem IS NOT NULL THEN
      RAISE EXCEPTION '%', problem;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid()) THEN
    RETURN NEW;
  END IF;

  IF OLD.status = 'photo_required'
     AND NEW.status = 'photo_submitted'
     AND NEW.selfie_url IS NOT NULL
     AND NEW.checked_in_at IS NOT DISTINCT FROM OLD.checked_in_at
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'You are not allowed to make this change to a registration.';
END;
$$ LANGUAGE plpgsql;

-- 5. An event can't be approved once its start time has passed — otherwise
--    registration would open in the middle of the event. The organizer edits
--    the dates and resubmits; then it can be approved normally.
CREATE OR REPLACE FUNCTION public.block_late_approval()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.approval_status = 'approved'
     AND OLD.approval_status IS DISTINCT FROM 'approved'
     AND now() >= public.event_starts_at(NEW)
  THEN
    RAISE EXCEPTION 'This event has already started, so it can no longer be approved. Reject it so the organizer can reschedule and resubmit.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_late_approval ON public.events;
CREATE TRIGGER trg_block_late_approval
  BEFORE UPDATE OF approval_status ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.block_late_approval();
