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
    const { organizer_id, full_name, first_name, middle_name, last_name, organization, password } =
      await req.json()

    // Name parts are optional for backward compatibility; when present,
    // full_name is always rebuilt from them ("First Last"). The middle name
    // is optional and stored on its own, not in full_name.
    const first  = String(first_name ?? '').trim()
    const middle = String(middle_name ?? '').trim()
    const last   = String(last_name ?? '').trim()
    const displayName = first && last ? `${first} ${last}` : String(full_name ?? '').trim()

    if (!organizer_id || !/^Org\d{4}$/i.test(organizer_id))
      return errRes(400, 'Organizer ID must be Org followed by 4 digits (e.g. Org0001).')
    if (!displayName)
      return errRes(400, 'Full name is required.')
    if (!password || password.length < 6)
      return errRes(400, 'Password must be at least 6 characters.')

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
    if (!adminRow) return errRes(403, 'Only admins can create organizer accounts.')

    // ── 4. Check organizer_id not already taken ───────────────────────────────
    // Normalize to Org#### regardless of user's casing (e.g. ORG0001 → Org0001)
    const id = 'Org' + organizer_id.trim().slice(3)
    const { data: existing } = await supabaseAdmin
      .from('organizers').select('organizer_id').eq('organizer_id', id).maybeSingle()
    if (existing) return errRes(409, `Organizer ID ${id} is already in use.`)

    // ── 5. Create auth user  (email = {organizer_id.toLowerCase()}@gmail.com) ─
    const email = `${id.toLowerCase()}@gmail.com`
    const { data: created, error: createErr } =
      await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      })
    if (createErr) return errRes(400, createErr.message)

    // ── 6. Insert organizers row ──────────────────────────────────────────────
    const { error: insertErr } = await supabaseAdmin.from('organizers').insert({
      organizer_id: id,
      user_id:      created.user.id,
      full_name:    displayName,
      first_name:   first || null,
      middle_name:  middle || null,
      last_name:    last || null,
      organization: organization?.trim() || null,
      is_active:    true,
    })

    if (insertErr) {
      // Roll back the auth user so nothing is left dangling
      await supabaseAdmin.auth.admin.deleteUser(created.user.id)
      return errRes(400, insertErr.message)
    }

    return okRes({ success: true, user_id: created.user.id })
  } catch (e) {
    return errRes(500, String(e))
  }
})
