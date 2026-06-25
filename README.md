# J-Jireh EventHub

A role-based school event management app built with **Flutter** and **Supabase**.

---

## Roles & RBAC

Three roles exist. Priority order is checked on every login — admin wins first.

| Priority | Role | How detected |
|---|---|---|
| 1 | **Admin** | Row found in `public.admins` where `user_id = auth.uid()` |
| 2 | **Organizer** | Row found in `public.organizers` where `user_id = auth.uid()` |
| 3 | **Student** | Default — no admin or organizer row found |

This check runs in four places: mobile `_handleLogin()`, mobile `setupAuthStateListener()`, mobile `setupAppLinks()`, web `_checkSession()`, and web `_login()` in `lib/auth/`.

---

## Account Provisioning

> **All accounts are created exclusively by the administrator. There is no self-registration flow.**

### Students & Organizers

The admin provisions these through the **Admin Web Dashboard** (Students / Organizers pages) or directly via Supabase SQL. The dashboard creates the profile record in `public.students` or `public.organizers`. Login credentials (the Supabase Auth account) are created separately:

- Go to Supabase Dashboard → **Authentication → Users → Add user → Create new user**
- Enter the student/organizer email and a temporary password
- Copy the UUID and link it to the profile row via `UPDATE students SET user_id = '<uuid>' WHERE lrn = '...'`

### Admin

> **Always create admin accounts via the Supabase Dashboard — never via manual SQL INSERT into `auth.users`.**
> Manual inserts often miss required GoTrue columns (`is_anonymous`, `is_sso_user`, token fields) and cause a "Database error querying schema" on login.

1. Go to Supabase Dashboard → **Authentication → Users → Add user → Create new user**
2. Enter the admin email and password
3. Copy the new user's UUID
4. Run in SQL Editor:

```sql
INSERT INTO public.admins (user_id, full_name, email, is_active)
VALUES ('<paste-uuid-here>', 'System Administrator', 'admin@example.com', true)
ON CONFLICT (user_id) DO NOTHING;
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — Material 3 |
| Backend | Supabase (PostgreSQL + Auth + Storage + Realtime) |
| AI Chatbot | Groq API (LLaMA 3) — organizer web dashboard |
| QR Codes | `qr_flutter` (generate) · `mobile_scanner` (scan) |
| Charts | `fl_chart` |
| Deep links | `app_links` |
| Secure store | `flutter_secure_storage` |
| Preferences | `shared_preferences` (organizer theme persistence) |

---

## Features

### Student (mobile)
- Browse and filter upcoming / ongoing / past events
- Register for events and receive a unique QR code
- View registered events with ticket-style cards
- Check-in flow: QR scan → selfie capture (triggered by organizer)
- Announcements feed
- Profile management

### Organizer (mobile + web)
- Create, edit, and manage events with banner image upload
- View and filter registrations per event
- Scan student QR codes to initiate check-in
- Selfie-based check-in confirmation
- Send announcements to all students
- Analytics dashboard (attendance rate, weekly registrations, per-event attendance)
- AI assistant chatbot (Groq / LLaMA 3.1) with organizer-specific quick questions
- Customisable sidebar theme (primary colour + sidebar variant)
- Web-only: collapsible sidebar (inset / floating / minimal variants)

### Admin (web dashboard only)
- Full sidebar navigation: Overview · Students · Organizers · Events · Registrations
- **Overview** — 4 stat cards (total students / organizers / events / registrations), recent events list, quick-access shortcuts, system status panel, recent registrations
- **Students** — search + Active/Inactive filter, data table with LRN / name / year / status / account-linked, row actions: Edit profile, Activate/Deactivate, Delete
- **Organizers** — same as Students with Organizer ID / Organization columns, auto-generates next `JJ####` ID when adding
- **Events** — system-wide read-only view with status filter chips and participant capacity progress bar
- **Registrations** — system-wide read-only view with all status filters and checked-in timestamps
- Animated sidebar with cascade stagger entrance, collapsible to icon-only mode
- Sign-out confirmation dialog

---

## Entry Points

| Platform | Entry widget | File |
|---|---|---|
| Mobile | `JirehEventHubApp` | `lib/app.dart` |
| Web | `JirehEventHubWebApp` | `lib/app.dart` |
| Mobile auth | `AuthScreen` | `lib/auth/auth_screen.dart` |
| Web auth | `WebAuthScreen` | `lib/auth/web_auth_screen.dart` |
| Student dashboard | `StudentDashboard` | `lib/student/dashboard/` |
| Organizer mobile | `OrganizerDashboardScreen` | `lib/organizer/dashboard/` |
| Organizer web | `OrganizerWebDashboard` | `lib/organizer/web/` |
| Admin mobile | `AdminDashboard` | `lib/admin/admin_dashboard.dart` |
| Admin web | `AdminWebDashboard` | `lib/admin/admin_web_dashboard.dart` |

