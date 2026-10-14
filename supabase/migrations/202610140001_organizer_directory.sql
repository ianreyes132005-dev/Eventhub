-- Allow authenticated students to see announcement authors without exposing
-- other organizer profile fields or changing organizer profile RLS policies.
CREATE OR REPLACE VIEW public.organizer_directory
WITH (security_barrier = true) AS
SELECT user_id, full_name
FROM public.organizers
WHERE user_id IS NOT NULL;

REVOKE ALL ON public.organizer_directory FROM anon;
GRANT SELECT ON public.organizer_directory TO authenticated;
