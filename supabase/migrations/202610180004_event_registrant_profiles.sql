-- Let organizers see the profile of a student registered for one of THEIR
-- events — and nothing else. Organizers have no read access to the students
-- table; this view exposes only the fields the organizer web "Student
-- details" panel needs, and only for students with a registration in an event
-- the calling organizer owns (same pattern as organizer_directory).
--
-- Requires the earlier migrations that added first_name, last_name, strand
-- and section to public.students.
CREATE OR REPLACE VIEW public.event_registrant_profiles
WITH (security_barrier = true) AS
SELECT s.user_id,
       s.lrn,
       s.full_name,
       s.first_name,
       s.last_name,
       s.year_level,
       s.strand,
       s.section,
       s.profile_image_url
FROM public.students s
WHERE s.user_id IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.registrations r
    JOIN public.events e     ON e.event_id = r.event_id
    JOIN public.organizers o ON o.organizer_id = e.organizer_id
    WHERE r.student_user_id = s.user_id
      AND o.user_id = auth.uid()
  );

REVOKE ALL ON public.event_registrant_profiles FROM anon;
GRANT SELECT ON public.event_registrant_profiles TO authenticated;