---

## Project Structure

```
lib/
├── auth/
│   ├── auth_screen.dart          # Mobile login (student / organizer / admin)
│   └── web_auth_screen.dart      # Web login (organizer / admin)
├── student/
│   ├── dashboard/
│   ├── events/
│   ├── profile/
│   ├── notifications/
│   └── check_in/
├── organizer/
│   ├── dashboard/
│   ├── events/
│   ├── registrations/
│   ├── announcements/
│   ├── analytics/
│   ├── evaluations/
│   ├── profile/
│   └── web/
│       ├── organizer_web_dashboard.dart  # Web shell + sidebar
│       ├── web_shared.dart               # Shared constants, widgets, theme
│       ├── dashboard_page.dart
│       ├── events_page.dart
│       ├── registrations_page.dart
│       ├── announcements_page.dart
│       ├── settings_page.dart
│       └── ai_chatbot.dart               # Groq-powered AI assistant
├── admin/
│   ├── admin_dashboard.dart              # Mobile admin placeholder
│   └── admin_web_dashboard.dart          # Full web admin dashboard (5 pages)
├── services/
│   ├── supabase_service.dart
│   └── registration_service.dart
├── widgets/                       # Shared widgets
├── app_colors.dart                # kGold, kGoldGradient, kText, etc.
├── app_theme.dart                 # Material 3 theme
├── app.dart                       # Routes + auth state listener + app links
└── main.dart
```

---

## Running the App

```bash
flutter pub get

# Mobile (Android / iOS)
flutter run

# Web
flutter run -d chrome
```

> Supabase credentials are in `lib/services/supabase_service.dart`.

---

## Database Schema

All tables are created manually via the Supabase Dashboard or SQL Editor. `lib/supabase_schema.sql` covers `registrations`, `selfies` storage, and the participant-counter RPCs.

---

### `admins`

```sql
CREATE TABLE public.admins (
  admin_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name  TEXT        NOT NULL,
  email      TEXT        NOT NULL,
  is_active  BOOLEAN     NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

-- Admin can read their own row
CREATE POLICY "admin_select_own" ON public.admins
  FOR SELECT USING (auth.uid() = user_id);
```

---

### `students`

```sql
CREATE TABLE public.students (
  lrn               VARCHAR     PRIMARY KEY,
  user_id           UUID        UNIQUE REFERENCES auth.users(id),
  full_name         VARCHAR     NOT NULL,
  profile_image_url TEXT,
  year_level        INT,
  is_active         BOOLEAN     DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

CREATE POLICY "student_select_own" ON public.students
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "student_update_own" ON public.students
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "organizer_select_students" ON public.students
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

-- Admin full access
CREATE POLICY "admin_students_all" ON public.students
  USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));
```

---

### `organizers`

```sql
CREATE TABLE public.organizers (
  organizer_id VARCHAR     PRIMARY KEY,   -- format: JJ0001
  user_id      UUID        UNIQUE REFERENCES auth.users(id),
  full_name    VARCHAR     NOT NULL,
  organization VARCHAR,
  is_active    BOOLEAN     DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.organizers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organizer_select_own" ON public.organizers
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "organizer_update_own" ON public.organizers
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "authenticated_select_organizers" ON public.organizers
  FOR SELECT USING (auth.role() = 'authenticated');

-- Admin full access
CREATE POLICY "admin_organizers_all" ON public.organizers
  USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));
```

---

### `events`

```sql
CREATE TABLE public.events (
  event_id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_id          VARCHAR     NOT NULL REFERENCES public.organizers(organizer_id) ON DELETE CASCADE,
  title                 VARCHAR     NOT NULL,
  description           TEXT,
  event_type            VARCHAR,
  location              VARCHAR,
  event_date            DATE,
  start_time            TIME,
  end_time              TIME,
  registration_deadline TIMESTAMPTZ,
  max_participants      INT,
  current_participants  INT         NOT NULL DEFAULT 0,
  event_status          VARCHAR     NOT NULL DEFAULT 'upcoming'
    CHECK (event_status IN ('upcoming', 'ongoing', 'completed', 'cancelled')),
  event_image_url       VARCHAR,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_organizer ON public.events (organizer_id);
CREATE INDEX IF NOT EXISTS idx_events_date      ON public.events (event_date);
CREATE INDEX IF NOT EXISTS idx_events_status    ON public.events (event_status);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_select_events" ON public.events
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "organizer_insert_events" ON public.events
  FOR INSERT WITH CHECK (
    organizer_id = (SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid())
  );

CREATE POLICY "organizer_update_events" ON public.events
  FOR UPDATE USING (
    organizer_id = (SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid())
  );

CREATE POLICY "organizer_delete_events" ON public.events
  FOR DELETE USING (
    organizer_id = (SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid())
  );

-- Admin read access
CREATE POLICY "admin_events_select" ON public.events
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));

ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
```

