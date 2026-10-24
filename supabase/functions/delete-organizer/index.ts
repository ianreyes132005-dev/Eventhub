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
    const { organizer_id } = await req.json()
    if (!organizer_id) return errRes(400, 'Organizer ID is required.')

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
    if (!adminRow) return errRes(403, 'Only admins can delete organizer accounts.')

    // ── 4. Look up the organizer to get their auth user id ────────────────────
    const { data: organizer } = await supabaseAdmin
      .from('organizers').select('user_id').eq('organizer_id', organizer_id).maybeSingle()
    if (!organizer) return errRes(404, 'Organizer not found.')

    // ── 4b. Archived events keep the school's attendance records, so this
    // account can only be deactivated (the database refuses the cascade too —
    // migration 202610230003). Checked before anything is deleted. ──────────
    const { count: archived, error: countErr } = await supabaseAdmin
      .from('events')
      .select('event_id', { count: 'exact', head: true })
      .eq('organizer_id', organizer_id)
      .not('archived_at', 'is', null)
    if (countErr) return errRes(400, countErr.message)
    if ((archived ?? 0) > 0) {
      return errRes(409, 'This organizer has archived events, so the account can be ' +
        'deactivated but not deleted.')
    }

    // ── 5. Delete the login credential first. If this fails, nothing else has
    // changed yet, so we never leave the profile deleted but the login still
    // working (the bug this function exists to close). ───────────────────────
    if (organizer.user_id) {
      const { error: authDelErr } =
        await supabaseAdmin.auth.admin.deleteUser(organizer.user_id)
      if (authDelErr && !`${authDelErr.message}`.toLowerCase().includes('not found')) {
        return errRes(400, `Could not remove login credentials: ${authDelErr.message}`)
      }
    }

    // ── 6. Delete the organizer row. Their events and those events'
    // registrations cascade away with this row (see eventhub_database.sql). ───
    const { error: deleteErr } = await supabaseAdmin
      .from('organizers').delete().eq('organizer_id', organizer_id)
    if (deleteErr) return errRes(400, deleteErr.message)

    return okRes({ success: true })
  } catch (e) {
    return errRes(500, String(e))
  }
})
