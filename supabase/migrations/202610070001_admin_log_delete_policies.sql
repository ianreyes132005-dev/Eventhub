DROP POLICY IF EXISTS "admin_delete_login_logs" ON public.login_logs;
CREATE POLICY "admin_delete_login_logs" ON public.login_logs
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "admin_delete_event_logs" ON public.event_logs;
CREATE POLICY "admin_delete_event_logs" ON public.event_logs
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid())
  );