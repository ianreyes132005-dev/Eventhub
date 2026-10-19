-- Store a student's name as separate parts, as entered in the admin
-- Add/Edit Student dialog. full_name stays the display value
-- ("First Last") used by greetings, avatars, tickets and registrations,
-- and is written alongside these on every save.
-- Existing rows start NULL; the admin dialog pre-fills a best-guess split
-- of full_name the first time such a student is edited.
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name  text;
