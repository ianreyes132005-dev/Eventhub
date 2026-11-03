-- Notify active, eligible students when an event becomes visible to them.
-- Student in-app notices are derived from events.reviewed_at for 14 days;
-- this trigger sends the corresponding outside-app FCM message.

CREATE OR REPLACE FUNCTION public.push_newly_approved_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  recipients uuid[];
  event_title text := COALESCE(NULLIF(btrim(NEW.title), ''), 'An event');
BEGIN
  IF NEW.approval_status IS DISTINCT FROM 'approved'
     OR (TG_OP = 'UPDATE' AND OLD.approval_status IS NOT DISTINCT FROM 'approved')
     OR NEW.archived_at IS NOT NULL
     OR NEW.event_status = 'cancelled' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(array_agg(s.user_id), ARRAY[]::uuid[])
  INTO recipients
  FROM public.students s
  WHERE s.is_active IS TRUE
    AND s.user_id IS NOT NULL
    AND public.event_audience_allows(
      NEW.audience_grades,
      NEW.audience_strands,
      s.year_level,
      s.strand
    );

  PERFORM public.dispatch_eventhub_push(
    recipients,
    'New event available',
    format('"%s" is now available on EventHub. Tap to view event details.',
      event_title),
    jsonb_build_object(
      'type', 'event_published',
      'event_id', NEW.event_id::text
    )
  );
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.push_newly_approved_event() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_push_newly_approved_event ON public.events;
CREATE TRIGGER trg_push_newly_approved_event
  AFTER INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.push_newly_approved_event();

DROP TRIGGER IF EXISTS trg_push_approved_event_students ON public.events;
CREATE TRIGGER trg_push_approved_event_students
  AFTER UPDATE OF approval_status ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.push_newly_approved_event();
