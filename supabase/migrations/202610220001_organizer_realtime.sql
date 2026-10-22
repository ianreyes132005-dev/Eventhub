-- ═════════════════════════════════════════════════════════════════════════════
-- Live updates for the organizer's change requests and notices.
--
-- The app and the web portal listen for database changes (Supabase Realtime),
-- but a table only sends them once it's in the supabase_realtime publication:
--
--   • event_revisions — the admin's answer to a change request. A rejection
--     only touches this table, so "Your last changes were rejected" (web
--     Events page, the app's edit form) and the bells waited up to a minute.
--   • notifications   — "your announcement was removed" notices for the
--     bells. The table comes from 202610180009_announcement_deletion_
--     notifications.sql — run that one first.
--   • events          — already switched on by hand in the dashboard; listed
--     here so the project records it. Nothing changes if it's already on.
--
-- A table that doesn't exist yet is skipped with a notice instead of failing
-- the whole script: run its migration, then this one again.
--
-- Who receives what still follows each table's RLS: an organizer only hears
-- about their own change requests and notices.
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['events', 'event_revisions', 'notifications'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE NOTICE 'Skipped %: the table doesn''t exist yet. Run its migration, then this script again.', t;
    ELSIF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END
$$;
