// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function errRes(status: number, message: string): Response {
  return new Response(
    JSON.stringify({ error: true, message }),
    { status, headers: { ...cors, 'Content-Type': 'application/json' } },
  )
}

function okRes(data: unknown): Response {
  return new Response(
    JSON.stringify(data),
    { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } },
  )
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    // ── 1. Parse body ────────────────────────────────────────────────────────
    const { lrn } = await req.json()
    if (!lrn) return errRes(400, 'LRN is required.')

    // ── 2. Build admin client (service role — never exposed to client) ────────
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // ── 3. Verify the caller is an admin ─────────────────────────────────────
    const token = req.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) return errRes(401, 'Unauthorized.')

    const { data: { user }, error: authErr } =
      await supabaseAdmin.auth.getUser(token)
    if (authErr || !user) return errRes(401, 'Unauthorized.')

    const { data: adminRow } = await supabaseAdmin
      .from('admins').select('admin_id').eq('user_id', user.id).maybeSingle()
    if (!adminRow) return errRes(403, 'Only admins can delete student accounts.')

    // ── 4. Look up the student to get their auth user id ─────────────────────
    const { data: student } = await supabaseAdmin
      .from('students').select('user_id').eq('lrn', lrn).maybeSingle()
    if (!student) return errRes(404, 'Student not found.')

    // ── 5. Delete the login credential first. If this fails, nothing else has
    // changed yet, so we never leave the profile deleted but the login still
    // working (the bug this function exists to close). ───────────────────────
    if (student.user_id) {
      const { error: authDelErr } =
        await supabaseAdmin.auth.admin.deleteUser(student.user_id)
      if (authDelErr && !`${authDelErr.message}`.toLowerCase().includes('not found')) {
        return errRes(400, `Could not remove login credentials: ${authDelErr.message}`)
      }
    }

    // ── 6. Delete the profile row. Idempotent — registrations referencing this
    // user cascade away with the auth user above, so this just removes the
    // remaining profile data (may already be gone via its own cascade). ───────
    const { error: deleteErr } = await supabaseAdmin
      .from('students').delete().eq('lrn', lrn)
    if (deleteErr) return errRes(400, deleteErr.message)

    return okRes({ success: true })
  } catch (e) {
    return errRes(500, String(e))
  }
})
