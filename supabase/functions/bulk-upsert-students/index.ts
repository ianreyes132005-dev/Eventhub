// @ts-nocheck
// Bulk create / update student accounts from a registrar list (admin only).
//
// Body: { rows: [{ action: 'create' | 'update', lrn, first_name, last_name,
//                  middle_name?, year_level, strand?, section?,
//                  password? (create only) }] }
// middle_name is only written when the row includes it (null clears it), so
// a list without middle names never erases ones already saved.
// Max 50 rows per call — the admin dashboard sends the import in batches so
// one call stays well inside the edge-function time limit.
//
// Each row is processed independently; one failure never blocks the rest.
// Response: { results: [{ lrn, ok, action, error? }] } in the same order.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_ROWS = 50
const STRANDS  = ['HUMSS', 'GAS', 'STEM']

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

// Shared validation for both actions. Returns an error message or null.
function validate(r: any): string | null {
  const raw = String(r.lrn ?? '').replace(/\D/g, '')
  if (!/^\d{12}$/.test(raw)) return 'LRN must be exactly 12 digits.'
  if (!String(r.first_name ?? '').trim()) return 'First name is required.'
  if (!String(r.last_name ?? '').trim())  return 'Last name is required.'
  const yr = Number(r.year_level)
  if (!Number.isInteger(yr) || yr < 7 || yr > 12) return 'Grade level must be 7–12.'
  if ((yr === 11 || yr === 12) && !STRANDS.includes(r.strand))
    return 'Senior High students need a strand (HUMSS, GAS, or STEM).'
  if (r.action === 'create' && String(r.password ?? '').length < 6)
    return 'Password must be at least 6 characters.'
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { rows } = await req.json()
    if (!Array.isArray(rows) || rows.length === 0) return errRes(400, 'No rows to import.')
    if (rows.length > MAX_ROWS) return errRes(400, `Send at most ${MAX_ROWS} rows per request.`)

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // ── Verify the caller is an admin ─────────────────────────────────────────
    const token = req.headers.get('Authorization')?.replace('Bearer ', '')
    if (!token) return errRes(401, 'Unauthorized.')
    const { data: { user }, error: authErr } = await supabaseAdmin.auth.getUser(token)
    if (authErr || !user) return errRes(401, 'Unauthorized.')
    const { data: adminRow } = await supabaseAdmin
      .from('admins').select('admin_id').eq('user_id', user.id).maybeSingle()
    if (!adminRow) return errRes(403, 'Only admins can import student accounts.')

    const results = []
    for (const r of rows) {
      const raw = String(r.lrn ?? '').replace(/\D/g, '')
      const res = { lrn: raw, action: r.action, ok: false, error: null as string | null }
      results.push(res)

      const invalid = validate(r)
      if (invalid) { res.error = invalid; continue }

      const first  = String(r.first_name).trim()
      const last   = String(r.last_name).trim()
      const yr     = Number(r.year_level)
      const isShs  = yr === 11 || yr === 12
      const fields = {
        first_name: first,
        last_name:  last,
        full_name:  `${first} ${last}`,
        year_level: yr,
        strand:     isShs ? r.strand : null,
        section:    String(r.section ?? '').trim() || null,
      }
      if ('middle_name' in r) fields.middle_name = String(r.middle_name ?? '').trim() || null
      const formatted = formatLrn(raw)

      try {
        // Older rows may store the LRN as raw digits, newer ones dash-formatted.
        const { data: existing } = await supabaseAdmin
          .from('students').select('lrn').in('lrn', [formatted, raw]).maybeSingle()

        if (r.action === 'update') {
          if (!existing) { res.error = 'Student not found.'; continue }
          const { error } = await supabaseAdmin
            .from('students').update(fields).eq('lrn', existing.lrn)
          if (error) { res.error = error.message; continue }
          res.ok = true
          continue
        }

        // ── create ──────────────────────────────────────────────────────────
        if (existing) { res.error = `LRN ${formatted} already exists.`; continue }

        const { data: created, error: createErr } =
          await supabaseAdmin.auth.admin.createUser({
            email: `${raw}@gmail.com`,
            password: String(r.password),
            email_confirm: true,
          })
        if (createErr) { res.error = createErr.message; continue }

        const { error: insertErr } = await supabaseAdmin.from('students').insert({
          lrn:       formatted,
          user_id:   created.user.id,
          is_active: true,
          ...fields,
        })
        if (insertErr) {
          // Roll back the auth user so nothing is left dangling.
          await supabaseAdmin.auth.admin.deleteUser(created.user.id)
          res.error = insertErr.message
          continue
        }
        res.ok = true
      } catch (e) {
        res.error = String(e)
      }
    }

    return okRes({ results })
  } catch (e) {
    return errRes(500, String(e))
  }
})
