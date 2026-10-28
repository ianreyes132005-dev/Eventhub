-- ═════════════════════════════════════════════════════════════════════════════
-- When a registration's status last changed.
--
-- The student's notifications "Selfie required", "Photo received" and
-- "Registration declined" showed the registration time: nothing recorded when
-- the organizer asked for the photo or made the decision, so a request made a
-- minute ago read "3d ago" and sat low in the list.
--
--   • registrations.status_changed_at is set by the database — when the
--     registration is made and whenever its status changes. The app never
--     sends it, and a value sent anyway is ignored.
--   • Registrations from before this migration keep it empty; the app uses
--     the check-in or registration time for those, as before
--     (StudentNotifications.build in
--     lib/features/student/notifications/student_feed.dart).
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.registrations
  ADD COLUMN IF NOT EXISTS status_changed_at timestamptz;

-- Runs after trg_enforce_registration_update_rules (triggers fire in name
-- order), so those rules see the row exactly as it was sent.
CREATE OR REPLACE FUNCTION public.stamp_registration_status_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.status_changed_at := now();
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.status_changed_at := now();
  ELSE
    NEW.status_changed_at := OLD.status_changed_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_registration_status_change ON public.registrations;
CREATE TRIGGER trg_stamp_registration_status_change
  BEFORE INSERT OR UPDATE ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.stamp_registration_status_change();

NOTIFY pgrst, 'reload schema';
