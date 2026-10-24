import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Server-side sign-in lockout (app and web portal): 5 failed attempts within
// 15 minutes lock the account for 30 seconds. Called before sign-in, so it's
// deployed with --no-verify-jwt; the one action that could undo the lockout
// (clear) checks the caller's session itself.

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MAX_ATTEMPTS = 5             // failures before lockout
const LOCK_MS      = 30_000        // 30-second lockout; resets counter on expiry
const WINDOW_MS    = 15 * 60_000   // failures older than this stop counting

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const body = await req.json() as {
      identifier?: string
      action?: 'check' | 'record' | 'clear'
    }
    // Sign-in emails are case-insensitive; one spelling per account.
    const identifier = String(body.identifier ?? '').trim().toLowerCase()
    const action = body.action

    if (!identifier || !action) return json({ error: 'Missing identifier or action' }, 400)

    // Service-role client — bypasses RLS; this table must not be client-accessible.
    const db = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    )

    // ── check ──────────────────────────────────────────────────────────────────
    if (action === 'check') {
      // A few typos last week shouldn't count toward a lockout today.
      const since = new Date(Date.now() - WINDOW_MS).toISOString()
      const pruned = await db.from('login_rate_limits').delete()
        .eq('identifier', identifier).lt('attempted_at', since)
      if (pruned.error) throw pruned.error

      const { data: rows, error } = await db
        .from('login_rate_limits')
        .select('attempted_at')
        .eq('identifier', identifier)
        .order('attempted_at', { ascending: false })
      if (error) throw error

      const attempts = rows?.length ?? 0

      if (attempts >= MAX_ATTEMPTS) {
        const lastAt      = rows![0].attempted_at
        const lockedUntil = new Date(new Date(lastAt).getTime() + LOCK_MS)

        if (lockedUntil <= new Date()) {
          // Lockout expired — clear records so the counter resets for this identifier
          const reset = await db.from('login_rate_limits').delete().eq('identifier', identifier)
          if (reset.error) throw reset.error
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
      const { error } = await db.from('login_rate_limits').insert({ identifier })
      if (error) throw error
      return json({ ok: true })
    }

    // ── clear ──────────────────────────────────────────────────────────────────
    // Only right after a successful sign-in to this same account: the app
    // calls it with the new session. Otherwise anyone could wipe the counter
    // between guesses and the lockout would never trigger.
    if (action === 'clear') {
      const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
      const { data, error } = await db.auth.getUser(token)
      const email = data?.user?.email?.toLowerCase()
      if (error || !email || email !== identifier) {
        return json({ error: 'Not allowed' }, 403)
      }
      const cleared = await db.from('login_rate_limits').delete().eq('identifier', identifier)
      if (cleared.error) throw cleared.error
      return json({ ok: true })
    }

    return json({ error: 'Unknown action' }, 400)
  } catch (err) {
    // A database error is a 500, not a silent "allowed" — the app already
    // lets the sign-in through when this function fails, and the function
    // logs show why.
    console.error('[login-rate-limit]', err)
    const message = (err as { message?: string })?.message ?? String(err)
    return json({ error: 'Internal error', message }, 500)
  }
})
