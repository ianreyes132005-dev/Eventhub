-- Restore the database behavior that was in place before
-- 202610150001_attendance_security_hardening.sql.
DROP POLICY IF EXISTS "organizer_select_own_event_registrations"
  ON public.registrations;
CREATE POLICY "organizer_select_all"
  ON public.registrations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.organizers
      WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "organizer_update_own_event_registrations"
  ON public.registrations;
CREATE POLICY "organizer_update_status"
  ON public.registrations
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.organizers
      WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "student_upload_selfie" ON storage.objects;
CREATE POLICY "student_upload_selfie"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'selfies'
    AND auth.uid()::TEXT = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "student_update_selfie" ON storage.objects;
CREATE POLICY "student_update_selfie"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'selfies'
    AND auth.uid()::TEXT = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "student_read_own_selfie" ON storage.objects;
CREATE POLICY "student_read_own_selfie"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'selfies'
    AND auth.uid()::TEXT = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "organizer_read_selfies" ON storage.objects;
CREATE POLICY "organizer_read_selfies"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'selfies'
    AND EXISTS (
      SELECT 1
      FROM public.organizers
      WHERE user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.enforce_registration_update_rules()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.organizers
    WHERE user_id = auth.uid()
  ) THEN
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

ALTER TABLE public.registrations
  DROP COLUMN IF EXISTS photo_requested_at;

CREATE OR REPLACE FUNCTION public.guard_events_approval()
RETURNS TRIGGER AS $$
DECLARE
  is_admin BOOLEAN;
  is_owner BOOLEAN;
BEGIN
  is_admin := EXISTS (
    SELECT 1 FROM public.admins WHERE user_id = auth.uid()
  );
  IF is_admin THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.approval_status := 'pending';
    NEW.rejection_reason := NULL;
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    RETURN NEW;
  END IF;

  is_owner := NEW.organizer_id = (
    SELECT organizer_id
    FROM public.organizers
    WHERE user_id = auth.uid()
  );

  IF is_owner
     AND OLD.approval_status = 'rejected'
     AND NEW.approval_status = 'pending'
  THEN
    NEW.rejection_reason := NULL;
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    RETURN NEW;
  END IF;

  NEW.approval_status := OLD.approval_status;
  NEW.rejection_reason := OLD.rejection_reason;
  NEW.reviewed_by := OLD.reviewed_by;
  NEW.reviewed_at := OLD.reviewed_at;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
