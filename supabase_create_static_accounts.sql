-- supabase_create_static_accounts.sql
-- Creates two static accounts (student + organizer) and their profile rows.
-- Run this in the Supabase SQL editor (Project -> SQL Editor -> New query).
-- Requires the pgcrypto extension (used for bcrypt hashing via crypt/gen_salt).

-- LRNs (from user):
-- student: LRN 202400001 / Cav242005
-- organizer: LRN 202400002 / Cav242005

-- IMPORTANT: this script inserts directly into auth.users. Run only in
-- a trusted/dev environment; don't expose service-role secrets.

-- Ensure pgcrypto is available
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) STUDENT ACCOUNT
DO $$
DECLARE
  uid UUID;
BEGIN
  -- Check if a user with that identifier already exists; reuse its id if so
  SELECT id INTO uid FROM auth.users WHERE email = lower('student-lrn-202400001@example.com') LIMIT 1;

  IF uid IS NULL THEN
    uid := gen_random_uuid();
    INSERT INTO auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_user_meta_data, raw_app_meta_data, created_at, updated_at
    ) VALUES (
      uid,
      'authenticated',
      'authenticated',
      lower('student-lrn-202400001@example.com'),
      crypt('Cav242005', gen_salt('bf')),
      now(),
      jsonb_build_object('full_name', 'Static Student'),
      '{}'::jsonb,
      now(),
      now()
    );
    RAISE NOTICE 'Created auth user (student) %', uid;
  ELSE
    RAISE NOTICE 'Auth user already exists for student: %', uid;
  END IF;

  -- Insert student profile if missing (table: public.students expects a user_id column)
  IF NOT EXISTS (SELECT 1 FROM public.students WHERE user_id = uid) THEN
    INSERT INTO public.students (
      user_id, student_id, lrn, full_name, is_active, created_at, updated_at
    ) VALUES (
      uid,
      'AA0001', -- static student id
      '123456 - 26 - 0001',
      'Static Student',
      true,
      now(),
      now()
    );
    RAISE NOTICE 'Inserted student profile for %', uid;
  ELSE
    RAISE NOTICE 'Student profile already exists for %', uid;
  END IF;
END
$$ LANGUAGE plpgsql;

-- 2) ORGANIZER ACCOUNT
DO $$
DECLARE
  oid UUID;
BEGIN
  SELECT id INTO oid FROM auth.users WHERE email = lower('organizer-lrn-202400002@example.com') LIMIT 1;

  IF oid IS NULL THEN
    oid := gen_random_uuid();
    INSERT INTO auth.users (
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_user_meta_data, raw_app_meta_data, created_at, updated_at
    ) VALUES (
      oid,
      'authenticated',
      'authenticated',
      lower('organizer-lrn-202400002@example.com'),
      crypt('Cav242005', gen_salt('bf')),
      now(),
      jsonb_build_object('full_name', 'Static Organizer'),
      '{}'::jsonb,
      now(),
      now()
    );
    RAISE NOTICE 'Created auth user (organizer) %', oid;
  ELSE
    RAISE NOTICE 'Auth user already exists for organizer: %', oid;
  END IF;

  -- Insert organizer profile if missing (table: public.organizers expects organizer_id)
  IF NOT EXISTS (SELECT 1 FROM public.organizers WHERE organizer_id = oid) THEN
    INSERT INTO public.organizers (
      organizer_id, lrn, full_name, is_active, created_at, updated_at
    ) VALUES (
      oid,
      '123456 - 26 - 0002',
      'Static Organizer',
      true,
      now(),
      now()
    );
    RAISE NOTICE 'Inserted organizer profile for %', oid;
  ELSE
    RAISE NOTICE 'Organizer profile already exists for %', oid;
  END IF;
END
$$ LANGUAGE plpgsql;

-- 3) Optional: grant access or insert into user_roles so RLS treats organizer as role
DO $$
DECLARE
  oid UUID;
BEGIN
  SELECT id INTO oid FROM auth.users WHERE email = lower('organizer-lrn-202400002@example.com') LIMIT 1;
  IF oid IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = oid AND role = 'organizer') THEN
      INSERT INTO public.user_roles (user_id, role, created_at) VALUES (oid, 'organizer', now());
      RAISE NOTICE 'Assigned organizer role to %', oid;
    END IF;
  END IF;
END
$$ LANGUAGE plpgsql;

-- End of script
