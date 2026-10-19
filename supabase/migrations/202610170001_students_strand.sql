-- Senior High strand for students (HUMSS / GAS / STEM).
-- Only meaningful for Grade 11–12; Junior High rows keep it NULL.
-- Existing SHS rows start NULL and are assigned from the admin
-- Students tab (they show under "No strand" until then).
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS strand text;

ALTER TABLE public.students
  DROP CONSTRAINT IF EXISTS students_strand_check;
ALTER TABLE public.students
  ADD CONSTRAINT students_strand_check
  CHECK (strand IS NULL OR strand IN ('HUMSS', 'GAS', 'STEM'));
