-- Store an organizer's name as separate parts, as entered in the admin
-- Add/Edit Organizer dialog. full_name stays the display value
-- ("First Last") shown on event cards, announcements, logs and the
-- organizer dashboards, and is written alongside these on every save.
-- Existing rows start NULL; the admin dialog pre-fills a best-guess split
-- of full_name the first time such an organizer is edited.
ALTER TABLE public.organizers
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name  text;
