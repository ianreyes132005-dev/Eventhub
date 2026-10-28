-- ═════════════════════════════════════════════════════════════════════════════
-- Check-in: arrive by the end, finish within 2 hours; attendance is final once
-- check-in closes; students can cancel before check-in opens.
--
-- 1. Two windows instead of one (was: every step from 1 hour before the start
--    until 2 hours after the end):
--      • Arriving: a ticket can be scanned (or a Registered student checked in
--        by hand) from 1 hour before the start until 30 minutes after the end.
--      • Finishing: a student scanned in time can still send the selfie and be
--        approved or declined until 2 hours after the end.
--    Nobody gets checked in for an event they showed up to after it was over,
--    and organizers get 1½ hours after scanning stops to finish their reviews.
--
-- 2. Attendance is final once check-in closes (2 hours after the end). Nobody
--    but the administrator can change or delete those registrations, and the
--    administrator can only correct one (Checked in ↔ Absent) with a reason,
--    stamped in corrected_at. Before then organizers keep the usual steps,
--    plus:
--      • a check-in or a decline is final (the apps already treated it so; now
--        the database agrees, so a bulk action can't undo one);
--      • checking a student in without an approved selfie (by hand) needs a
--        reason, saved in attendance_note; declining needs a reason too;
--      • only the student's own upload marks a selfie as sent, and organizers
--        change nothing but the check-in fields.
--
-- 3. Students can cancel their own registration while it's still Registered
--    (not scanned) and check-in hasn't opened (until 1 hour before the start).
--    Cancelling deletes it; they can register again while registration is
--    open.
--
-- The app shows the same rules (kScanClosesAfter, kCheckInClosesAfter,
-- attendanceFinal and registrationCancellable in lib/core/app_colors.dart);
-- keep the two the same.
--
-- Run once in the Supabase SQL editor, after 202610270002. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── Columns ──────────────────────────────────────────────────────────────────
ALTER TABLE public.registrations
  ADD COLUMN IF NOT EXISTS attendance_note text,
  ADD COLUMN IF NOT EXISTS corrected_at timestamptz;

COMMENT ON COLUMN public.registrations.attendance_note IS
  'Why this attendance didn''t come from an approved selfie: the organizer''s reason for checking the student in by hand, or the administrator''s reason for a correction.';
COMMENT ON COLUMN public.registrations.corrected_at IS
  'When the administrator corrected this attendance after check-in closed (reviewed_by is the administrator).';

-- ── Windows ──────────────────────────────────────────────────────────────────
-- Arriving: scanning a ticket, or checking a Registered student in by hand.
-- (Finishing keeps event_checkin_problem: 1 hour before the start until 2
-- hours after the end.)
CREATE OR REPLACE FUNCTION public.event_scan_problem(p_event_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
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
  IF now() > public.event_ends_at(ev) + interval '30 minutes' THEN
    RETURN 'Scanning closed 30 minutes after the event ended. Students scanned before then can still finish checking in.';
  END IF;
  RETURN NULL;
END;
$$;

-- Check-in has closed, so the attendance is final.
CREATE OR REPLACE FUNCTION public.event_attendance_final(p_event_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.events e
    WHERE e.event_id = p_event_id
      AND now() > public.event_ends_at(e) + interval '2 hours'
  );
$$;

-- ── Who may change a registration, and when ─────────────────────────────────
-- Replaces the 202610230003 body; trg_enforce_registration_update_rules points
-- at this function by name. It runs before trg_stamp_registration_status_change
-- (triggers fire in name order), so status_changed_at is stamped afterwards.
CREATE OR REPLACE FUNCTION public.enforce_registration_update_rules()
RETURNS TRIGGER AS $$
DECLARE
  problem  text;
  ev       public.events%ROWTYPE;
  is_final boolean := false;
  -- What a check-in step changes. Everything else stays as it was.
  checkin_fields constant text[] := ARRAY[
    'status', 'checked_in_at', 'reviewed_by', 'rejection_reason',
    'attendance_note', 'corrected_at', 'status_changed_at'];
BEGIN
  SELECT * INTO ev FROM public.events WHERE event_id = OLD.event_id;
  IF FOUND THEN
    is_final := now() > public.event_ends_at(ev) + interval '2 hours';
  END IF;

  -- ── The administrator ──────────────────────────────────────────────────────
  IF EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    -- Archiving: the photo file is gone, so its link is cleared. The
    -- attendance (status, times, reviewer) stays exactly as it was.
    IF OLD.selfie_url IS NOT NULL
       AND NEW.selfie_url IS NULL
       AND (to_jsonb(NEW) - 'selfie_url') = (to_jsonb(OLD) - 'selfie_url')
    THEN
      RETURN NEW;
    END IF;

    -- Correcting attendance once check-in has closed: Checked in or Absent
    -- (back to Registered), with a reason. Archived events stay frozen
    -- (restore one first); a cancelled one had no check-in to correct.
    IF is_final
       AND ev.archived_at IS NULL
       AND ev.event_status IS DISTINCT FROM 'cancelled'
       AND NEW.status IN ('checked_in', 'pending')
       AND NEW.status IS DISTINCT FROM OLD.status
       AND nullif(btrim(COALESCE(NEW.attendance_note, '')), '') IS NOT NULL
       AND (to_jsonb(NEW) - checkin_fields) = (to_jsonb(OLD) - checkin_fields)
    THEN
      NEW.corrected_at := now();
      NEW.reviewed_by  := auth.uid();
      NEW.checked_in_at := CASE WHEN NEW.status = 'checked_in'
                                THEN COALESCE(NEW.checked_in_at, now())
                                ELSE NULL END;
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'The administrator can only correct attendance after an event''s check-in has closed: mark the student Checked in or Absent, with a reason.';
  END IF;

  -- ── Everyone else: final once check-in has closed ──────────────────────────
  IF is_final THEN
    RAISE EXCEPTION 'Check-in for this event closed 2 hours after it ended, so its attendance is final. Only the administrator can correct it.';
  END IF;

  -- ── A step into check-in happens inside its window ─────────────────────────
  -- From Registered it's an arrival (a scan, or a check-in by hand): until 30
  -- minutes after the end. Later steps finish a check-in that started in
  -- time: until 2 hours after the end.
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('qr_scanned', 'photo_required', 'photo_submitted', 'checked_in')
  THEN
    problem := CASE WHEN OLD.status = 'pending'
                    THEN public.event_scan_problem(NEW.event_id)
                    ELSE public.event_checkin_problem(NEW.event_id) END;
    IF problem IS NOT NULL THEN
      RAISE EXCEPTION '%', problem;
    END IF;
  END IF;

  -- ── Organizers: the check-in steps ─────────────────────────────────────────
  IF EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid()) THEN
    IF (to_jsonb(NEW) - checkin_fields) <> (to_jsonb(OLD) - checkin_fields) THEN
      RAISE EXCEPTION 'Organizers can only change a registration''s check-in status.';
    END IF;
    IF NEW.corrected_at IS DISTINCT FROM OLD.corrected_at THEN
      RAISE EXCEPTION 'Only the administrator can correct attendance.';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF OLD.status IN ('checked_in', 'rejected') THEN
        RAISE EXCEPTION 'This check-in was already decided, so it can''t be changed. After check-in closes, the administrator can correct it.';
      END IF;
      IF NEW.status = 'pending' THEN
        RAISE EXCEPTION 'A check-in can''t be moved back to Registered.';
      END IF;
      IF NEW.status = 'photo_submitted' THEN
        RAISE EXCEPTION 'Only the student can send their check-in photo.';
      END IF;
      IF NEW.status = 'checked_in'
         AND OLD.status <> 'photo_submitted'
         AND nullif(btrim(COALESCE(NEW.attendance_note, '')), '') IS NULL
      THEN
        RAISE EXCEPTION 'Checking a student in without an approved selfie needs a reason.';
      END IF;
      IF NEW.status = 'rejected'
         AND nullif(btrim(COALESCE(NEW.rejection_reason, '')), '') IS NULL
      THEN
        RAISE EXCEPTION 'Declining a check-in needs a reason.';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- ── Students: only their own selfie ────────────────────────────────────────
  IF OLD.status = 'photo_required'
     AND NEW.status = 'photo_submitted'
     AND NEW.selfie_url IS NOT NULL
     AND NEW.checked_in_at IS NOT DISTINCT FROM OLD.checked_in_at
     AND NEW.attendance_note IS NOT DISTINCT FROM OLD.attendance_note
     AND NEW.corrected_at IS NOT DISTINCT FROM OLD.corrected_at
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'You are not allowed to make this change to a registration.';
END;
$$ LANGUAGE plpgsql;

-- ── Deleting ─────────────────────────────────────────────────────────────────
-- The signed-in organizer runs this event. Same as 202610230002, repeated so
-- this file also works where that one hasn't been run.
CREATE OR REPLACE FUNCTION public.organizer_owns_event(p_event_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.events e
    JOIN public.organizers o ON o.organizer_id = e.organizer_id
    WHERE e.event_id = p_event_id
      AND o.user_id = auth.uid()
  );
$$;

-- Organizers: not a check-in, and not once check-in has closed.
DROP POLICY IF EXISTS "organizer_delete_own_event_registrations" ON public.registrations;
CREATE POLICY "organizer_delete_own_event_registrations"
  ON public.registrations
  FOR DELETE
  USING (
    status <> 'checked_in'
    AND public.organizer_owns_event(event_id)
    AND NOT public.event_attendance_final(event_id)
  );

-- Students can cancel while check-in hasn't opened (until 1 hour before the
-- start) on an event that's still on: not cancelled, not archived.
CREATE OR REPLACE FUNCTION public.registration_cancellable(p_event_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.events e
    WHERE e.event_id = p_event_id
      AND e.archived_at IS NULL
      AND e.event_status IS DISTINCT FROM 'cancelled'
      AND now() < public.event_starts_at(e) - interval '1 hour'
  );
$$;

DROP POLICY IF EXISTS "student_cancel_own_registration" ON public.registrations;
CREATE POLICY "student_cancel_own_registration"
  ON public.registrations
  FOR DELETE
  USING (
    auth.uid() = student_user_id
    AND status = 'pending'
    AND public.registration_cancellable(event_id)
  );

NOTIFY pgrst, 'reload schema';
