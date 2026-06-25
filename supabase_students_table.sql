-- Supabase SQL for Students Table
-- Compatible with PostgreSQL and Supabase conventions
-- Updated: LRN is now the PRIMARY KEY (simplified from id, student_id, lrn)

-- Enable UUID/crypto extension (use pgcrypto on Supabase)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create students table
-- LRN (Learner Registration Number) is the PRIMARY KEY
CREATE TABLE public.students (
    lrn VARCHAR(20) PRIMARY KEY,
    user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name VARCHAR(200) NOT NULL,
    profile_image_url TEXT,
    year_level INTEGER CHECK (year_level >= 1 AND year_level <= 6),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Create indexes for better performance
CREATE INDEX idx_students_user_id ON public.students(user_id);
CREATE INDEX idx_students_lrn ON public.students(lrn);
CREATE INDEX idx_students_year_level ON public.students(year_level);
CREATE INDEX idx_students_created_at ON public.students(created_at);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = TIMEZONE('utc'::text, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updated_at
CREATE TRIGGER handle_students_updated_at
    BEFORE UPDATE ON public.students
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- Row Level Security (RLS) - Enable RLS
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

-- Table: user_roles
-- Small helper table used by RLS policies to determine user roles
CREATE TABLE IF NOT EXISTS public.user_roles (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);

COMMENT ON TABLE public.user_roles IS 'Mapping of auth.users to roles (organizer, admin, etc)';

-- Grant readonly access to authenticated users so policies can query roles
GRANT SELECT ON public.user_roles TO authenticated;

-- RLS Policies

-- Policy: Students can view their own profile
CREATE POLICY "Students can view own profile" ON public.students
    FOR SELECT
    USING (auth.uid() = user_id);

-- Policy: Students can update their own profile
CREATE POLICY "Students can update own profile" ON public.students
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Policy: Allow authenticated users to insert their own student profile
CREATE POLICY "Users can create own student profile" ON public.students
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Policy: Organizers/Admins can view all student profiles (assuming you have a role system)
-- Note: You'll need to adjust this based on your role system
CREATE POLICY "Organizers can view all students" ON public.students
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('organizer', 'admin')
        )
    );

-- Policy: Organizers/Admins can update student profiles
CREATE POLICY "Organizers can update students" ON public.students
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_id = auth.uid()
            AND role IN ('organizer', 'admin')
        )
    );

-- Sample data insertion (for testing - remove in production)
INSERT INTO public.students (
    lrn,
    user_id,
    full_name,
    year_level,
    is_active
) VALUES
(
    '123456 - 26 - 0001',
    '00000000-0000-0000-0000-000000000001'::uuid,
    'John Doe',
    '+639123456789',
    'Computer Science',
    3,
    '2002-05-15',
    '123 Main St, University City',
    'Jane Doe',
    '+639123456790',
    true
),
(
    '123456 - 26 - 0002',
    '00000000-0000-0000-0000-000000000002'::uuid,
    'Jane Smith',
    '+639123456791',
    'Information Technology',
    2,
    '2003-08-22',
    '456 Oak Ave, University City',
    'Bob Smith',
    '+639123456792',
    true
),
(
    '123456 - 26 - 0003',
    '00000000-0000-0000-0000-000000000003'::uuid,
    'Mike Johnson',
    '+639123456793',
    'Business Administration',
    4,
    '2001-12-10',
    '789 Pine Rd, University City',
    'Sarah Johnson',
    '+639123456794',
    true
);

-- Create a view for student profiles with auth user info
CREATE VIEW public.student_profiles AS
SELECT
    s.lrn,
    s.user_id,
    s.full_name,
    s.profile_image_url,
    s.year_level,
    s.is_active,
    s.created_at,
    s.updated_at,
    au.last_sign_in_at,
    au.created_at as auth_created_at
FROM public.students s
LEFT JOIN auth.users au ON s.user_id = au.id;

-- Grant permissions (adjust based on your needs)
GRANT SELECT, INSERT, UPDATE ON public.students TO authenticated;
GRANT SELECT ON public.student_profiles TO authenticated;

-- Comments for documentation
COMMENT ON TABLE public.students IS 'Student profiles linked to Supabase auth users';
COMMENT ON COLUMN public.students.lrn IS 'Learner Registration Number - PRIMARY KEY (format: XXXXXX - YY - ZZZZ)';
COMMENT ON COLUMN public.students.user_id IS 'References auth.users(id) for authentication';
COMMENT ON COLUMN public.students.year_level IS 'Academic year level (1-6)';
COMMENT ON VIEW public.student_profiles IS 'Student profiles with authentication metadata';