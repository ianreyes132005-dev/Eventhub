import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── Constants ──────────────────────────────────────────────────────────────────
const GROQ_URL    = 'https://api.groq.com/openai/v1/chat/completions'
const GROQ_MODEL  = 'llama-3.1-8b-instant'
const DAILY_LIMIT = 100   // max user messages per user per calendar day (UTC)

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ── Helpers ────────────────────────────────────────────────────────────────────
function errRes(
  status:  number,
  code:    string,
  message: string,
  extra?:  Record<string, unknown>,
): Response {
  return new Response(
    JSON.stringify({ error: code, message, ...extra }),
    { status, headers: { ...cors, 'Content-Type': 'application/json' } },
  )
}

// ── Entry point ────────────────────────────────────────────────────────────────
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    // ── 1. Authenticate ──────────────────────────────────────────────────────
    // Only signed-in app users can call this function.
    // supabase_flutter automatically sends the user's JWT as Authorization.
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return errRes(401, 'unauthorized', 'Authentication required.')
    }

    // Create a scoped client that runs as the requesting user (respects RLS).
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: { user }, error: authErr } = await supabase.auth.getUser()
    if (authErr || !user) {
      return errRes(401, 'unauthorized', 'Invalid or expired session.')
    }

    // ── 2. Per-user daily quota (bill-shock protection) ──────────────────────
    // Reuses the existing chat_messages table — no extra tables needed.
    // Quota resets at midnight UTC every day.
    const todayUtc = new Date()
    todayUtc.setUTCHours(0, 0, 0, 0)

    const { data: sessions } = await supabase
      .from('chat_sessions')
      .select('id')
      .eq('user_id', user.id)

    if (sessions && sessions.length > 0) {
      const sessionIds = (sessions as Array<{ id: string }>).map((s) => s.id)

      const { count } = await supabase
        .from('chat_messages')
        .select('*', { count: 'exact', head: true })
        .in('session_id', sessionIds)
        .eq('role', 'user')
        .gte('created_at', todayUtc.toISOString())

      if (count !== null && count >= DAILY_LIMIT) {
        return errRes(
          429,
          'quota_exceeded',
          `You've reached your daily limit of ${DAILY_LIMIT} messages. Your quota resets at midnight UTC.`,
        )
      }
    }

    // ── 3. Parse request body ────────────────────────────────────────────────
    const body = await req.json() as {
      messages: Array<{ role: string; content: string }>
      userRole?: string
    }

    const { messages, userRole = 'student' } = body

    if (!Array.isArray(messages) || messages.length === 0) {
      return errRes(400, 'bad_request', 'messages must be a non-empty array.')
    }

    // ── 4. Call Groq ─────────────────────────────────────────────────────────
    // The API key lives only here as a Supabase secret — never in the client.
    const groqKey = Deno.env.get('GROQ_API_KEY')
    if (!groqKey) {
      console.error('[ai-chat] GROQ_API_KEY secret is not set.')
      return errRes(500, 'config_error', 'The AI service is not configured. Contact your administrator.')
    }

    const groqRes = await fetch(GROQ_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${groqKey}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        model:       GROQ_MODEL,
        max_tokens:  1024,
        temperature: 0.7,
        messages: [
          { role: 'system', content: buildSystemPrompt(userRole) },
          ...messages,
        ],
      }),
    })

    // ── 5. Handle Groq-level errors ──────────────────────────────────────────
    if (!groqRes.ok) {
      // Rate limit from Groq's side (distinct from our per-user quota above).
      if (groqRes.status === 429) {
        const retryAfter = parseInt(groqRes.headers.get('retry-after') ?? '60', 10)
        console.warn(`[ai-chat] Groq rate-limited user=${user.id}, retry-after=${retryAfter}s`)
        return errRes(
          429,
          'rate_limited',
          `The AI service is busy. Please wait ${retryAfter} seconds and try again.`,
          { retryAfter },
        )
      }
      if (groqRes.status === 401) {
        console.error('[ai-chat] Groq rejected the API key.')
        return errRes(502, 'ai_auth_error', 'AI service authentication failed. Contact your administrator.')
      }
      const errBody = await groqRes.text()
      console.error(`[ai-chat] Groq ${groqRes.status}:`, errBody)
      return errRes(502, 'ai_error', 'The AI service returned an error. Please try again.')
    }

    // ── 6. Return the reply ──────────────────────────────────────────────────
    const groqBody = await groqRes.json() as {
      choices: Array<{ message: { content: string } }>
    }
    const text = groqBody.choices?.[0]?.message?.content ?? ''

    return new Response(
      JSON.stringify({ text }),
      { headers: { ...cors, 'Content-Type': 'application/json' } },
    )

  } catch (e) {
    console.error('[ai-chat] Unhandled error:', e)
    return errRes(500, 'internal_error', 'An unexpected error occurred.')
  }
})

// ── System prompt ──────────────────────────────────────────────────────────────
// Lives server-side so clients cannot inspect or tamper with it.
function buildSystemPrompt(role: string): string {
  const isOrg = role === 'organizer'
  return `You are EventHub Assistant, a friendly AI helper built into J-Jireh EventHub — a school event management app.
Your role is to clearly answer questions for ${isOrg ? 'event organizers' : 'students'}.

## App overview
J-Jireh EventHub is a mobile app for managing school events with three user types: Students, Organizers, and Admins.

## Student features
- Browse events with filters (Upcoming, Ongoing, Past) and search by name, venue, or type
- Register for events → receive a unique QR code ticket immediately after registering
- Check-in flow: organizer scans QR → student takes a selfie → organizer confirms → status = Checked In
- "My Registered Events" page shows all registrations with live status badges
- Notifications bell shows announcements and check-in updates
- Profile page: view full name, year level, LRN/student ID; change password under the Security tab

## Organizer features
- Create events with title, date, time, location, description, banner image, capacity, and type
- Edit and manage existing events; the Manage button shows per-event registration and check-in stats
- Post announcements that appear in every student's notification feed
- Registrations tab: filter by Pending, Awaiting Selfie, Photo Submitted, or Checked In
- QR scanner (gold button, centre of bottom nav bar) — scans a student QR code to begin check-in
- After scanning: tap "Confirm & Request Selfie" → student takes a selfie → approve to mark Checked In
- Home dashboard shows a weekly registration bar chart and an event attendance line chart

## Common questions
- Login: email + password. "Forgot Password?" sends a reset link by email.
- Accounts are created by the school administrator — students and organizers cannot self-register.
- QR code: auto-generated after registration. Tap "My QR Code" or "View QR Code" to display it.
- Check-in status order: pending → qr_scanned → photo_required → photo_submitted → checked_in
- Camera permission is required for student selfies and organizer QR scanning.
- The app needs an active internet connection.
- Organizers can delete a registration from the ⋯ menu in the Registrations tab.

## Rules
- Keep replies short: 2–4 sentences for simple questions; numbered steps for processes.
- Friendly and professional tone, suitable for a school setting.
- If unsure, say so and suggest contacting the school administrator.
- Never invent app features not listed above.`
}