---

### `registrations`

Created by running `lib/supabase_schema.sql`. Key columns:

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | auto |
| `event_id` | UUID FK | → events |
| `event_title` | TEXT | denormalised copy |
| `student_user_id` | UUID FK | → auth.users |
| `student_name` | TEXT | denormalised copy |
| `student_school_id` | TEXT | copy of students.lrn |
| `qr_code` | TEXT UNIQUE | generated on register |
| `status` | TEXT | `pending` → `qr_scanned` → `photo_required` → `photo_submitted` → `checked_in` / `rejected` |
| `selfie_url` | TEXT | storage path |
| `registered_at` | TIMESTAMPTZ | |
| `checked_in_at` | TIMESTAMPTZ | nullable |

After running `lib/supabase_schema.sql`, add admin read access:

```sql
CREATE POLICY "admin_registrations_select" ON public.registrations
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));
```

---

### `announcements`

```sql
CREATE TABLE public.announcements (
  id         BIGINT      PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  title      TEXT        NOT NULL,
  message    TEXT        NOT NULL,
  created_by UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ann_created ON public.announcements (created_at DESC);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_select_announcements" ON public.announcements
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "organizer_insert_announcement" ON public.announcements
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

CREATE POLICY "organizer_delete_own_announcement" ON public.announcements
  FOR DELETE USING (
    created_by = auth.uid()
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
```

---

### `chat_sessions` and `chat_messages`

Used by the AI assistant (Groq / LLaMA 3.1).

```sql
CREATE TABLE public.chat_sessions (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_role  VARCHAR     NOT NULL CHECK (user_role IN ('student', 'organizer')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_session_user ON public.chat_sessions (user_id);

ALTER TABLE public.chat_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_manage_own_session" ON public.chat_sessions
  FOR ALL USING (auth.uid() = user_id);

-- ──────────────────────────────────────────────────────

CREATE TABLE public.chat_messages (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID        NOT NULL REFERENCES public.chat_sessions(id) ON DELETE CASCADE,
  role       TEXT        NOT NULL CHECK (role IN ('user', 'assistant')),
  content    TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_msg_session ON public.chat_messages (session_id, created_at);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_manage_own_messages" ON public.chat_messages
  FOR ALL USING (
    session_id IN (SELECT id FROM public.chat_sessions WHERE user_id = auth.uid())
  );
```

---

## Storage Buckets

| Bucket | Access | Path pattern | Purpose |
|---|---|---|---|
| `event-banners` | **Public** | `banner_{timestamp}_{uuid}.ext` | Event banner images |
| `selfies` | **Private** | `{user_id}/{registration_id}.jpg` | Student check-in selfies |

### `event-banners` RLS

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('event-banners', 'event-banners', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "public_read_event_banners" ON storage.objects
  FOR SELECT USING (bucket_id = 'event-banners');

CREATE POLICY "organizer_upload_event_banner" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

CREATE POLICY "organizer_update_event_banner" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );

CREATE POLICY "organizer_delete_event_banner" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'event-banners'
    AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
  );
```

> **Note:** Banner paths use a flat root-level filename (`banner_<ms>_<uuid>.ext`) — no subfolder — so the organizer policy works regardless of the organizer's custom ID format (`JJ0001`). Do **not** use the organizer's custom ID as a folder prefix; it is not the same as `auth.uid()` and will cause a 403.

See `lib/supabase_schema.sql` for `selfies` bucket policies.

---

## What's in `lib/supabase_schema.sql`

Run this file in the Supabase SQL Editor for any table or function not yet created:

| Section | What it creates |
|---|---|
| 1 | `registrations` table + indexes |
| 2 | RLS policies for `registrations` |
| 3 | Realtime on `registrations` |
| 4 | `selfies` storage bucket + RLS policies |
| 5 | `increment_participant_count` and `decrement_participant_count` RPCs |
