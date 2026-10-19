-- Class section (e.g. "Sampaguita"), as listed on the registrar's SF1.
-- Filled by the admin Students tab (Add/Edit dialog and registrar import).
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS section text;
