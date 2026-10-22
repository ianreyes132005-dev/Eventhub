-- ═════════════════════════════════════════════════════════════════════════════
-- Settings that follow the account to any phone.
--
-- Read/unread notification marks, the notification settings (Profile →
-- Notifications) and the language choice used to live only on the phone
-- (SharedPreferences), so signing in on another phone started from scratch.
-- They're now saved here too, one row per account; the phone keeps its own
-- copy as a fast, offline cache (lib/core/services/user_settings_cloud.dart).
--
--   • Only the owner can read or write their row (RLS).
--   • The app keeps at most the 300 newest read ids.
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id                uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  read_notification_ids  text[]      NOT NULL DEFAULT '{}',
  disabled_notifications text[]      NOT NULL DEFAULT '{}',
  language               text        NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'fil')),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_settings_select_own" ON public.user_settings;
CREATE POLICY "user_settings_select_own" ON public.user_settings
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "user_settings_insert_own" ON public.user_settings;
CREATE POLICY "user_settings_insert_own" ON public.user_settings
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "user_settings_update_own" ON public.user_settings;
CREATE POLICY "user_settings_update_own" ON public.user_settings
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

GRANT SELECT, INSERT, UPDATE ON public.user_settings TO authenticated;

NOTIFY pgrst, 'reload schema';
