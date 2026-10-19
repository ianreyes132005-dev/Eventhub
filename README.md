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

### Students

The admin provisions students through Admin Web Dashboard → Students → **Add Student**.

This calls the `create-student` Supabase Edge Function which atomically:
1. Creates the Supabase Auth user with email `{lrn}@gmail.com` (e.g. `123456261234@gmail.com`)
2. Inserts the row into `public.students`
3. Rolls back the auth user if the DB insert fails

The new student appears in the list immediately after the dialog closes. On the mobile app, the student logs in with the **last 4 digits of their LRN** + their password. This short login uses the school's standard LRN prefix (`12345626`).

### Organizers

The admin provisions organizers through Admin Web Dashboard → Organizers → **Add Organizer**.

This calls the `create-organizer` Supabase Edge Function which atomically:
1. Creates the Supabase Auth user with email `{organizer_id.toLowerCase()}@gmail.com` (e.g. `org0001@gmail.com`)
2. Inserts the row into `public.organizers`
3. Rolls back the auth user if the DB insert fails

**Organizer ID format:** `Org0001` — `Org` prefix followed by 4 digits. The dashboard auto-generates the next available ID. The organizer logs in using their ID in lowercase as the username (e.g. `org0001`) + the password set by the admin.

### Admin

> **Always create admin accounts via the Supabase Dashboard — never via manual SQL INSERT into `auth.users`.**
> Manual inserts often miss required GoTrue columns and cause a "Database error querying schema" on login.

The web login accepts a **username only** (no `@email`). The app appends `@gmail.com` internally before calling Supabase Auth, so the auth user's email must follow the format `{username}@gmail.com`.

1. Go to Supabase Dashboard → **Authentication → Users → Add user → Create new user**
2. **Email:** `yourusername@gmail.com` — e.g. `jjadmin@gmail.com`
3. **Password:** set a strong password
4. Enable **Auto Confirm User**, then click **Create User**
5. Copy the new user's UUID
6. Run in SQL Editor:

```sql
INSERT INTO public.admins (admin_id, user_id, username, full_name)
VALUES (
  'ADMIN001',               -- any unique ID you choose
  '<paste-uuid-here>',
  'jjadmin',                -- what you type at the login screen (no @gmail.com)
  'J-Jireh Admin'
);
```

**To log in:** open the web portal, type `jjadmin` as the username and the password you set. The app constructs `jjadmin@gmail.com` automatically.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — Material 3 |
| Backend | Supabase (PostgreSQL + Auth + Storage + Realtime) |
| Edge Functions | Supabase Edge Functions (Deno / TypeScript) |
| AI Chatbot | Groq API (LLaMA 3) — organizer web dashboard |
| QR Codes | `qr_flutter` (generate) · `mobile_scanner` (scan) |
| Charts | `fl_chart` |
| Deep links | `app_links` |
| Secure store | `flutter_secure_storage` |
| Preferences | `shared_preferences` (organizer theme persistence) |

---

## Features

### Student (mobile)
- Browse and filter upcoming / ongoing / past events — **live via Supabase Realtime**
- Register for events and receive a unique QR code
- View registered events with ticket-style cards — **live updates on status changes**
- Check-in flow: QR scan → selfie capture (triggered by organizer)
- Announcements feed — **live via Supabase Realtime**
- Profile management

### Organizer (mobile + web)
- Create, edit, and manage events with banner image upload
- View and filter registrations per event
- Scan student QR codes to initiate check-in
- Selfie-based check-in confirmation
- Send announcements to all students
- Analytics dashboard (attendance rate, weekly registrations, per-event attendance) — **live via Supabase Realtime**
- Events and announcements pages — **live via Supabase Realtime**
- AI assistant chatbot (Groq / LLaMA 3.1) with organizer-specific quick questions
- Customisable sidebar theme (primary colour + sidebar variant)
- Web-only: collapsible sidebar (inset / floating / minimal variants)

### Admin (web dashboard only)
- Full sidebar navigation: Overview · Students · Organizers · Events · Registrations — **all pages live via Supabase Realtime (600 ms debounce)**
- **Overview** — 4 stat cards (total students / organizers / events / registrations), recent events list, quick-access shortcuts, system status panel, recent registrations
- **Students** — search + Active/Inactive filter, data table with LRN / name / year / status / account-linked, row actions: Edit profile, Activate/Deactivate, Delete. **Add Student** creates auth account + DB row atomically via Edge Function
- **Organizers** — same as Students with Organizer ID / Organization columns, auto-generates next `Org####` ID when adding. **Add Organizer** creates auth account + DB row atomically via Edge Function; organizer logs in with `{id.lowercase()}@gmail.com`
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
| Mobile auth | `AuthScreen` | `lib/features/auth/auth_screen.dart` |
| Web auth | `WebAuthScreen` | `lib/features/auth/web_auth_screen.dart` |
| Student dashboard | `StudentDashboard` | `lib/features/student/dashboard/` |
| Organizer mobile | `OrganizerDashboardScreen` | `lib/features/organizer/mobile/dashboard/` |
| Organizer web | `WebShell` | `lib/features/organizer/web/` |
| Admin web | `AdminWebDashboard` | `lib/features/admin/admin_web_dashboard.dart` |

---

## Project Structure

