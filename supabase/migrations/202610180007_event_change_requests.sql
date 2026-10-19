-- ═════════════════════════════════════════════════════════════════════════════
-- Edits to a live event need admin approval — as CHANGE REQUESTS.
--
-- Why not just set an edited event back to approval_status = 'pending'?
-- Students can only see approved events (RLS public_select_approved_events),
-- so that would make the event vanish for every registered student — tickets
-- break, registration stops — until an admin acts. Instead:
--
--   • Editing an APPROVED event stores the proposed values in
--     event_revisions (one pending request per event). The live event keeps
--     its current details meanwhile.
--   • Admin approves → the changes are applied. If date / time / venue
--     changed, events.schedule_changed_at is stamped and registered students
--     get an "Event updated" notification. Admin rejects → reason required.
--   • Events not yet live (pending / rejected / expired) are still edited
--     directly — students can't see them.
--   • Schedule rules everywhere: the start can't be in the past and the end
--     must be after the start.
--   • An organizer can no longer change a live event's details directly
--     (only cancel / restore it — see 202610180006).
--
-- Requires 202610180005 (event_starts_at / event_ends_at) and 202610180006.
-- Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- "Event updated" notice for registered students.
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS schedule_changed_at  timestamptz,
  ADD COLUMN IF NOT EXISTS schedule_change_note text;   -- the previous schedule, e.g. "Oct 20, 9:00 AM · Room 101"

CREATE TABLE IF NOT EXISTS public.event_revisions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id         uuid NOT NULL REFERENCES public.events(event_id) ON DELETE CASCADE,
  organizer_id     text NOT NULL,
  changes          jsonb NOT NULL,        -- proposed values, editable columns only
  status           text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
  rejection_reason text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  reviewed_by      uuid,
  reviewed_at      timestamptz
);

-- At most one open request per event; editing again updates it.
CREATE UNIQUE INDEX IF NOT EXISTS event_revisions_one_pending
  ON public.event_revisions (event_id) WHERE status = 'pending';

