import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

type PushRequest = {
  user_ids?: unknown
  title?: unknown
  body?: unknown
  data?: unknown
}

type ServiceAccount = {
  client_email: string
  private_key: string
  project_id: string
}

const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

let cachedAccessToken: string | null = null
let accessTokenExpiresAt = 0

function jsonResponse(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function base64Url(value: Uint8Array | string): string {
  const encoded = typeof value === 'string'
    ? btoa(String.fromCharCode(...new TextEncoder().encode(value)))
    : btoa(String.fromCharCode(...value))
  return encoded.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

async function getGoogleAccessToken(
  account: ServiceAccount,
): Promise<string> {
  if (cachedAccessToken && Date.now() < accessTokenExpiresAt - 60_000) {
    return cachedAccessToken
  }

  const now = Math.floor(Date.now() / 1000)
  const unsignedJwt = [
    base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' })),
    base64Url(JSON.stringify({
      iss: account.client_email,
      scope: FCM_SCOPE,
      aud: GOOGLE_TOKEN_URL,
      iat: now,
      exp: now + 3600,
    })),
  ].join('.')
  const privateKeyPem = account.private_key.replace(/\\n/g, '\n')
  const privateKeyBase64 = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const privateKeyBytes = Uint8Array.from(atob(privateKeyBase64), (c) =>
    c.charCodeAt(0))
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    privateKeyBytes.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      privateKey,
      new TextEncoder().encode(unsignedJwt),
    ),
  )
  const assertion = `${unsignedJwt}.${base64Url(signature)}`
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  })
  const result = await response.json()
  if (!response.ok || typeof result.access_token !== 'string') {
    throw new Error(`Google OAuth token request failed (${response.status}).`)
  }
  cachedAccessToken = result.access_token
  accessTokenExpiresAt = Date.now() + Number(result.expires_in ?? 3600) * 1000
  return cachedAccessToken
}

function dataPayload(value: unknown): Record<string, string> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {}
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .filter(([key]) => /^[a-zA-Z0-9_.-]{1,128}$/.test(key))
      .map(([key, item]) => [
        key,
        typeof item === 'string' ? item : JSON.stringify(item),
      ]),
  )
}

serve(async (req) => {
  if (req.method !== 'POST') {
    return jsonResponse(405, { error: 'method_not_allowed' })
  }

  const webhookSecret = Deno.env.get('PUSH_WEBHOOK_SECRET')
  if (!webhookSecret ||
      req.headers.get('x-eventhub-push-secret') !== webhookSecret) {
    return jsonResponse(401, { error: 'unauthorized' })
  }

  try {
    const body = await req.json() as PushRequest
    if (!Array.isArray(body.user_ids) || body.user_ids.length > 5000) {
      return jsonResponse(400, { error: 'invalid_recipients' })
    }

    const userIds = [...new Set(
      body.user_ids.filter(
        (id): id is string => typeof id === 'string' && UUID_PATTERN.test(id),
      ),
    )]
    if (userIds.length === 0) return jsonResponse(200, { sent: 0 })

    const title = typeof body.title === 'string'
      ? body.title.trim().slice(0, 200)
      : 'EventHub update'
    const messageBody = typeof body.body === 'string'
      ? body.body.trim().slice(0, 2000)
      : ''
    const data = dataPayload(body.data)

    const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!serviceAccountJson || !supabaseUrl || !serviceRoleKey) {
      console.error('[send-push] Required service secrets are not configured.')
      return jsonResponse(500, { error: 'push_not_configured' })
    }

    const account = JSON.parse(serviceAccountJson) as ServiceAccount
    if (!account.client_email || !account.private_key || !account.project_id) {
      console.error('[send-push] FCM service account JSON is incomplete.')
      return jsonResponse(500, { error: 'invalid_fcm_service_account' })
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })
    const tokens: Array<{ token: string }> = []
    for (let offset = 0; offset < userIds.length; offset += 500) {
      let tokenOffset = 0
      while (true) {
        const { data: rows, error } = await admin
          .from('push_tokens')
          .select('token')
          .in('user_id', userIds.slice(offset, offset + 500))
          .range(tokenOffset, tokenOffset + 999)
        if (error) {
          console.error(`[send-push] Could not load device tokens: ${error.message}`)
          return jsonResponse(500, { error: 'token_lookup_failed' })
        }
        tokens.push(...(rows ?? []))
        if ((rows?.length ?? 0) < 1000) break
        tokenOffset += 1000
      }
    }
    if (tokens.length === 0) return jsonResponse(200, { sent: 0 })

    const accessToken = await getGoogleAccessToken(account)
    let sent = 0
    const staleTokens: string[] = []
    for (let offset = 0; offset < tokens.length; offset += 20) {
      const batch = tokens.slice(offset, offset + 20)
      const results = await Promise.all(batch.map(async ({ token }) => {
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${accessToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token,
                notification: { title, body: messageBody },
                data,
                android: {
                  priority: 'HIGH',
                  notification: {
                    channel_id: 'eventhub_notifications',
                    sound: 'default',
                  },
                },
              },
            }),
          },
        )
        if (response.ok) return 'sent' as const
        const result = await response.json().catch(() => ({}))
        const status = result?.error?.status
        if (status === 'UNREGISTERED') {
          staleTokens.push(token)
          return 'stale' as const
        }
        console.error(`[send-push] FCM rejected a message (${response.status}, ${status ?? 'unknown'}).`)
        return 'failed' as const
      }))
      sent += results.filter((result) => result === 'sent').length
    }

    for (const token of staleTokens) {
      const { error } = await admin.from('push_tokens').delete().eq('token', token)
      if (error) console.error('[send-push] Could not remove a stale device token.')
    }

    return jsonResponse(200, { sent, stale: staleTokens.length })
  } catch (error) {
    console.error('[send-push] Delivery failed:', error)
    return jsonResponse(500, { error: 'delivery_failed' })
  }
})
