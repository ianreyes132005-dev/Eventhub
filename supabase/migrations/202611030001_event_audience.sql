-- ═════════════════════════════════════════════════════════════════════════════
-- Who can register: an event can be open to every student (as before) or only
-- to some grades, and — for Senior High — some strands.
--
-- 1. events.audience_grades  integer[]  grades 7–12 that can register; NULL =
--                                       every student (whatever their grade).
--    events.audience_strands text[]     Senior High strands (HUMSS, GAS, STEM)
--                                       that can register; NULL = any strand.
--                                       Only filters Grades 11–12: a Junior
--                                       High grade in the list stays open to
--                                       all of that grade.
--    Every existing event keeps NULL / NULL, so nothing changes for it.
--
-- 2. Students outside an event's group still SEE it (the apps label it, e.g.
--    "Senior High only", with no Register button), but the database refuses
--    their registration. A student with no grade on file can only register
--    for events open to every student.
--
-- 3. Capacity = the active students in the group: active_student_counts()
--    returns the count per grade and strand, and the apps add up the ones the
--    group allows (active_student_count() stays for "every student").
--
-- 4. On a live (approved) event the group is changed through a change
--    request, like the other details. Students who already registered keep
--    their registration if the group is narrowed.
--
-- The apps use the same rule (EventAudience.allows in
-- lib/core/event_audience.dart); keep the two the same.
--
-- Run once in the Supabase SQL editor, after 202610280001. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── Columns ──────────────────────────────────────────────────────────────────
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS audience_grades  integer[],
  ADD COLUMN IF NOT EXISTS audience_strands text[];

COMMENT ON COLUMN public.events.audience_grades IS
  'Grades (7–12) that can register; NULL = every student.';
COMMENT ON COLUMN public.events.audience_strands IS
  'Senior High strands that can register (filters Grades 11–12 only); NULL = any strand.';

ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_audience_check;
ALTER TABLE public.events ADD CONSTRAINT events_audience_check CHECK (
  (audience_grades IS NULL
    OR (cardinality(audience_grades) > 0
        AND audience_grades <@ ARRAY[7, 8, 9, 10, 11, 12]))
  AND (audience_strands IS NULL
    OR (audience_grades IS NOT NULL
        AND audience_grades && ARRAY[11, 12]
        AND cardinality(audience_strands) > 0
        AND audience_strands <@ ARRAY['HUMSS', 'GAS', 'STEM']))
);

