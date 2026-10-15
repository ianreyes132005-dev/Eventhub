-- Remove the legacy blanket SELECT policies. PostgreSQL ORs permissive
-- policies together, so either policy would expose pending and rejected
-- events despite the approval-only policy.
DROP POLICY IF EXISTS "Anyone can view events" ON public.events;
DROP POLICY IF EXISTS "authenticated_select_events" ON public.events;

DROP POLICY IF EXISTS "public_select_approved_events" ON public.events;
CREATE POLICY "public_select_approved_events" ON public.events
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND approval_status = 'approved'
  );

DROP POLICY IF EXISTS "organizer_select_own_events" ON public.events;
CREATE POLICY "organizer_select_own_events" ON public.events
  FOR SELECT USING (
    organizer_id = (
      SELECT organizer_id
      FROM public.organizers
      WHERE user_id = auth.uid()
    )
  );

-- Recreate the explicit admin policy so removing the blanket policy does not
-- hide pending submissions from the admin review queue.
DROP POLICY IF EXISTS "admin_events_select" ON public.events;
CREATE POLICY "admin_events_select" ON public.events
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.admins
      WHERE user_id = auth.uid()
    )
  );
