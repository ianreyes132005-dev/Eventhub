-- ═════════════════════════════════════════════════════════════════════════════
-- Event cancellation — one flow for organizer web and mobile.
--
--   • Cancelling needs a reason; when it happened is recorded. Registrations
--     (and their attendance / selfie records) are kept, never deleted.
--     Registered students see a "Event cancelled" notification with the reason.
--   • Restoring clears the reason. Neither cancel nor restore is possible
--     once the event has ended.
--   • An organizer can't delete an event that has registrations — cancel it
--     instead. (Admins and account deletion are unaffected.)
--
-- Requires 202610180005_event_timing_rules.sql (event_ends_at). Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at  timestamptz;

CREATE OR REPLACE FUNCTION public.event_cancellation_rules()
RETURNS TRIGGER AS $$
BEGIN
  -- Cancel
  IF NEW.event_status = 'cancelled'
     AND OLD.event_status IS DISTINCT FROM 'cancelled' THEN
    IF now() >= public.event_ends_at(NEW) THEN
      RAISE EXCEPTION 'This event has already ended, so it can''t be cancelled.';
    END IF;
    IF COALESCE(btrim(NEW.cancel_reason), '') = '' THEN
      RAISE EXCEPTION 'Please give a reason for cancelling — registered students will see it.';
    END IF;
    NEW.cancel_reason := btrim(NEW.cancel_reason);
    NEW.cancelled_at  := now();
    RETURN NEW;
  END IF;

  -- Restore
  IF OLD.event_status = 'cancelled'
     AND NEW.event_status IS DISTINCT FROM 'cancelled' THEN
    IF now() >= public.event_ends_at(NEW) THEN
      RAISE EXCEPTION 'This event has already ended, so it can''t be restored.';
    END IF;
    NEW.cancel_reason := NULL;
    NEW.cancelled_at  := NULL;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_event_cancellation_rules ON public.events;
CREATE TRIGGER trg_event_cancellation_rules
  BEFORE UPDATE OF event_status ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.event_cancellation_rules();

-- Organizers keep attendance history: no deleting events with registrations.
CREATE OR REPLACE FUNCTION public.block_event_delete_with_registrations()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
     AND EXISTS (SELECT 1 FROM public.registrations WHERE event_id = OLD.event_id)
  THEN
    RAISE EXCEPTION 'This event has registrations, so it can''t be deleted. Cancel it instead — registrations and attendance records are kept.';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_event_delete_with_registrations ON public.events;
CREATE TRIGGER trg_block_event_delete_with_registrations
  BEFORE DELETE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.block_event_delete_with_registrations();
