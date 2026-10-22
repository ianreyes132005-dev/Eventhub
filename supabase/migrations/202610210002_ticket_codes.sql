-- ═════════════════════════════════════════════════════════════════════════════
-- Ticket IDs: a short code on every ticket that the organizer can type.
--
-- Each registration gets a 4-digit Ticket ID (e.g. 4821), shown big under the
-- student's QR code. When the camera can't read the QR (cracked screen, glare,
-- low brightness), the organizer taps "Type Ticket ID" in the scanner and
-- enters those 4 digits instead.
--
--   • Unique within its event, not across all events, so 4 digits are
--     enough: 9,000 codes per event. Only an event that somehow ran out of
--     free 4-digit codes would hand out 5 digits.
--   • Random, not 1, 2, 3…: a mistyped digit rarely lands on another
--     student's ticket, and nobody can guess the next student's code.
--   • The database picks it (trg_assign_ticket_code). The app never sends
--     one, and it can't be changed afterwards.
--   • Registrations made before this runs get one now (step 3).
--
-- Run once in the Supabase SQL editor. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- 1. The column.
ALTER TABLE public.registrations
  ADD COLUMN IF NOT EXISTS ticket_code text;

-- 2. Pick a code when a registration is created; keep it after that.
--    SECURITY DEFINER: it has to see every registration of the event, not
--    only the student's own (RLS), to avoid handing out a code twice.
CREATE OR REPLACE FUNCTION public.assign_ticket_code()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  candidate text;
  tries     integer := 0;
BEGIN
  -- Already has one (and is still in the same event): it never changes.
  IF TG_OP = 'UPDATE'
     AND OLD.ticket_code IS NOT NULL
     AND NEW.event_id IS NOT DISTINCT FROM OLD.event_id THEN
    NEW.ticket_code := OLD.ticket_code;
    RETURN NEW;
  END IF;

  -- One registration per event picks a code at a time, so two students
  -- registering at the same moment can't draw the same number.
  PERFORM pg_advisory_xact_lock(hashtext('ticket_code:' || NEW.event_id::text));

  LOOP
    tries := tries + 1;
    candidate := CASE
      WHEN tries <= 50  THEN (1000  + floor(random() * 9000))::integer::text   -- 1000–9999
      WHEN tries <= 250 THEN (10000 + floor(random() * 90000))::integer::text  -- 10000–99999
    END;
    IF candidate IS NULL THEN
      RAISE EXCEPTION 'Could not create a Ticket ID for this registration. Please try again.';
    END IF;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.registrations r
       WHERE r.event_id = NEW.event_id
         AND r.ticket_code = candidate
    );
  END LOOP;

  NEW.ticket_code := candidate;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_ticket_code ON public.registrations;
CREATE TRIGGER trg_assign_ticket_code
  BEFORE INSERT OR UPDATE OF ticket_code, event_id ON public.registrations
  FOR EACH ROW EXECUTE FUNCTION public.assign_ticket_code();

-- 3. Codes for the registrations made before today, one row at a time.
--    trg_enforce_registration_update_rules lets only a signed-in organizer
--    edit a registration, and the SQL editor isn't one, so that guard is
--    paused for these updates only. It's all one statement: if anything
--    fails, nothing changes and the guard stays on.
DO $$
DECLARE
  r record;
BEGIN
  ALTER TABLE public.registrations DISABLE TRIGGER trg_enforce_registration_update_rules;

  FOR r IN
    SELECT id FROM public.registrations
     WHERE ticket_code IS NULL
     ORDER BY registered_at
  LOOP
    -- Writing ticket_code fires trg_assign_ticket_code, which fills it in.
    UPDATE public.registrations SET ticket_code = NULL WHERE id = r.id;
  END LOOP;

  ALTER TABLE public.registrations ENABLE TRIGGER trg_enforce_registration_update_rules;
END;
$$;

-- 4. Every registration has one, and no two in the same event share it.
--    ticket_code first, so the scanner's lookup by code uses this index too.
ALTER TABLE public.registrations ALTER COLUMN ticket_code SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS registrations_ticket_code_event_key
  ON public.registrations (ticket_code, event_id);

NOTIFY pgrst, 'reload schema';
