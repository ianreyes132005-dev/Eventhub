-- ═════════════════════════════════════════════════════════════════════════════
-- Events nobody reviewed before they started are REJECTED automatically.
--
-- The approval statuses are Pending review, Approved and Rejected — there is
-- no "Expired". An event can't be approved once it has started
-- (trg_block_late_approval, 202610180005), so a pending event that reaches its
-- start time is rejected with the reason below. The app shows the same text
-- until this runs: kNotReviewedInTimeReason in lib/core/app_colors.dart —
-- keep the two the same.
--
--   • reviewed_at = the event's start time, the moment the rejection took
--     effect (the organizer's notice uses it, so it's the same notice before
--     and after this runs). reviewed_by stays empty: no admin decided.
--   • Runs every minute when pg_cron is available, whenever the admin portal
--     loads its review count, and once right now for existing events.
--
-- Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- 1. The rejection.
CREATE OR REPLACE FUNCTION public.reject_unreviewed_events()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n integer;
BEGIN
  -- Lets guard_events_approval accept this one system change (step 2).
  PERFORM set_config('eventhub.auto_reject', 'on', true);

  UPDATE public.events e
     SET approval_status  = 'rejected',
         rejection_reason = 'Not reviewed by the admin before the event started.',
         reviewed_by      = NULL,
         reviewed_at      = public.event_starts_at(e)
   WHERE e.approval_status = 'pending'
     AND e.archived_at IS NULL            -- archived records stay frozen
     AND public.event_starts_at(e) <= now();
  GET DIAGNOSTICS n = ROW_COUNT;

  PERFORM set_config('eventhub.auto_reject', 'off', true);
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.reject_unreviewed_events() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_unreviewed_events() FROM anon;
GRANT EXECUTE ON FUNCTION public.reject_unreviewed_events() TO authenticated;

-- 2. The approval guard (latest body: 202610150003) with one addition at the
--    top: the change made by reject_unreviewed_events is allowed. The flag is
--    only ever set inside that function, for its own transaction, and can't
--    be set through the API.
CREATE OR REPLACE FUNCTION public.guard_events_approval()
RETURNS TRIGGER AS $$
DECLARE
  is_admin BOOLEAN;
  is_owner BOOLEAN;
BEGIN
  IF current_setting('eventhub.auto_reject', true) = 'on' THEN
    RETURN NEW;
  END IF;

  is_admin := EXISTS (
    SELECT 1 FROM public.admins WHERE user_id = auth.uid()
  );
  IF is_admin THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.approval_status := 'pending';
    NEW.rejection_reason := NULL;
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    RETURN NEW;
  END IF;

  is_owner := NEW.organizer_id = (
    SELECT organizer_id
    FROM public.organizers
    WHERE user_id = auth.uid()
  );

  IF is_owner
     AND OLD.approval_status = 'rejected'
     AND NEW.approval_status = 'pending'
  THEN
    NEW.rejection_reason := NULL;
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
    RETURN NEW;
  END IF;

  NEW.approval_status := OLD.approval_status;
  NEW.rejection_reason := OLD.rejection_reason;
  NEW.reviewed_by := OLD.reviewed_by;
  NEW.reviewed_at := OLD.reviewed_at;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Events that are already past their start while pending.
SELECT public.reject_unreviewed_events();

-- 4. Every minute, when pg_cron is available. Without it, the admin portal
--    runs the function each time it loads its review count, and the app
--    already shows these events as Rejected in the meantime.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.schedule(
    'reject-unreviewed-events',
    '* * * * *',
    'SELECT public.reject_unreviewed_events()'
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron could not be set up (%). Unreviewed events are still rejected whenever the admin portal loads, and the app shows them as Rejected meanwhile.', SQLERRM;
END $$;

NOTIFY pgrst, 'reload schema';
