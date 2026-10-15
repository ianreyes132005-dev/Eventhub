-- Keep attendance records and selfie evidence scoped to the event owner.
DROP POLICY IF EXISTS "organizer_select_all" ON public.registrations;
CREATE POLICY "organizer_select_own_event_registrations"
  ON public.registrations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.events e
      JOIN public.organizers o ON o.organizer_id = e.organizer_id
      WHERE e.event_id = registrations.event_id
        AND o.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "organizer_update_status" ON public.registrations;
CREATE POLICY "organizer_update_own_event_registrations"
  ON public.registrations
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.events e
      JOIN public.organizers o ON o.organizer_id = e.organizer_id
      WHERE e.event_id = registrations.event_id
        AND o.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.events e
      JOIN public.organizers o ON o.organizer_id = e.organizer_id
      WHERE e.event_id = registrations.event_id
        AND o.user_id = auth.uid()
    )
  );

-- Students can only upload or replace the one expected selfie for an active
-- photo request. The request timestamp prevents an older object from being
-- reused as evidence for a newer check-in request.
-- This binds evidence to a registration but does not prove live camera capture.
ALTER TABLE public.registrations
  ADD COLUMN IF NOT EXISTS photo_requested_at TIMESTAMPTZ;

ALTER TABLE public.registrations
  DISABLE TRIGGER trg_enforce_registration_update_rules;

UPDATE public.registrations
SET photo_requested_at = NOW()
WHERE status = 'photo_required'
  AND photo_requested_at IS NULL;

ALTER TABLE public.registrations
  ENABLE TRIGGER trg_enforce_registration_update_rules;

DROP POLICY IF EXISTS "student_upload_selfie" ON storage.objects;
CREATE POLICY "student_upload_selfie"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'selfies'
    AND EXISTS (
      SELECT 1
      FROM public.registrations r
      WHERE r.student_user_id = auth.uid()
        AND r.status = 'photo_required'
        AND r.photo_requested_at IS NOT NULL
        AND name = r.student_user_id::TEXT || '/' || r.id::TEXT || '.jpg'
    )
  );

DROP POLICY IF EXISTS "student_update_selfie" ON storage.objects;
CREATE POLICY "student_update_selfie"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'selfies'
    AND EXISTS (
      SELECT 1
      FROM public.registrations r
      WHERE r.student_user_id = auth.uid()
        AND r.status = 'photo_required'
        AND r.photo_requested_at IS NOT NULL
        AND name = r.student_user_id::TEXT || '/' || r.id::TEXT || '.jpg'
    )
  )
  WITH CHECK (
    bucket_id = 'selfies'
    AND EXISTS (
      SELECT 1
      FROM public.registrations r
      WHERE r.student_user_id = auth.uid()
        AND r.status = 'photo_required'
        AND r.photo_requested_at IS NOT NULL
        AND name = r.student_user_id::TEXT || '/' || r.id::TEXT || '.jpg'
    )
  );

DROP POLICY IF EXISTS "student_read_own_selfie" ON storage.objects;
CREATE POLICY "student_read_own_selfie"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'selfies'
    AND EXISTS (
      SELECT 1
      FROM public.registrations r
      WHERE r.student_user_id = auth.uid()
        AND name = r.student_user_id::TEXT || '/' || r.id::TEXT || '.jpg'
    )
  );

DROP POLICY IF EXISTS "organizer_read_selfies" ON storage.objects;
CREATE POLICY "organizer_read_selfies"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'selfies'
    AND EXISTS (
      SELECT 1
      FROM public.registrations r
      JOIN public.events e ON e.event_id = r.event_id
      JOIN public.organizers o ON o.organizer_id = e.organizer_id
      WHERE r.selfie_url = name
        AND name = r.student_user_id::TEXT || '/' || r.id::TEXT || '.jpg'
        AND o.user_id = auth.uid()
    )
  );

CREATE OR REPLACE FUNCTION public.enforce_registration_update_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  is_admin BOOLEAN;
  is_event_organizer BOOLEAN;
  expected_selfie_path TEXT;
BEGIN
  is_admin := EXISTS (
    SELECT 1
    FROM public.admins
    WHERE user_id = auth.uid()
  );
  IF is_admin THEN
    RETURN NEW;
  END IF;

  is_event_organizer := EXISTS (
    SELECT 1
    FROM public.organizers o
    JOIN public.events e ON e.organizer_id = o.organizer_id
    WHERE o.user_id = auth.uid()
      AND e.event_id = OLD.event_id
  );

  IF is_event_organizer THEN
    IF NEW.status = 'photo_required' AND OLD.status <> 'photo_required' THEN
      NEW.photo_requested_at := clock_timestamp();
      NEW.selfie_url := NULL;
    END IF;
    RETURN NEW;
  END IF;

  expected_selfie_path := OLD.student_user_id::TEXT || '/' || OLD.id::TEXT || '.jpg';

  IF OLD.status = 'photo_required'
     AND NEW.status = 'photo_submitted'
     AND NEW.selfie_url = expected_selfie_path
     AND OLD.photo_requested_at IS NOT NULL
     AND (to_jsonb(NEW) - ARRAY['status', 'selfie_url'])
         IS NOT DISTINCT FROM
         (to_jsonb(OLD) - ARRAY['status', 'selfie_url'])
     AND EXISTS (
       SELECT 1
       FROM storage.objects o
       WHERE o.bucket_id = 'selfies'
         AND o.name = expected_selfie_path
         AND o.updated_at >= OLD.photo_requested_at
     )
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'You are not allowed to make this change to a registration.';
END;
$$;

-- Any material content change to an approved event requires another admin
-- review. Lifecycle status changes are not content edits; editing a rejected
-- event also resubmits it instead of leaving it rejected.
CREATE OR REPLACE FUNCTION public.guard_events_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  is_admin BOOLEAN;
  is_owner BOOLEAN;
  material_details_changed BOOLEAN;
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

  is_owner := OLD.organizer_id = (
    SELECT o.organizer_id
    FROM public.organizers o
    WHERE o.user_id = auth.uid()
  );

  material_details_changed :=
    ROW(
      NEW.title,
      NEW.description,
      NEW.location,
      NEW.event_type,
      NEW.event_date,
      NEW.end_date,
      NEW.start_time,
      NEW.end_time,
      NEW.registration_deadline,
      NEW.max_participants,
      NEW.event_image_url
    ) IS DISTINCT FROM ROW(
      OLD.title,
      OLD.description,
      OLD.location,
      OLD.event_type,
      OLD.event_date,
      OLD.end_date,
      OLD.start_time,
      OLD.end_time,
      OLD.registration_deadline,
      OLD.max_participants,
      OLD.event_image_url
    );

  IF is_owner
     AND (
       OLD.approval_status = 'rejected'
       OR (OLD.approval_status = 'approved' AND material_details_changed)
     )
  THEN
    NEW.approval_status := 'pending';
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
$$;