ALTER TABLE public.event_revisions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "organizer_select_own_revisions" ON public.event_revisions;
CREATE POLICY "organizer_select_own_revisions" ON public.event_revisions
  FOR SELECT USING (
    organizer_id = (SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "organizer_insert_own_revisions" ON public.event_revisions;
CREATE POLICY "organizer_insert_own_revisions" ON public.event_revisions
  FOR INSERT WITH CHECK (
    status = 'pending'
    AND organizer_id = (SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid())
    AND EXISTS (SELECT 1 FROM public.events e
                WHERE e.event_id = event_revisions.event_id
                  AND e.organizer_id = event_revisions.organizer_id)
  );

-- Amend or withdraw your own OPEN request.
DROP POLICY IF EXISTS "organizer_update_own_pending_revisions" ON public.event_revisions;
CREATE POLICY "organizer_update_own_pending_revisions" ON public.event_revisions
  FOR UPDATE
  USING (
    status = 'pending'
    AND organizer_id = (SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid())
  )
  WITH CHECK (
    status IN ('pending', 'withdrawn')
    AND organizer_id = (SELECT organizer_id FROM public.organizers WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "admin_select_revisions" ON public.event_revisions;
CREATE POLICY "admin_select_revisions" ON public.event_revisions
  FOR SELECT USING (EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()));

-- ── Schedule rules ────────────────────────────────────────────────────────────

-- Raises if the schedule starts in the past or doesn't end after it starts.
CREATE OR REPLACE FUNCTION public.assert_valid_schedule(
  p_date date, p_end_date date, p_start time, p_end time)
RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE
  starts timestamptz := (p_date + COALESCE(p_start, time '08:00')) AT TIME ZONE 'Asia/Manila';
  ends   timestamptz := (COALESCE(p_end_date, p_date) + COALESCE(p_end, time '23:59:59'))
                        AT TIME ZONE 'Asia/Manila';
BEGIN
  IF p_date IS NULL THEN
    RAISE EXCEPTION 'The event needs a date.';
  END IF;
  IF starts <= now() THEN
    RAISE EXCEPTION 'The event can''t start in the past — pick a later date or time.';
  END IF;
  IF ends <= starts THEN
    RAISE EXCEPTION 'The event must end after it starts.';
  END IF;
END;
$$;

-- Direct inserts / edits (new events, or ones not live yet): validate the
-- schedule whenever it's set or changed. Ongoing / past events whose
-- schedule isn't touched (e.g. a cancellation) are unaffected.
CREATE OR REPLACE FUNCTION public.validate_event_schedule()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.event_date IS DISTINCT FROM OLD.event_date
     OR NEW.end_date   IS DISTINCT FROM OLD.end_date
     OR NEW.start_time IS DISTINCT FROM OLD.start_time
     OR NEW.end_time   IS DISTINCT FROM OLD.end_time
  THEN
    PERFORM public.assert_valid_schedule(NEW.event_date, NEW.end_date, NEW.start_time, NEW.end_time);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_event_schedule ON public.events;
CREATE TRIGGER trg_validate_event_schedule
  BEFORE INSERT OR UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.validate_event_schedule();

-- An organizer can't change a LIVE event's details directly — it must go
-- through a change request. (Cancel / restore and the participant counter
-- are not "details" and stay allowed.)
CREATE OR REPLACE FUNCTION public.block_direct_live_event_edits()
RETURNS TRIGGER AS $$
BEGIN
  IF COALESCE(OLD.approval_status, 'approved') = 'approved'   -- NULL = legacy live event
     AND EXISTS (SELECT 1 FROM public.organizers WHERE user_id = auth.uid())
     AND (NEW.title            IS DISTINCT FROM OLD.title
       OR NEW.description      IS DISTINCT FROM OLD.description
       OR NEW.event_type       IS DISTINCT FROM OLD.event_type
       OR NEW.location         IS DISTINCT FROM OLD.location
       OR NEW.event_date       IS DISTINCT FROM OLD.event_date
       OR NEW.end_date         IS DISTINCT FROM OLD.end_date
       OR NEW.start_time       IS DISTINCT FROM OLD.start_time
       OR NEW.end_time         IS DISTINCT FROM OLD.end_time
       OR NEW.max_participants IS DISTINCT FROM OLD.max_participants
       OR NEW.allow_walk_in    IS DISTINCT FROM OLD.allow_walk_in
       OR NEW.event_image_url  IS DISTINCT FROM OLD.event_image_url
       OR NEW.registration_deadline IS DISTINCT FROM OLD.registration_deadline)
  THEN
    RAISE EXCEPTION 'This event is live, so changes need admin approval. Submit them as a change request.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_direct_live_event_edits ON public.events;
CREATE TRIGGER trg_block_direct_live_event_edits
  BEFORE UPDATE ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.block_direct_live_event_edits();

-- Change requests: only for live events that haven't started; only editable
-- columns; the resulting schedule must be valid.
CREATE OR REPLACE FUNCTION public.validate_event_revision()
RETURNS TRIGGER AS $$
DECLARE
  ev   public.events%ROWTYPE;
  c    jsonb := NEW.changes;
  bad  text;
BEGIN
  IF NEW.status <> 'pending' THEN
    RETURN NEW;   -- withdrawing / reviewing — nothing to validate
  END IF;

  SELECT * INTO ev FROM public.events WHERE event_id = NEW.event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event not found.';
  END IF;
  IF COALESCE(ev.approval_status, 'approved') <> 'approved' THEN
    RAISE EXCEPTION 'This event isn''t live yet — edit it directly instead.';
  END IF;
  IF ev.event_status = 'cancelled' THEN
    RAISE EXCEPTION 'This event is cancelled. Restore it before changing its details.';
  END IF;
  IF now() >= public.event_starts_at(ev) THEN
    RAISE EXCEPTION 'This event has already started, so its details can''t be changed.';
  END IF;

  SELECT k INTO bad FROM jsonb_object_keys(c) AS k
  WHERE k NOT IN ('title', 'description', 'event_type', 'location', 'event_date',
                  'end_date', 'start_time', 'end_time', 'max_participants',
                  'allow_walk_in', 'event_image_url')
  LIMIT 1;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'A change request can''t change "%".', bad;
  END IF;
  IF c = '{}'::jsonb THEN
    RAISE EXCEPTION 'There are no changes to submit.';
  END IF;

  IF c ?| array['event_date', 'end_date', 'start_time', 'end_time'] THEN
    PERFORM public.assert_valid_schedule(
      CASE WHEN c ? 'event_date' THEN (c->>'event_date')::date ELSE ev.event_date END,
      CASE WHEN c ? 'end_date'   THEN (c->>'end_date')::date   ELSE ev.end_date   END,
      CASE WHEN c ? 'start_time' THEN (c->>'start_time')::time ELSE ev.start_time END,
      CASE WHEN c ? 'end_time'   THEN (c->>'end_time')::time   ELSE ev.end_time   END);
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_event_revision ON public.event_revisions;
CREATE TRIGGER trg_validate_event_revision
  BEFORE INSERT OR UPDATE ON public.event_revisions
  FOR EACH ROW EXECUTE FUNCTION public.validate_event_revision();

-- ── Admin review ──────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.approve_event_revision(p_revision_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rev    public.event_revisions%ROWTYPE;
  ev     public.events%ROWTYPE;
  upd    public.events%ROWTYPE;
  c      jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins can approve change requests.';
  END IF;

  SELECT * INTO rev FROM public.event_revisions WHERE id = p_revision_id FOR UPDATE;
  IF NOT FOUND OR rev.status <> 'pending' THEN
    RAISE EXCEPTION 'This change request is no longer waiting for review.';
  END IF;
  SELECT * INTO ev FROM public.events WHERE event_id = rev.event_id FOR UPDATE;
  IF now() >= public.event_starts_at(ev) THEN
    RAISE EXCEPTION 'This event has already started, so the change can''t be applied. Reject it instead.';
  END IF;

  c := rev.changes;
  UPDATE public.events SET
    title            = CASE WHEN c ? 'title'            THEN c->>'title'                 ELSE title END,
    description      = CASE WHEN c ? 'description'      THEN c->>'description'           ELSE description END,
    event_type       = CASE WHEN c ? 'event_type'       THEN c->>'event_type'            ELSE event_type END,
    location         = CASE WHEN c ? 'location'         THEN c->>'location'              ELSE location END,
    event_date       = CASE WHEN c ? 'event_date'       THEN (c->>'event_date')::date    ELSE event_date END,
    end_date         = CASE WHEN c ? 'end_date'         THEN (c->>'end_date')::date      ELSE end_date END,
    start_time       = CASE WHEN c ? 'start_time'       THEN (c->>'start_time')::time    ELSE start_time END,
    end_time         = CASE WHEN c ? 'end_time'         THEN (c->>'end_time')::time      ELSE end_time END,
    max_participants = CASE WHEN c ? 'max_participants' THEN (c->>'max_participants')::int ELSE max_participants END,
    allow_walk_in    = CASE WHEN c ? 'allow_walk_in'    THEN (c->>'allow_walk_in')::boolean ELSE allow_walk_in END,
    event_image_url  = CASE WHEN c ? 'event_image_url'  THEN c->>'event_image_url'       ELSE event_image_url END,
    updated_at       = now()
  WHERE event_id = ev.event_id
  RETURNING * INTO upd;          -- trg_validate_event_schedule re-checks the schedule

  -- Date / time / venue changed → registered students get "Event updated".
  IF upd.event_date IS DISTINCT FROM ev.event_date
     OR upd.end_date   IS DISTINCT FROM ev.end_date
     OR upd.start_time IS DISTINCT FROM ev.start_time
     OR upd.end_time   IS DISTINCT FROM ev.end_time
     OR upd.location   IS DISTINCT FROM ev.location
  THEN
    UPDATE public.events SET
      schedule_changed_at  = now(),
      schedule_change_note = to_char(ev.event_date + COALESCE(ev.start_time, time '08:00'),
                                     'Mon FMDD, FMHH12:MI AM')
                             || COALESCE(' · ' || NULLIF(btrim(ev.location), ''), '')
    WHERE event_id = ev.event_id;
  END IF;

  UPDATE public.event_revisions
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  WHERE id = rev.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_event_revision(p_revision_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins can reject change requests.';
  END IF;
  IF COALESCE(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'Please give a reason — the organizer will see it.';
  END IF;
  UPDATE public.event_revisions
  SET status = 'rejected', rejection_reason = btrim(p_reason),
      reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
  WHERE id = p_revision_id AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This change request is no longer waiting for review.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_event_revision(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.reject_event_revision(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_event_revision(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_event_revision(uuid, text) TO authenticated;
