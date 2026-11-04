-- ═════════════════════════════════════════════════════════════════════════════
-- Admin dashboard: the Registration trend and the KPI totals, counted in the
-- database.
--
-- The dashboard used to download every registration and count them in the
-- browser. Supabase returns at most 1,000 rows per request, so past 1,000
-- registrations the trend, the Registrations total and the check-in rate were
-- worked out from whichever 1,000 rows came back. These functions count on the
-- server and return one small JSON value.
--
-- One rule throughout: a declined registration (status 'rejected') isn't a
-- registration (the apps' countsAsRegistered). Days are school days
-- (Asia/Manila), like event_starts_at / event_ends_at. Attendance is final
-- once check-in has closed, 2 hours after the event ends (202610280001).
--
--   admin_dashboard_totals()      the KPI cards: registrations, students,
--                                 and the check-in rate over events whose
--                                 attendance is final
--   admin_registration_trend(...) the Registration trend card: sign-ups per
--                                 day with their events, the previous
--                                 period's total, student reach by grade and
--                                 strand for a school year, and registered
--                                 vs attended per week
--
-- Administrator only. Run once in the Supabase SQL editor, after
-- 202610280001. Safe to rerun.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_dashboard_totals()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only the administrator can see these numbers.';
  END IF;

  SELECT jsonb_build_object(
    'registrations', (SELECT count(*) FROM public.registrations x
                      WHERE x.status IS DISTINCT FROM 'rejected'),
    'students', (SELECT count(*) FROM public.students),
    'students_active', (SELECT count(*) FROM public.students s
                        WHERE s.is_active IS TRUE),
    -- Events whose attendance is final: registered vs checked in.
    'final_registered', count(*) FILTER (WHERE r.status IS DISTINCT FROM 'rejected'),
    'final_attended', count(*) FILTER (WHERE r.status = 'checked_in')
  )
  INTO result
  FROM public.registrations r
  JOIN public.events e ON e.event_id = r.event_id
  WHERE e.event_status IS DISTINCT FROM 'cancelled'
    AND now() > public.event_ends_at(e) + interval '2 hours';

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_totals() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_totals() TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_registration_trend(
  p_from        date,  -- first day of the chart (school time)
  p_to          date,  -- last day, included
  p_prev_from   date,  -- the period it's compared with
  p_prev_to     date,
  p_school_year date   -- first day of the school year for student reach
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  tz constant text := 'Asia/Manila';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only the administrator can see these numbers.';
  END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to OR p_to - p_from > 400
     OR p_prev_from IS NULL OR p_prev_to IS NULL OR p_prev_from > p_prev_to
     OR p_school_year IS NULL THEN
    RAISE EXCEPTION 'Pick a period of up to one school year.';
  END IF;

  RETURN jsonb_build_object(
    -- Sign-ups per school day and event (declined left out), so the chart
    -- can say which event most sign-ups were for.
    'days', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'day', d.day, 'event_id', d.event_id, 'title', d.title, 'n', d.n)
             ORDER BY d.day, d.n DESC)
      FROM (
        SELECT (r.registered_at AT TIME ZONE tz)::date AS day,
               r.event_id, e.title, count(*) AS n
        FROM public.registrations r
        JOIN public.events e ON e.event_id = r.event_id
        WHERE r.status IS DISTINCT FROM 'rejected'
          AND r.registered_at >= (p_from::timestamp AT TIME ZONE tz)
          AND r.registered_at <  ((p_to + 1)::timestamp AT TIME ZONE tz)
        GROUP BY 1, 2, 3
      ) d), '[]'::jsonb),

    'previous', (
      SELECT count(*) FROM public.registrations r
      WHERE r.status IS DISTINCT FROM 'rejected'
        AND r.registered_at >= (p_prev_from::timestamp AT TIME ZONE tz)
        AND r.registered_at <  ((p_prev_to + 1)::timestamp AT TIME ZONE tz)),

    -- The earliest sign-up: the school years the dashboard offers.
    'first_day', (
      SELECT min((r.registered_at AT TIME ZONE tz)::date)
      FROM public.registrations r
      WHERE r.status IS DISTINCT FROM 'rejected'),

    -- Active students per grade and strand, and how many of them joined at
    -- least one event of the school year (by its date; cancelled events and
    -- declined registrations don't count).
    'reach', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'grade', g.grade, 'strand', g.strand,
               'students', g.students, 'reached', g.reached))
      FROM (
        SELECT s.year_level AS grade,
               NULLIF(btrim(s.strand), '') AS strand,
               count(*) AS students,
               count(j.user_id) AS reached
        FROM public.students s
        LEFT JOIN (
          SELECT DISTINCT r.student_user_id AS user_id
          FROM public.registrations r
          JOIN public.events e ON e.event_id = r.event_id
          WHERE r.status IS DISTINCT FROM 'rejected'
            AND e.event_status IS DISTINCT FROM 'cancelled'
            AND e.event_date >= p_school_year
            AND e.event_date <  (p_school_year + interval '1 year')::date
        ) j ON j.user_id = s.user_id
        WHERE s.is_active IS TRUE
        GROUP BY 1, 2
      ) g), '[]'::jsonb),

    -- Registered vs attended per week (Monday) for the period's events whose
    -- attendance is final.
    'attendance', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'week', w.week, 'registered', w.registered,
               'attended', w.attended, 'events', w.events)
             ORDER BY w.week)
      FROM (
        SELECT date_trunc('week', e.event_date::timestamp)::date AS week,
               count(*) FILTER (WHERE r.status IS DISTINCT FROM 'rejected') AS registered,
               count(*) FILTER (WHERE r.status = 'checked_in') AS attended,
               count(DISTINCT e.event_id) AS events
        FROM public.events e
        JOIN public.registrations r ON r.event_id = e.event_id
        WHERE e.event_status IS DISTINCT FROM 'cancelled'
          AND e.approval_status = 'approved'
          AND e.event_date BETWEEN p_from AND p_to
          AND now() > public.event_ends_at(e) + interval '2 hours'
        GROUP BY 1
      ) w), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_registration_trend(date, date, date, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_registration_trend(date, date, date, date, date)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
