-- ═════════════════════════════════════════════════════════════════════════════
-- Organizers only see and change registrations of their own events.
--
-- 202610150003 rolled back all of 202610150001, which also brought back the
-- broad policies organizer_select_all and organizer_update_status: any
-- signed-in organizer could read and change every registration and open
-- every check-in selfie. This restores only the "own events" part of 150001.
-- Its stricter selfie-upload rules and approval changes stay rolled back.
--
-- The apps already show organizers only their own events' registrations, so
-- their screens don't change. Scanning a ticket for another organizer's event
-- now finds nothing instead of opening it for check-in.
-- Admins keep admin_select_all_registrations, admin_update_registrations and
-- admin_read_selfies; students keep their own policies.
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── Ownership checks ─────────────────────────────────────────────────────────
-- SECURITY DEFINER: they read events and organizers without those tables' own
-- policies. A policy that queries a table whose policies query back would fail
-- with "infinite recursion detected in policy" for every user.

-- The signed-in organizer runs this event.
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

-- The selfie at this storage path ({student_user_id}/{registration_id}.jpg,
-- see RegistrationService.uploadSelfie) belongs to one of the signed-in
-- organizer's events.
CREATE OR REPLACE FUNCTION public.organizer_owns_selfie(p_path text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organizers o
    JOIN public.events e ON e.organizer_id = o.organizer_id
    JOIN public.registrations r ON r.event_id = e.event_id
    WHERE o.user_id = auth.uid()
      AND p_path = r.student_user_id::text || '/' || r.id::text || '.jpg'
  );
$$;

-- ── Read ─────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "organizer_select_all" ON public.registrations;
DROP POLICY IF EXISTS "organizer_select_own_event_registrations" ON public.registrations;
CREATE POLICY "organizer_select_own_event_registrations"
  ON public.registrations
  FOR SELECT
  USING (public.organizer_owns_event(event_id));

-- ── Change: scan, request a selfie, check in, reject ─────────────────────────
DROP POLICY IF EXISTS "organizer_update_status" ON public.registrations;
DROP POLICY IF EXISTS "organizer_update_own_event_registrations" ON public.registrations;
CREATE POLICY "organizer_update_own_event_registrations"
  ON public.registrations
  FOR UPDATE
  USING (public.organizer_owns_event(event_id))
  WITH CHECK (public.organizer_owns_event(event_id));

-- ── Delete (202610230001), now through the same check ────────────────────────
DROP POLICY IF EXISTS "organizer_delete_own_event_registrations" ON public.registrations;
CREATE POLICY "organizer_delete_own_event_registrations"
  ON public.registrations
  FOR DELETE
  USING (status <> 'checked_in' AND public.organizer_owns_event(event_id));

-- ── Check-in selfies ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "organizer_read_selfies" ON storage.objects;
CREATE POLICY "organizer_read_selfies"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'selfies' AND public.organizer_owns_selfie(name));

NOTIFY pgrst, 'reload schema';
