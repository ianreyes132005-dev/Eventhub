# 🚀 Complete Supabase Setup Guide for EventHub

## Step 1: Enable Email Confirmation

1. Go to your Supabase dashboard: https://aefbpjwjoqypstrnaxar.supabase.co
2. Click **"Authentication"** in the left sidebar
3. Click **"Settings"** tab
4. Scroll to **"Email Confirmation"** section
5. **Enable** "Enable email confirmations"
6. Set **"Site URL"** to: `eventhub://auth-callback`
7. Add **"Redirect URLs"**:
   - `eventhub://auth-callback`
   - `https://yourdomain.com/auth-callback` (optional)

## Step 2: Create the Students Table

Go to **SQL Editor** in your Supabase dashboard and run this SQL:

```sql
-- Create students table
CREATE TABLE public.students (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    student_id VARCHAR(20) UNIQUE,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    profile_image_url TEXT,
    course VARCHAR(150),
    year_level INTEGER CHECK (year_level >= 1 AND year_level <= 6),
    date_of_birth DATE,
    address TEXT,
    emergency_contact_name VARCHAR(150),
    emergency_contact_phone VARCHAR(20),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Create indexes
CREATE INDEX idx_students_user_id ON public.students(user_id);
CREATE INDEX idx_students_student_id ON public.students(student_id);
CREATE INDEX idx_students_email ON public.students(email);

-- Enable Row Level Security
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Students can view own profile" ON public.students
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Students can update own profile" ON public.students
    FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can create own student profile" ON public.students
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = TIMEZONE('utc'::text, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER handle_students_updated_at
    BEFORE UPDATE ON public.students
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
```

## Step 3: Test the Sign-Up Process

1. **Run your Flutter app**
2. **Go to Sign Up tab**
3. **Fill in the form:**
   - Name: John Doe
   - Email: your-email@example.com
   - Password: yourpassword123
   - Confirm Password: yourpassword123
4. **Click "Create Account"**
5. **Check your email** for confirmation link
6. **Click the confirmation link**
7. **App should automatically navigate** to student dashboard

## Step 4: Verify Database Entry

After confirming email, check your Supabase dashboard:
1. Go to **Table Editor**
2. Select **students** table
3. You should see the new user record

## 🔧 Troubleshooting

### Issue: "Create Account" button doesn't work
**Solution:** Check console logs for errors. Make sure:
- Supabase URL and key are correct
- Email confirmation is enabled
- Students table exists

### Issue: Sign-up fails with error messages
**Solution:** The app now shows detailed error dialogs. Common issues:
- **"This email is already registered"**: Use a different email or try signing in
- **"Please enter a valid email address"**: Check email format
- **"Password must be at least 6 characters"**: Use a longer password
- **"Network error"**: Check internet connection
- **"Too many attempts"**: Wait a few minutes before trying again

If you see an unexpected error, check the console logs (run `flutter logs` in terminal) for detailed error information.

### Issue: No confirmation email received
**Solution:**
- Check spam/junk folder
- Verify email address is correct
- Check Supabase email settings

### Issue: App doesn't navigate after email confirmation
**Solution:**
- Check that deep linking is set up correctly
- Verify the redirect URL in Supabase matches your app scheme

### Issue: Profile not created
**Solution:**
- Check RLS policies allow profile creation
- Verify the auth state listener is working
- Check Supabase logs for errors

## ✅ Expected Behavior

1. **Click "Create Account"** → Loading spinner appears
2. **Success dialog** shows with email confirmation instructions
3. **Email arrives** with confirmation link
4. **Click link** → App opens and automatically signs in user
5. **Profile created** in students table
6. **Navigation** to student dashboard

## 📧 Email Template Customization (Optional)

To customize the confirmation email:
1. Go to **Authentication > Email Templates**
2. Edit **"Confirm signup"** template
3. Modify subject and content as needed

## 🔑 Environment Variables

Make sure your `.env` file (if used) has:
```
SUPABASE_URL=https://aefbpjwjoqypstrnaxar.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

The sign-up functionality should now work perfectly! 🎉