// @ts-nocheck
// Admin-only: set a new password for a student or organizer login.
// Called from the admin dashboard's Edit Student / Edit Organizer dialogs.
// Body: { role: 'student' | 'organizer', id: <LRN | organizer_id>, password }
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
    // ── 1. Parse + validate body ─────────────────────────────────────────────
    const { role, id, password } = await req.json()
    if (role !== 'student' && role !== 'organizer') {
      return errRes(400, 'Role must be "student" or "organizer".')
    }
    if (!id) return errRes(400, role === 'student' ? 'LRN is required.' : 'Organizer ID is required.')
    if (typeof password !== 'string' || password.length < 6) {
      return errRes(400, 'The new password must be at least 6 characters.')
    }

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
    if (!adminRow) return errRes(403, 'Only admins can reset passwords.')

    // ── 4. Find the account's login ──────────────────────────────────────────
    const { data: row } = role === 'student'
      ? await supabaseAdmin.from('students').select('user_id').eq('lrn', id).maybeSingle()
      : await supabaseAdmin.from('organizers').select('user_id').eq('organizer_id', id).maybeSingle()
    if (!row) return errRes(404, role === 'student' ? 'Student not found.' : 'Organizer not found.')
    if (!row.user_id) return errRes(400, 'This account has no login yet, so there is no password to reset.')

    // ── 5. Set the new password ──────────────────────────────────────────────
    const { error: updErr } =
      await supabaseAdmin.auth.admin.updateUserById(row.user_id, { password })
    if (updErr) return errRes(400, `Could not reset the password: ${updErr.message}`)

    return okRes({ success: true })
  } catch (e) {
    return errRes(500, String(e))
  }
})