```
lib/
├── features/
│   ├── auth/
│   │   ├── auth_screen.dart          # Mobile login (student / organizer / admin)
│   │   └── web_auth_screen.dart      # Web login (organizer / admin)
│   ├── student/
│   │   ├── dashboard/
│   │   ├── events/                   # All events + My registered events (realtime)
│   │   ├── profile/
│   │   └── notifications/
│   ├── organizer/
│   │   ├── mobile/
│   │   │   ├── dashboard/
│   │   │   ├── events/
│   │   │   ├── registrations/
│   │   │   ├── announcements/
│   │   │   └── profile/
│   │   └── web/
│   │       ├── web_shell.dart              # Web shell + sidebar
│   │       ├── web_shared.dart             # Shared constants, widgets, theme
│   │       ├── dashboard_page.dart         # Realtime: events, registrations
│   │       ├── events_page.dart            # Realtime: events, registrations
│   │       ├── registrations_page.dart
│   │       ├── announcements_page.dart     # Realtime: announcements
│   │       ├── settings_page.dart
│   │       └── ai_chatbot.dart             # Groq-powered AI assistant
│   └── admin/
│       └── admin_web_dashboard.dart        # Full web admin dashboard (5 pages, all realtime)
├── core/
│   ├── services/
│   │   ├── supabase_service.dart
│   │   └── registration_service.dart
│   ├── app_colors.dart               # kGold, kGoldGradient, kText, etc.
│   └── app_theme.dart                # Material 3 theme
├── shared/
│   └── widgets/                      # Shared widgets
├── app.dart                          # Routes + auth state listener + app links
└── main.dart

supabase/
└── functions/
    ├── ai-chat/index.ts              # Groq / LLaMA 3.1 AI assistant
    ├── create-student/index.ts       # Atomically creates auth user + students row
    └── create-organizer/index.ts     # Atomically creates auth user + organizers row
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

> Supabase credentials are in `lib/core/services/supabase_service.dart`.

---

## Edge Functions

| Function | File | Purpose |
|---|---|---|
| `ai-chat` | `supabase/functions/ai-chat/index.ts` | Groq / LLaMA 3.1 AI assistant for the organizer web dashboard |
| `create-student` | `supabase/functions/create-student/index.ts` | Admin-only: creates Supabase auth user + `students` row atomically |
| `create-organizer` | `supabase/functions/create-organizer/index.ts` | Admin-only: creates Supabase auth user + `organizers` row atomically |

### Deploying

```bash
# Must be run from the project root (c:\project\eventhub)
supabase login
supabase link --project-ref <your-project-ref>

supabase functions deploy ai-chat
supabase functions deploy create-student
supabase functions deploy create-organizer
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically by Supabase at runtime — do not set them manually.

### Edge Function inputs

**`create-student`**

```json
{ "lrn": "123456261234", "full_name": "Juan Dela Cruz", "year_level": 3, "password": "secret123" }
```

**`create-organizer`**

```json
{ "organizer_id": "Org0001", "full_name": "Maria Santos", "organization": "Science Club", "password": "secret123" }
```

Both require the caller's JWT to belong to a row in `public.admins`.

---

## Realtime

Supabase Realtime (`supabase_realtime` publication) is enabled on these tables:

| Table | Who subscribes |
|---|---|
| `events` | Admin dashboard, Organizer web (dashboard, events), Student (all events, my events) |
| `registrations` | Admin dashboard, Organizer web (dashboard, events), Student (all events, my events) |
| `announcements` | Admin dashboard, Organizer web (announcements), Student (dashboard, my events) |
| `students` | Admin dashboard |
| `organizers` | Admin dashboard |

All realtime callbacks use a **600 ms debounce** (`Timer`) to coalesce rapid bulk changes into a single silent refresh. The `_load({bool silent = false})` pattern keeps the spinner hidden during background refreshes.

Enable realtime on the tables in the Supabase Dashboard under **Database → Replication**, or run:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.registrations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;
ALTER PUBLICATION supabase_realtime ADD TABLE public.students;
ALTER PUBLICATION supabase_realtime ADD TABLE public.organizers;
```

---

## Database Schema

All tables are created manually via the Supabase Dashboard or SQL Editor. `lib/supabase_schema.sql` covers `registrations`, `selfies` storage, and the participant-counter RPCs.

---

### `admins`

```sql
DROP TABLE IF EXISTS public.admins CASCADE;

CREATE TABLE public.admins (
  admin_id    VARCHAR     PRIMARY KEY,
  user_id     UUID        UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  username    VARCHAR     NOT NULL UNIQUE,
  full_name   VARCHAR     NOT NULL,
  is_active   BOOLEAN     DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

-- Admin can read their own row
CREATE POLICY "admins_read_own" ON public.admins
  FOR SELECT USING (auth.uid() = user_id);
```

> **Note:** `username` is what the admin types at the web login screen. The auth email stored in Supabase is `{username}@gmail.com` — it is never shown in the UI.

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
  organizer_id VARCHAR     PRIMARY KEY,   -- format: Org0001
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

> **Organizer login:** email is `{organizer_id.toLowerCase()}@gmail.com` — e.g. `org0001@gmail.com`. The organizer types their ID in lowercase at the login screen; the app appends `@gmail.com` internally.

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

> **Note:** Banner paths use a flat root-level filename (`banner_<ms>_<uuid>.ext`) — no subfolder — so the organizer policy works regardless of the organizer's custom ID (`Org0001`). Do **not** use the organizer's custom ID as a folder prefix; it is not the same as `auth.uid()` and will cause a 403.

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
