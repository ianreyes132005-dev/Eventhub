-- ═════════════════════════════════════════════════════════════════════════════
-- Which manual migrations has this database had?           READ-ONLY CHECK
--
-- Migrations here are run by hand in the SQL editor, so one can be missed
-- (202610180009 was: no notifications table, and the admin's "remove
-- announcement" failed). This looks for what each migration creates and
-- lists the missing ones first.
--
-- Paste into the Supabase SQL editor and run. It changes nothing.
--   ✓        the migration's objects are there
--   ✗ run it  something it creates is missing — run that file from
--             supabase/migrations/, then this check again
-- Run them oldest first: a later file may need an earlier one.
-- An old file can also hold an older copy of a function a later file
-- replaced; rerunning it puts the older copy back. Where that's the case the
-- row says which file to run instead.
-- ═════════════════════════════════════════════════════════════════════════════

WITH fn AS (
  SELECT p.proname, p.prosrc
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
),
col AS (
  SELECT table_name, column_name
  FROM information_schema.columns
  WHERE table_schema = 'public'
),
pub AS (
  SELECT tablename
  FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
),
pol AS (
  SELECT policyname FROM pg_policies
),
checks (migration, what, ok) AS (
  VALUES
  ('202610070001_admin_log_delete_policies', 'admin can clear the logs',
    EXISTS (SELECT 1 FROM pol WHERE policyname = 'admin_delete_event_logs')
    AND EXISTS (SELECT 1 FROM pol WHERE policyname = 'admin_delete_login_logs')),
  ('202610070002_announcements_realtime', 'announcements update live',
    EXISTS (SELECT 1 FROM pub WHERE tablename = 'announcements')),
  ('202610140001_organizer_directory', 'organizer names for students',
    to_regclass('public.organizer_directory') IS NOT NULL),
  ('202610150004_hide_unapproved_events_from_students', 'students only see approved events',
    EXISTS (SELECT 1 FROM pol WHERE policyname = 'public_select_approved_events')),
  ('202610170001_students_strand', 'students.strand',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'students' AND column_name = 'strand')),
  ('202610180001_students_name_parts', 'students.first_name / last_name',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'students' AND column_name = 'first_name')),
  ('202610180002_organizers_name_parts', 'organizers.first_name / last_name',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'organizers' AND column_name = 'first_name')),
  ('202610180003_students_section', 'students.section',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'students' AND column_name = 'section')),
  ('202610180004_event_registrant_profiles', 'student details panel view',
    to_regclass('public.event_registrant_profiles') IS NOT NULL),
  ('202610180005_event_timing_rules', 'check-in window and late-approval rules',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'event_checkin_problem')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'block_late_approval')),
  ('202610180006_event_cancellation', 'cancel with a reason',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'events' AND column_name = 'cancel_reason')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'event_cancellation_rules')),
  ('202610180007_event_change_requests', 'change requests',
    to_regclass('public.event_revisions') IS NOT NULL
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'approve_event_revision')),
  ('202610180008_remove_walk_in', 'walk-in rule removed',
    NOT EXISTS (SELECT 1 FROM fn WHERE proname = 'enforce_registration_insert_rules'
                                   AND prosrc LIKE '%allow_walk_in%')),
  ('202610180009_announcement_deletion_notifications', 'admin removes announcements, organizer notified',
    to_regclass('public.notifications') IS NOT NULL
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'admin_delete_announcement')),
  ('202610180010_event_archives', 'archives',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'events' AND column_name = 'archived_at')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'admin_delete_archived_event')
    AND to_regclass('public.event_attendance_summary') IS NOT NULL),
  ('202610180011_capacity_from_students', 'capacity = active students',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'active_student_count')),
  ('202610190001_organizer_preferences_and_active_guard', 'organizer settings, deactivated accounts blocked',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'organizers' AND column_name = 'notification_preferences')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'block_inactive_organizer_changes')),
  ('202610190002_account_status_realtime', 'deactivation reaches signed-in apps',
    EXISTS (SELECT 1 FROM pub WHERE tablename = 'students')
    AND EXISTS (SELECT 1 FROM pub WHERE tablename = 'organizers')),
  ('202610200001_middle_names', 'middle names',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'students' AND column_name = 'middle_name')
    AND EXISTS (SELECT 1 FROM col WHERE table_name = 'organizers' AND column_name = 'middle_name')),
  ('202610210001_auto_reject_unreviewed_events', 'unreviewed events rejected at their start',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'reject_unreviewed_events')),
  ('202610210002_ticket_codes', '4-digit Ticket IDs',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'registrations' AND column_name = 'ticket_code')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'assign_ticket_code')),
  ('202610210003_registration_closes_after_start', 'registration open until 2 h after the start',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'enforce_registration_insert_rules'
                               AND prosrc LIKE '%2 hours%')),
  ('202610210004_user_settings', 'settings follow the account',
    to_regclass('public.user_settings') IS NOT NULL),
  ('202610220001_organizer_realtime', 'change requests and notices update live',
    EXISTS (SELECT 1 FROM pub WHERE tablename = 'events')
    AND EXISTS (SELECT 1 FROM pub WHERE tablename = 'event_revisions')
    AND EXISTS (SELECT 1 FROM pub WHERE tablename = 'notifications')),
  ('202610230001_registration_delete_and_counts', 'delete registrations; declined ones don''t count',
    EXISTS (SELECT 1 FROM pol WHERE policyname = 'organizer_delete_own_event_registrations')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'maintain_participant_count'
                                   AND prosrc ILIKE '%rejected%')),
  ('202610230002_organizers_own_events_only', 'organizers only see their own events'' registrations',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'organizer_owns_event')
    AND EXISTS (SELECT 1 FROM pol WHERE policyname = 'organizer_select_own_event_registrations')
    AND NOT EXISTS (SELECT 1 FROM pol WHERE policyname IN ('organizer_select_all', 'organizer_update_status'))),
  -- Not rerunnable since 202610280001 (it would put back older check-in rules):
  -- when ✗, run 202611030002_reapply_archive_records.sql instead.
  ('202610230003_archive_records', 'archives keep real, complete records; archive notices — if ✗, run 202611030002_reapply_archive_records.sql instead of this file',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'admin_delete_unused_event')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'notify_archive_changes')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'event_archive_rules'
                                   AND prosrc ILIKE '%nothing to archive%')),
  ('202610230004_archive_delete_notice', 'organizer told when an archived event is deleted',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'admin_delete_archived_event'
                               AND prosrc ILIKE '%event_deleted%')),
  ('202610270001_audit_log_integrity', 'audit log entries name their real author',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'stamp_event_log_author')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'stamp_login_log_account')),
  ('202610270002_registration_status_changed_at', 'notifications show when a check-in step happened',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'registrations' AND column_name = 'status_changed_at')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'stamp_registration_status_change')),
  ('202610280001_checkin_windows_final_attendance', 'scanning until 30 min after the end, final attendance, students can cancel',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'registrations' AND column_name = 'attendance_note')
    AND EXISTS (SELECT 1 FROM col WHERE table_name = 'registrations' AND column_name = 'corrected_at')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'event_scan_problem')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'enforce_registration_update_rules'
                                   AND prosrc ILIKE '%attendance is final%')
    AND EXISTS (SELECT 1 FROM pol WHERE policyname = 'student_cancel_own_registration')),
  ('202611030001_event_audience', 'events can be open to some grades and strands only',
    EXISTS (SELECT 1 FROM col WHERE table_name = 'events' AND column_name = 'audience_grades')
    AND EXISTS (SELECT 1 FROM col WHERE table_name = 'events' AND column_name = 'audience_strands')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'active_student_counts')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'enforce_registration_insert_rules'
                                   AND prosrc ILIKE '%event_audience_allows%')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'approve_event_revision'
                                   AND prosrc ILIKE '%audience_grades%')),
  -- The same objects as 202610230003: ✗ together, fixed together by this file.
  ('202611030002_reapply_archive_records', 'archive rules and notices re-applied (fixes a ✗ on 202610230003)',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'admin_delete_unused_event')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'notify_archive_changes')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'event_archive_rules'
                                   AND prosrc ILIKE '%nothing to archive%')),
  ('202611030003_android_push_notifications', 'Android push token registration and notification triggers',
    to_regclass('public.push_tokens') IS NOT NULL
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'register_push_token')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'dispatch_eventhub_push')
    AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_push_new_announcement')
    AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_push_new_event_registration')),
  ('202611040001_student_event_push_notifications', 'newly approved events notify eligible students',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'push_newly_approved_event')
    AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_push_approved_event_students')),
  ('202611040002_admin_log_clear_all', 'admins can clear login and event logs of any age',
    EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
              AND tablename = 'event_logs' AND policyname = 'admin_delete_event_logs'
              AND cmd = 'DELETE' AND qual ILIKE '%admins%')
    AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
              AND tablename = 'login_logs' AND policyname = 'admin_delete_login_logs'
              AND cmd = 'DELETE' AND qual ILIKE '%admins%')
    AND NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
              AND tablename IN ('event_logs', 'login_logs')
              AND cmd IN ('DELETE', 'ALL')
              AND (COALESCE(qual, '') NOT ILIKE '%admins%'
                   OR COALESCE(qual, '') ILIKE '%90 days%'))),
  ('202611040003_admin_registration_trend', 'admin dashboard counts registrations in the database (no 1,000-row limit)',
    EXISTS (SELECT 1 FROM fn WHERE proname = 'admin_dashboard_totals')
    AND EXISTS (SELECT 1 FROM fn WHERE proname = 'admin_registration_trend'
                                   AND prosrc ILIKE '%attendance%'))
)
SELECT CASE WHEN ok THEN '✓' ELSE '✗ run it' END AS status, migration, what
FROM checks
ORDER BY ok, migration;
