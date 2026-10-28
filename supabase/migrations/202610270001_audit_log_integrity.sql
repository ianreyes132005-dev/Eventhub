-- ═════════════════════════════════════════════════════════════════════════════
-- Audit logs can't be wiped or faked.
--
--   1. The admin's Clear (Logs tab) removes only entries older than 90 days:
--      the last 90 days of sign-ins and event actions always stay. The app
--      offers the same: kLogRetention in lib/features/admin/admin_web_logs.dart
--      — keep the two the same.
--   2. Every new entry names who really did it. Whatever the app sends, the
--      database fills in the signed-in account:
--        event_logs  performed_by; for an organizer also their own ID and
--                    name, and only their own events
--        login_logs  the account, its role, its name and its sign-in name
--      The admin's entries, and the ones the database writes during an admin
--      action (archive, restore, delete), name the event's organizer and are
--      kept as written.
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── 1. Clearing keeps the last 90 days ───────────────────────────────────────
DROP POLICY IF EXISTS "admin_delete_event_logs" ON public.event_logs;
CREATE POLICY "admin_delete_event_logs" ON public.event_logs
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
    AND created_at < now() - interval '90 days'
  );

DROP POLICY IF EXISTS "admin_delete_login_logs" ON public.login_logs;
CREATE POLICY "admin_delete_login_logs" ON public.login_logs
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
    AND created_at < now() - interval '90 days'
  );

-- ── 2a. Event log entries name their real author ─────────────────────────────
-- SECURITY DEFINER: it reads organizers and events whatever their policies.
CREATE OR REPLACE FUNCTION public.stamp_event_log_author()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  org public.organizers%ROWTYPE;
BEGIN
  -- Nobody signed in: the service role (Edge Functions, pg_cron, SQL editor).
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  NEW.performed_by := auth.uid();

  -- The admin's entries name the event's organizer, not the admin.
  IF EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RETURN NEW;
  END IF;

  SELECT * INTO org FROM public.organizers WHERE user_id = auth.uid();
  IF NOT FOUND THEN
    RETURN NEW;   -- nobody else may add entries (RLS)
  END IF;

  NEW.organizer_id   := org.organizer_id;
  NEW.organizer_name := org.full_name;

  -- Only their own events. An entry about an event they just deleted points
  -- at a row that's gone, so there's nothing left to compare.
  IF NEW.event_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.events e
    WHERE e.event_id = NEW.event_id
      AND e.organizer_id IS DISTINCT FROM org.organizer_id
  ) THEN
    RAISE EXCEPTION 'You can only log actions on your own events.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_event_log_author ON public.event_logs;
CREATE TRIGGER trg_stamp_event_log_author
  BEFORE INSERT ON public.event_logs
  FOR EACH ROW EXECUTE FUNCTION public.stamp_event_log_author();

-- ── 2b. Sign-in entries name the account that signed in ──────────────────────
CREATE OR REPLACE FUNCTION public.stamp_login_log_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid     uuid := auth.uid();
  -- The sign-in name: a student's LRN, the organizer ID, or the admin's
  -- username — the part of the account email before the @.
  sign_in text := lower(split_part(COALESCE(auth.jwt() ->> 'email', ''), '@', 1));
  who     text;
BEGIN
  IF uid IS NULL THEN
    RETURN NEW;
  END IF;

  NEW.user_id := uid;

  SELECT a.full_name INTO who FROM public.admins a WHERE a.user_id = uid;
  IF FOUND THEN
    NEW.user_role := 'admin';
  ELSE
    SELECT o.full_name INTO who FROM public.organizers o WHERE o.user_id = uid;
    IF FOUND THEN
      NEW.user_role := 'organizer';
    ELSE
      SELECT s.full_name INTO who FROM public.students s WHERE s.user_id = uid;
      NEW.user_role := 'student';
    END IF;
  END IF;
  NEW.full_name := who;

  IF sign_in <> '' THEN
    NEW.identifier := sign_in;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_login_log_account ON public.login_logs;
CREATE TRIGGER trg_stamp_login_log_account
  BEFORE INSERT ON public.login_logs
  FOR EACH ROW EXECUTE FUNCTION public.stamp_login_log_account();

NOTIFY pgrst, 'reload schema';
