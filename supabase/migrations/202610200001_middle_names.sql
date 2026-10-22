-- Add a middle name to students and organizers, next to the first_name /
-- last_name parts added in 202610180001 and 202610180002. Optional: NULL
-- means no middle name (or not entered yet). full_name is unchanged and is
-- still the display value written by the admin dialogs.
-- Existing rows start NULL; nothing is split out of full_name automatically.
-- Safe to rerun.
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS middle_name text;

ALTER TABLE public.organizers
  ADD COLUMN IF NOT EXISTS middle_name text;

COMMENT ON COLUMN public.students.middle_name   IS 'Optional middle name; NULL when none.';
COMMENT ON COLUMN public.organizers.middle_name IS 'Optional middle name; NULL when none.';

-- Let the Supabase API see the new columns right away.
NOTIFY pgrst, 'reload schema';
