import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_ATTEMPTS = 5        // failures before lockout
const LOCK_MS      = 30_000   // 30-second lockout; resets counter on expiry

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { identifier, action } = await req.json() as {
      identifier: string
      action: 'check' | 'record' | 'clear'
    }

    if (!identifier || !action) return json({ error: 'Missing identifier or action' }, 400)

    // Service-role client — bypasses RLS; this table must not be client-accessible.
    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // ── check ──────────────────────────────────────────────────────────────────
    if (action === 'check') {
      const { data: rows } = await db
        .from('login_rate_limits')
        .select('attempted_at')
        .eq('identifier', identifier)
        .order('attempted_at', { ascending: false })

      const attempts = rows?.length ?? 0

      if (attempts >= MAX_ATTEMPTS) {
        const lastAt      = rows![0].attempted_at
        const lockedUntil = new Date(new Date(lastAt).getTime() + LOCK_MS)

        if (lockedUntil <= new Date()) {
          // Lockout expired — clear records so the counter resets for this identifier
          await db.from('login_rate_limits').delete().eq('identifier', identifier)
          return json({ allowed: true, attemptsRemaining: MAX_ATTEMPTS })
        }

        return json({
          allowed:           false,
          lockedUntil:       lockedUntil.toISOString(),
          attemptsRemaining: 0,
        })
      }

      return json({ allowed: true, attemptsRemaining: MAX_ATTEMPTS - attempts })
    }

    // ── record ─────────────────────────────────────────────────────────────────
    if (action === 'record') {
      await db.from('login_rate_limits').insert({ identifier })
      return json({ ok: true })
    }

    // ── clear ──────────────────────────────────────────────────────────────────
    if (action === 'clear') {
      await db.from('login_rate_limits').delete().eq('identifier', identifier)
      return json({ ok: true })
    }

    return json({ error: 'Unknown action' }, 400)
  } catch (err) {
    return json({ error: 'Internal error', message: String(err) }, 500)
  }
})
