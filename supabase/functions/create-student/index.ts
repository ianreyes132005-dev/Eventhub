// @ts-nocheck
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Must match `kRequiredLrnPrefix` in lib/core/app_colors.dart — the student
// login screen only asks for the last 4 digits of the LRN and rebuilds the
// rest from that constant, so any account created with a different prefix
// here could never actually be logged into. Keep both in sync by hand.
const REQUIRED_LRN_PREFIX = '12345626'

function formatLrn(rawDigits: string): string {
  return `${rawDigits.slice(0, 6)} - ${rawDigits.slice(6, 8)} - ${rawDigits.slice(8, 12)}`
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
    const { lrn, full_name, year_level, password } = await req.json()

    const rawLrn = String(lrn ?? '').replace(/\D/g, '')
    if (!rawLrn || !/^\d{12}$/.test(rawLrn))
      return errRes(400, 'LRN must be exactly 12 digits.')
    if (!rawLrn.startsWith(REQUIRED_LRN_PREFIX)) {
      const prefixDisplay = `${REQUIRED_LRN_PREFIX.slice(0, 6)} - ${REQUIRED_LRN_PREFIX.slice(6, 8)}`
      return errRes(400, `LRN must start with ${prefixDisplay} — students log in with only the last 4 digits.`)
    }
    if (!full_name?.trim())
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
    if (!adminRow) return errRes(403, 'Only admins can create student accounts.')

    // ── 4. Check LRN not already taken ───────────────────────────────────────
    const formattedLrn = formatLrn(rawLrn)
    const { data: existing } = await supabaseAdmin
      .from('students').select('lrn').eq('lrn', formattedLrn).maybeSingle()
    if (existing) return errRes(409, `LRN ${formattedLrn} already exists.`)

    // ── 5. Create auth user (email always built from the raw digits, so it
    // matches what the login screen reconstructs regardless of how the LRN
    // is formatted for storage) ───────────────────────────────────────────────
    const email = `${rawLrn}@gmail.com`
    const { data: created, error: createErr } =
      await supabaseAdmin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      })
    if (createErr) return errRes(400, createErr.message)

    // ── 6. Insert student row (LRN stored dash-formatted for readability) ────
    const { error: insertErr } = await supabaseAdmin.from('students').insert({
      lrn:        formattedLrn,
      user_id:    created.user.id,
      full_name:  full_name.trim(),
      year_level: year_level ?? null,
      is_active:  true,
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
