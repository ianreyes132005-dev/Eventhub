-- ═════════════════════════════════════════════════════════════════════════════
-- Live database rules the app depends on.                  READ-ONLY CHECK
--
-- Some rules can only be seen on the live database (they may have been set in
-- the dashboard rather than by a migration). Paste into the Supabase SQL
-- editor and run. It changes nothing. Each row says what it checks, what was
-- found, and whether that's what the app expects.
-- ═════════════════════════════════════════════════════════════════════════════

WITH checks (topic, finding, ok) AS (
  -- Organizers' "Delete registration" needs a DELETE policy; without one the
  -- delete silently removes nothing. Added by 202610230001.
  SELECT 'Organizers can delete registrations',
         COALESCE((SELECT string_agg(policyname, ', ') FROM pg_policies
                    WHERE schemaname = 'public' AND tablename = 'registrations'
                      AND cmd IN ('DELETE', 'ALL')), 'no DELETE policy'),
         EXISTS (SELECT 1 FROM pg_policies
                  WHERE schemaname = 'public' AND tablename = 'registrations'
                    AND cmd IN ('DELETE', 'ALL'))
  UNION ALL
  -- Who can read and change registrations: the 202610150003 rollback let every
  -- organizer read and change every registration; 202610230002 limits them to
  -- their own events.
  SELECT 'Organizers see and change only their own events'' registrations',
         COALESCE((SELECT string_agg(policyname, ', ') FROM pg_policies
                    WHERE schemaname = 'public' AND tablename = 'registrations'
                      AND cmd IN ('SELECT', 'UPDATE')), 'none'),
         NOT EXISTS (SELECT 1 FROM pg_policies
                      WHERE schemaname = 'public' AND tablename = 'registrations'
                        AND policyname IN ('organizer_select_all', 'organizer_update_status'))
  UNION ALL
  SELECT 'Organizers open only their own events'' selfies',
         COALESCE((SELECT CASE WHEN qual ILIKE '%organizer_owns_selfie%'
                               THEN 'own events only' ELSE 'every organizer' END
                     FROM pg_policies
                    WHERE schemaname = 'storage' AND tablename = 'objects'
                      AND policyname = 'organizer_read_selfies'), 'no policy'),
         EXISTS (SELECT 1 FROM pg_policies
                  WHERE schemaname = 'storage' AND tablename = 'objects'
                    AND policyname = 'organizer_read_selfies'
                    AND qual ILIKE '%organizer_owns_selfie%')
  UNION ALL
  -- "N registered" counts every registration but a declined one; the counter
  -- trigger keeps it so (202610230001).
  SELECT 'Registered counts leave out declined registrations',
         (SELECT count(*) FROM public.events e
           WHERE e.current_participants IS DISTINCT FROM
                 (SELECT count(*) FROM public.registrations r
                   WHERE r.event_id = e.event_id AND r.status <> 'rejected'))
         || ' event(s) off',
         NOT EXISTS (SELECT 1 FROM public.events e
                      WHERE e.current_participants IS DISTINCT FROM
                            (SELECT count(*) FROM public.registrations r
                              WHERE r.event_id = e.event_id AND r.status <> 'rejected'))
  UNION ALL
  -- Unreviewed events are rejected at their start by a pg_cron job (when the
  -- extension is on); otherwise only when the admin portal loads.
  SELECT 'Auto-reject runs every minute (pg_cron)',
         CASE WHEN to_regclass('cron.job') IS NULL THEN 'pg_cron not enabled'
              ELSE 'see the next row' END,
         to_regclass('cron.job') IS NOT NULL
  UNION ALL
  SELECT 'Selfies are private',
         COALESCE((SELECT CASE WHEN public THEN 'public' ELSE 'private' END
                     FROM storage.buckets WHERE id = 'selfies'), 'no bucket'),
         EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'selfies' AND NOT public)
  UNION ALL
  SELECT 'Profile photos bucket (public by design — see Privacy Policy)',
         COALESCE((SELECT CASE WHEN public THEN 'public' ELSE 'private' END
                     FROM storage.buckets WHERE id = 'profile-photos'), 'no bucket'),
         EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'profile-photos')
  UNION ALL
  SELECT 'Event banners bucket is public (banners load without sign-in)',
         COALESCE((SELECT CASE WHEN public THEN 'public' ELSE 'private' END
                     FROM storage.buckets WHERE id = 'event-banners'), 'no bucket'),
         EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'event-banners' AND public)
  UNION ALL
  -- Clearing logs keeps the last 90 days (202610270001). Any other DELETE (or
  -- ALL) policy on the log tables, e.g. one added in the dashboard, would let
  -- recent entries be deleted again.
  SELECT 'Log entries from the last 90 days can''t be deleted',
         COALESCE((SELECT string_agg(tablename || ': ' || policyname, ', ') FROM pg_policies
                    WHERE schemaname = 'public' AND tablename IN ('event_logs', 'login_logs')
                      AND cmd IN ('DELETE', 'ALL')), 'no delete policy'),
         NOT EXISTS (SELECT 1 FROM pg_policies
                      WHERE schemaname = 'public' AND tablename IN ('event_logs', 'login_logs')
                        AND cmd IN ('DELETE', 'ALL')
                        AND COALESCE(qual, '') NOT ILIKE '%90 days%')
)
SELECT CASE WHEN ok THEN '✓' ELSE '✗' END AS status, topic, finding
FROM checks
ORDER BY ok, topic;

-- If pg_cron is enabled, this shows the auto-reject job (run it on its own):
-- SELECT jobname, schedule, active FROM cron.job WHERE command ILIKE '%reject_unreviewed_events%';
