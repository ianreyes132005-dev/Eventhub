-- ============================================================
-- EventHub – Registration & Check-In Schema
-- Paste this entire file into your Supabase SQL Editor and run it.
-- ============================================================

-- 1. REGISTRATIONS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.registrations (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id          UUID        NOT NULL REFERENCES public.events(event_id) ON DELETE CASCADE,
  event_title       TEXT        NOT NULL DEFAULT '',
  student_user_id   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  student_name      TEXT        NOT NULL,
  student_school_id TEXT        NOT NULL, -- copy of students.lrn at registration time
  qr_code           TEXT        UNIQUE NOT NULL,
  status            TEXT        NOT NULL DEFAULT 'Pending'
    CHECK (status IN (
      'pending',        -- student registered, not yet scanned
      'qr_scanned',     -- organizer scanned QR, appears in registrations tab
      'photo_required', -- organizer clicked Confirm, student camera triggered
      'photo_submitted',-- student uploaded selfie, organizer can check in
      'checked_in',     -- organizer clicked Check In
      'rejected'        -- organizer rejected
    )),
  selfie_url        TEXT,       -- storage path: {student_user_id}/{registration_id}.jpg
  registered_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checked_in_at     TIMESTAMPTZ
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_reg_event   ON public.registrations (event_id);
CREATE INDEX IF NOT EXISTS idx_reg_student ON public.registrations (student_user_id);
CREATE INDEX IF NOT EXISTS idx_reg_status  ON public.registrations (status);
CREATE INDEX IF NOT EXISTS idx_reg_qr      ON public.registrations (qr_code);

-- 2. ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE public.registrations ENABLE ROW LEVEL SECURITY;

-- Students: read their own registrations
CREATE POLICY "student_select_own" ON public.registrations
  FOR SELECT USING (auth.uid() = student_user_id);

-- Students: register (insert their own row)
CREATE POLICY "student_insert_own" ON public.registrations
  FOR INSERT WITH CHECK (auth.uid() = student_user_id);

-- Students: update their own row (upload selfie, etc.)
CREATE POLICY "student_update_own" ON public.registrations
  FOR UPDATE USING (auth.uid() = student_user_id);

-- Organizers: read all registrations
CREATE POLICY "organizer_select_all" ON public.registrations
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- Organizers: update status (confirm, check in, reject)
CREATE POLICY "organizer_update_status" ON public.registrations
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- 3. REALTIME
-- ============================================================
-- Enable Realtime so the Flutter app receives live updates.
ALTER PUBLICATION supabase_realtime ADD TABLE public.registrations;

-- 4. STORAGE BUCKET FOR SELFIES
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('selfies', 'selfies', false)
ON CONFLICT (id) DO NOTHING;

-- Students: upload their own selfie (path must start with their user_id)
CREATE POLICY "student_upload_selfie" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'selfies'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Students: update/replace their own selfie
CREATE POLICY "student_update_selfie" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'selfies'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Students: read their own selfie
CREATE POLICY "student_read_own_selfie" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'selfies'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Organizers: read all selfies (to verify attendance)
CREATE POLICY "organizer_read_selfies" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'selfies'
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- Admins: read all selfies (for photo review in admin dashboard)
CREATE POLICY "admin_read_selfies" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'selfies'
    AND EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
  );

-- 5. ATOMIC PARTICIPANT COUNTER UPDATE FUNCTIONS
-- ============================================================
-- Doing UPDATE events SET current_participants = current_participants + 1
-- atomically in the database avoids the race condition that occurs when the
-- app reads the current count and then writes count+1 (two concurrent
-- registrations can both read 5 and both write 6 instead of one writing 7).
--
-- Run ONCE in Supabase SQL Editor (or re-run safely; CREATE OR REPLACE is idempotent).

CREATE OR REPLACE FUNCTION public.increment_participant_count(p_event_id UUID)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  UPDATE public.events
  SET current_participants = current_participants + 1
  WHERE event_id = p_event_id;
$$;

CREATE OR REPLACE FUNCTION public.decrement_participant_count(p_event_id UUID)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  UPDATE public.events
  SET current_participants = GREATEST(current_participants - 1, 0)
  WHERE event_id = p_event_id;
$$;

-- Allow any authenticated user to call these functions.
-- The functions only touch the counter column; they do not bypass RLS for SELECT.
GRANT EXECUTE ON FUNCTION public.increment_participant_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_participant_count(UUID) TO authenticated;

-- 6. STORAGE BUCKET FOR EVENT BANNERS
-- ============================================================
-- Public bucket: anyone can read banner images (no auth required for SELECT).
-- Only authenticated organizers may upload / update / delete.
INSERT INTO storage.buckets (id, name, public)
VALUES ('event-banners', 'event-banners', true)
ON CONFLICT (id) DO NOTHING;

-- Public read (anonymous + authenticated)
CREATE POLICY "public_read_event_banners" ON storage.objects
  FOR SELECT USING (bucket_id = 'event-banners');

-- Only organizers can upload banners
CREATE POLICY "organizer_upload_event_banner" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- Only organizers can replace/update banners
CREATE POLICY "organizer_update_event_banner" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- Only organizers can delete banners
CREATE POLICY "organizer_delete_event_banner" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- 7. SERVER-SIDE LOGIN RATE LIMITING
-- ============================================================
-- Tracks failed login attempts per identifier (full login email).
-- Accessed exclusively via the login-rate-limit Edge Function using the
-- service role key. No client-facing RLS policies — direct client access
-- is intentionally blocked.