-- ── The rule ─────────────────────────────────────────────────────────────────
-- Can a student in [p_grade] / [p_strand] register for an event open to
-- [p_grades] / [p_strands]?
CREATE OR REPLACE FUNCTION public.event_audience_allows(
  p_grades integer[], p_strands text[], p_grade integer, p_strand text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_grades IS NULL THEN true
    WHEN p_grade IS NULL OR NOT (p_grade = ANY (p_grades)) THEN false
    WHEN p_grade < 11 OR p_strands IS NULL THEN true
    ELSE COALESCE(p_strand = ANY (p_strands), false)
  END;
$$;

-- jsonb list → array, for change requests (NULL / JSON null → NULL).
CREATE OR REPLACE FUNCTION public.jsonb_to_int_array(j jsonb)
RETURNS integer[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN j IS NULL OR jsonb_typeof(j) <> 'array' THEN NULL
              ELSE ARRAY(SELECT x::integer FROM jsonb_array_elements_text(j) AS x) END;
$$;

CREATE OR REPLACE FUNCTION public.jsonb_to_text_array(j jsonb)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN j IS NULL OR jsonb_typeof(j) <> 'array' THEN NULL
              ELSE ARRAY(SELECT x FROM jsonb_array_elements_text(j) AS x) END;
$$;

-- ── Capacity: active students per grade and strand ──────────────────────────
CREATE OR REPLACE FUNCTION public.active_student_counts()
RETURNS TABLE (grade integer, strand text, students integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT s.year_level, s.strand, count(*)::integer
  FROM public.students s
  WHERE s.is_active IS TRUE
  GROUP BY s.year_level, s.strand;
$$;
REVOKE EXECUTE ON FUNCTION public.active_student_counts() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.active_student_counts() TO authenticated;

-- ── Registration rules: as in 202610210003, plus who can register ───────────
CREATE OR REPLACE FUNCTION public.enforce_registration_insert_rules()
RETURNS TRIGGER AS $$
DECLARE
  ev        public.events%ROWTYPE;
  st_grade  integer;
  st_strand text;
BEGIN
  SELECT * INTO ev
    FROM public.events
    WHERE event_id = NEW.event_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Event not found.';
  END IF;

  IF ev.approval_status != 'approved' THEN
    RAISE EXCEPTION 'Registration is closed — this event has not been approved yet.';
  END IF;

  IF ev.event_status = 'cancelled' THEN
    RAISE EXCEPTION 'Registration is closed — this event was cancelled.';
  END IF;

  IF now() >= public.event_ends_at(ev) THEN
    RAISE EXCEPTION 'Registration is closed — this event has already ended.';
  END IF;

  IF ev.registration_deadline IS NOT NULL THEN
    IF now() > ev.registration_deadline THEN
      RAISE EXCEPTION 'Registration is closed — the deadline has passed.';
    END IF;
  ELSIF now() >= public.event_starts_at(ev) + interval '2 hours' THEN
    RAISE EXCEPTION 'Registration is closed — it closes 2 hours after the event starts.';
  END IF;

  IF ev.audience_grades IS NOT NULL THEN
    SELECT s.year_level, s.strand INTO st_grade, st_strand
      FROM public.students s
      WHERE s.user_id = NEW.student_user_id;
    IF st_grade IS NULL THEN
      RAISE EXCEPTION 'This event is only open to some grade levels, and your grade level isn''t on file yet. Ask the school administrator to add it.';
    END IF;
    IF NOT public.event_audience_allows(ev.audience_grades, ev.audience_strands,
                                        st_grade, st_strand) THEN
      RAISE EXCEPTION 'This event isn''t open to your grade level or strand.';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.registrations
    WHERE event_id = NEW.event_id
      AND student_user_id = NEW.student_user_id
  ) THEN
    RAISE EXCEPTION 'You''re already registered for this event.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Change requests (202610180007), now including who can register ──────────

-- An organizer can't change a LIVE event's details directly — it must go
-- through a change request.
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
       OR NEW.registration_deadline IS DISTINCT FROM OLD.registration_deadline
       OR NEW.audience_grades  IS DISTINCT FROM OLD.audience_grades
       OR NEW.audience_strands IS DISTINCT FROM OLD.audience_strands)
  THEN
    RAISE EXCEPTION 'This event is live, so changes need admin approval. Submit them as a change request.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Change requests: only for live events that haven't started; only editable
-- columns; the resulting schedule and group must be valid.
CREATE OR REPLACE FUNCTION public.validate_event_revision()
RETURNS TRIGGER AS $$
DECLARE
  ev      public.events%ROWTYPE;
  c       jsonb := NEW.changes;
  bad     text;
  grades  integer[];
  strands text[];
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
                  'allow_walk_in', 'event_image_url',
                  'audience_grades', 'audience_strands')
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

  IF c ?| array['audience_grades', 'audience_strands'] THEN
    grades  := CASE WHEN c ? 'audience_grades'
                    THEN public.jsonb_to_int_array(c->'audience_grades') ELSE ev.audience_grades END;
    strands := CASE WHEN c ? 'audience_strands'
                    THEN public.jsonb_to_text_array(c->'audience_strands') ELSE ev.audience_strands END;
    IF grades IS NOT NULL
       AND (cardinality(grades) = 0 OR NOT grades <@ ARRAY[7, 8, 9, 10, 11, 12]) THEN
      RAISE EXCEPTION 'Pick at least one grade from 7 to 12.';
    END IF;
    IF strands IS NOT NULL
       AND (grades IS NULL OR NOT grades && ARRAY[11, 12]
            OR cardinality(strands) = 0 OR NOT strands <@ ARRAY['HUMSS', 'GAS', 'STEM']) THEN
      RAISE EXCEPTION 'Strands can only narrow Senior High grades (11–12) to HUMSS, GAS or STEM.';
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
    audience_grades  = CASE WHEN c ? 'audience_grades'
                            THEN public.jsonb_to_int_array(c->'audience_grades')    ELSE audience_grades END,
    audience_strands = CASE WHEN c ? 'audience_strands'
                            THEN public.jsonb_to_text_array(c->'audience_strands')  ELSE audience_strands END,
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

REVOKE ALL ON FUNCTION public.approve_event_revision(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_event_revision(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
