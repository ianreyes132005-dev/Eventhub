-- ===========================================
-- 1. SETUP & EXTENSIONS
-- ===========================================
-- Enable crypto extension; prefer pgcrypto on Supabase
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create the sequence for your custom Student IDs (AA0001)
CREATE SEQUENCE IF NOT EXISTS student_id_seq START 1;

-- Function to generate the AA0001 format
CREATE OR REPLACE FUNCTION generate_custom_student_id()
RETURNS TEXT AS $$
BEGIN
    RETURN 'AA' || LPAD(nextval('student_id_seq')::text, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- Function to handle updated_at timestamps
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = TIMEZONE('utc'::text, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- 2. CORE USER TABLES
-- ===========================================

-- Students: Primary Key is the custom AA0001 ID
CREATE TABLE public.students (
    id UUID UNIQUE DEFAULT auth.uid(), -- The hidden link to Supabase Auth
    student_id VARCHAR(20) PRIMARY KEY DEFAULT generate_custom_student_id(),
    lrn VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Organizers: Primary Key is the UUID from Auth
CREATE TABLE public.organizers (
    organizer_id UUID PRIMARY KEY DEFAULT auth.uid(),
    lrn VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    organization VARCHAR(100),
    contact_number VARCHAR(15),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ===========================================
-- 3. EVENTS & REGISTRATIONS
-- ===========================================

-- Drop the existing events table if you want to recreate it
DROP TABLE IF EXISTS public.events CASCADE;

-- Create the updated Events table
CREATE TABLE public.events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    event_type VARCHAR(100), 
    organizer_id VARCHAR(20) NOT NULL REFERENCES public.organizers(organizer_id) ON DELETE CASCADE,
    location VARCHAR(255),
    event_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    registration_deadline TIMESTAMP WITH TIME ZONE, 
    max_participants INT,
    current_participants INT DEFAULT 0,
    event_status TEXT DEFAULT 'upcoming' CHECK (event_status IN ('upcoming', 'ongoing', 'completed', 'cancelled')),
    event_image_url VARCHAR(500), 
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Create index for faster queries
CREATE INDEX idx_events_organizer_id ON public.events(organizer_id);
CREATE INDEX idx_events_event_date ON public.events(event_date);
CREATE INDEX idx_events_status ON public.events(event_status);

-- Create trigger for automatic updated_at
CREATE TRIGGER handle_updated_at_events
    BEFORE UPDATE ON public.events
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

CREATE TABLE public.registrations (
    registration_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id VARCHAR(20) NOT NULL REFERENCES public.students(student_id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES public.events(event_id) ON DELETE CASCADE,
    qr_code_data TEXT NOT NULL,
    registration_status TEXT DEFAULT 'registered' CHECK (registration_status IN ('registered', 'checked_in', 'cancelled')),
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    checked_in_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(student_id, event_id)
);

-- ===========================================
-- 4. UTILITY TABLES
-- ===========================================

CREATE TABLE public.announcements (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    organizer_id UUID NOT NULL REFERENCES public.organizers(organizer_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE public.notifications (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL, -- Holds student_id or organizer_id
    user_type TEXT NOT NULL CHECK (user_type IN ('student', 'organizer')),
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ===========================================
-- 5. TRIGGERS & SECURITY
-- ===========================================

-- Trigger to validate notification recipients
CREATE OR REPLACE FUNCTION validate_notification_recipient()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_type = 'student' THEN
        IF NOT EXISTS (SELECT 1 FROM public.students WHERE student_id = NEW.user_id) THEN
            RAISE EXCEPTION 'Student ID % does not exist', NEW.user_id;
        END IF;
    ELSIF NEW.user_type = 'organizer' THEN
        IF NOT EXISTS (SELECT 1 FROM public.organizers WHERE organizer_id::text = NEW.user_id) THEN
            RAISE EXCEPTION 'Organizer ID % does not exist', NEW.user_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_notification
BEFORE INSERT ON public.notifications
FOR EACH ROW EXECUTE FUNCTION validate_notification_recipient();

-- Enable RLS
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registrations ENABLE ROW LEVEL SECURITY;

-- Simple Policies for Students and Organizers
CREATE POLICY "Students view own profile" ON public.students FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Organizers view own profile" ON public.organizers FOR SELECT USING (auth.uid() = organizer_id);

-- RLS Policies for Events (Row Level Security)
-- 1. Anyone logged in can view the events
CREATE POLICY "Anyone can view events" ON public.events
    FOR SELECT TO authenticated USING (true);

-- 2. Organizers can create their own events
CREATE POLICY "Organizers can create events" ON public.events
    FOR INSERT TO authenticated
    WITH CHECK (
        organizer_id IN (
            SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid()
        )
    );

-- 3. Organizers can update their own events
CREATE POLICY "Organizers can update own events" ON public.events
    FOR UPDATE TO authenticated
    USING (
        organizer_id IN (
            SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid()
        )
    );

-- 4. Organizers can delete their own events
CREATE POLICY "Organizers can delete own events" ON public.events
    FOR DELETE TO authenticated
    USING (
        organizer_id IN (
            SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid()
        )
    );

-- ===========================================
-- 6. STORAGE POLICIES (Event Banners Bucket)
-- ===========================================
-- 
-- FRONTEND UPLOAD WORKFLOW:
-- 
-- STEP 1: User selects banner image
--   - File is picked via file picker (FilePicker in Flutter, input in web)
--   - Stored in temporary variable
-- 
-- STEP 2: Generate unique filename to prevent overwrites
--   - Dart:   'banner_${DateTime.now().millisecondsSinceEpoch}_${filename}'
--   - JS:     `${crypto.randomUUID()}.${fileExt}`
--   - Ensures no conflicts between different organizers
-- 
-- STEP 3: Upload file to Supabase Storage bucket 'event-banners'
--   - Dart:   supabase.storage.from('event-banners').uploadBinary(fileName, fileBytes)
--   - JS:     supabase.storage.from('event-banners').upload(filePath, file)
--   - Returns error if bucket policy fails or upload fails
-- 
-- STEP 4: Get public URL for the uploaded banner
--   - Dart:   supabase.storage.from('event-banners').getPublicUrl(fileName)
--   - JS:     supabase.storage.from('event-banners').getPublicUrl(filePath)
--   - This URL is stored in event_image_url database field
-- 
-- STEP 5: Insert event into database with banner URL
--   - All event fields including event_image_url are saved
--   - RLS policies ensure only organizers can create events
--   - Banner is now publicly accessible at the returned URL
-- 
-- JavaScript Example:
-- ```javascript
-- const file = event.target.files[0];
-- const fileExt = file.name.split('.').pop();
-- const fileName = `${crypto.randomUUID()}.${fileExt}`;
-- 
-- const { data: uploadData, error: uploadError } = await supabase.storage
--   .from('event-banners')
--   .upload(fileName, file);
-- 
-- const { data: urlData } = supabase.storage
--   .from('event-banners')
--   .getPublicUrl(fileName);
-- const finalImageUrl = urlData.publicUrl;
-- 
-- const { data: eventData } = await supabase
--   .from('events')
--   .insert([{
--     title: 'Annual Tech Symposium',
--     organizer_id: 'JJ0001',
--     event_date: '2026-06-15',
--     start_time: '08:00:00',
--     end_time: '17:00:00',
--     event_image_url: finalImageUrl  // <-- URL is saved here!
--   }]);
-- ```

-- 1. Policy to allow ANYONE to view/download the event banners
CREATE POLICY "Public Read Access for Event Banners"
ON storage.objects FOR SELECT
USING (bucket_id = 'event-banners');

-- 2. Policy to allow ONLY Authenticated users (Organizers) to upload
CREATE POLICY "Organizers can upload banners"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'event-banners'
);

-- 3. Policy to allow Organizers to update/overwrite their own uploads
CREATE POLICY "Organizers can update own banners"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'event-banners' AND auth.uid() = owner);

-- 4. Policy to allow Organizers to delete their own uploads
CREATE POLICY "Organizers can delete own banners"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'event-banners' AND auth.uid() = owner);