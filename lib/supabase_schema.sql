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
  status            TEXT        NOT NULL DEFAULT 'pending'
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

-- 5. ATOMIC PARTICIPANT COUNTER RPCs
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