CREATE TABLE IF NOT EXISTS public.login_rate_limits (
  identifier   TEXT        NOT NULL,
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_rl_lookup
  ON public.login_rate_limits (identifier, attempted_at DESC);

ALTER TABLE public.login_rate_limits ENABLE ROW LEVEL SECURITY;
-- No policies defined: anon/authenticated roles cannot read or write this table.

-- 8. ANNOUNCEMENTS ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Any authenticated user (students, organizers) can read announcements
CREATE POLICY "authenticated_read_announcements" ON public.announcements
  FOR SELECT USING (auth.role() = 'authenticated');

-- Only organizers can create announcements
CREATE POLICY "organizer_insert_announcements" ON public.announcements
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- Only organizers can delete announcements
CREATE POLICY "organizer_delete_announcements" ON public.announcements
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- 9. REGISTRATION UPDATE GUARDRAIL
-- ============================================================
-- student_update_own (section 2) only restricts WHICH ROW a student may
-- update, not which columns/values — RLS can't express that on its own.
-- Without this trigger, a student's own already-authenticated session could
-- set status straight to 'checked_in' (or fabricate a selfie_url) with a
-- plain .update() call, bypassing the QR-scan -> confirm -> selfie flow
-- entirely. Applied directly via the Supabase SQL editor on 2026-07-23;
-- captured here so the schema has one source of truth (see the audit's
-- "conflicting SQL drafts" finding for why that matters).

CREATE OR REPLACE FUNCTION public.enforce_registration_update_rules()
RETURNS TRIGGER AS $$
BEGIN
  -- Organizers may perform any legitimate transition (scan, confirm, check in).
  IF EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid()) THEN
    RETURN NEW;
  END IF;

  -- Anyone else (i.e. the student themselves) may ONLY submit a selfie:
  -- photo_required -> photo_submitted, nothing else changes.
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

CREATE TRIGGER trg_enforce_registration_update_rules
  BEFORE UPDATE ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_registration_update_rules();

-- 10. REGISTRATION INSERT GUARDRAIL + AUTOMATIC PARTICIPANT COUNTER
-- ============================================================
-- Two things used to be enforced only by the Flutter client, with nothing
-- backing them up server-side:
--   1. event_status / registration_deadline / max_participants were checked
--      in Dart before inserting a registration, but a direct insert
--      (bypassing the app) skipped all three checks entirely.
--   2. increment_participant_count / decrement_participant_count (section 5)
--      were independently callable by ANY authenticated user for ANY
--      event_id, with no check they corresponded to a real registration.
-- This section replaces both: a BEFORE INSERT trigger enforces the rules
-- server-side (with FOR UPDATE locking to close the concurrent-registration
-- race condition, not just the deliberate-bypass case), and the counter is
-- now maintained automatically as a side effect of a real insert/delete,
-- never independently callable. Applied 2026-07-23.

CREATE OR REPLACE FUNCTION public.enforce_registration_insert_rules()
RETURNS TRIGGER AS $$
DECLARE
  ev RECORD;
BEGIN
  SELECT event_status, max_participants, current_participants, registration_deadline
    INTO ev
    FROM public.events
    WHERE event_id = NEW.event_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event not found.';
  END IF;

  IF ev.event_status IN ('cancelled', 'completed') THEN
    RAISE EXCEPTION 'Registration is closed — this event is no longer accepting sign-ups.';
  END IF;

  IF ev.registration_deadline IS NOT NULL AND now() > ev.registration_deadline THEN
    RAISE EXCEPTION 'Registration is closed — the deadline has passed.';
  END IF;

  IF ev.max_participants IS NOT NULL AND ev.max_participants > 0
     AND ev.current_participants >= ev.max_participants THEN
    RAISE EXCEPTION 'This event is full — no spots remaining.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_enforce_registration_insert_rules ON public.registrations;
CREATE TRIGGER trg_enforce_registration_insert_rules
  BEFORE INSERT ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_registration_insert_rules();

CREATE OR REPLACE FUNCTION public.maintain_participant_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.events
    SET current_participants = current_participants + 1
    WHERE event_id = NEW.event_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.events
    SET current_participants = GREATEST(current_participants - 1, 0)
    WHERE event_id = OLD.event_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_maintain_participant_count ON public.registrations;
CREATE TRIGGER trg_maintain_participant_count
  AFTER INSERT OR DELETE ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.maintain_participant_count();

-- The old RPCs are now fully replaced by the triggers above, and were the
-- exact thing flagged as freely callable by anyone for any event with no
-- ownership or cap check — drop them rather than leave unused, still-
-- dangerous functions around.
DROP FUNCTION IF EXISTS public.increment_participant_count(UUID);
DROP FUNCTION IF EXISTS public.decrement_participant_count(UUID);

-- 11. ANNOUNCEMENT LENGTH LIMITS
-- ============================================================
-- title/message are plain TEXT with no length cap in any schema source —
-- the 100/1000 character limits shown in the app are a Flutter
-- TextField.maxLength UI nicety only; nothing server-side re-checks them,
-- so a direct insert (bypassing the app) could post arbitrary-length
-- content that every screen rendering announcements would then have to
-- display as-is. These CHECK constraints make the same 100/1000 limits
-- the app already advertises to organizers actually enforced.

ALTER TABLE public.announcements
  DROP CONSTRAINT IF EXISTS announcements_title_length_chk,
  DROP CONSTRAINT IF EXISTS announcements_message_length_chk;

ALTER TABLE public.announcements
  ADD CONSTRAINT announcements_title_length_chk   CHECK (char_length(title)   <= 100),
  ADD CONSTRAINT announcements_message_length_chk CHECK (char_length(message) <= 1000);
