/**
 * Next.js App Router handler for the itinerary chat sheet.
 *
 *   cp docs/itinerary-agent.ts       src/lib/itinerary-agent.ts
 *   cp docs/itinerary-chat-route.ts  src/app/api/itinerary/chat/route.ts
 *   npm i @anthropic-ai/sdk zod
 *   echo 'ANTHROPIC_API_KEY=sk-ant-...' >> .env.local     # NOT NEXT_PUBLIC_
 *
 * This route exists for exactly one reason: the Anthropic API key must not
 * reach the browser. Everything else in this product is a direct
 * browser-to-Postgres call with no server tier, and that is deliberate — but a
 * key that bills your account is not something Row Level Security can protect.
 * So there is one server route, it holds one secret, and it holds nothing else.
 *
 * Note what this handler does NOT do: it does not use the service-role key, it
 * does not look up the traveler in a session store, and it does not decide what
 * they are allowed to touch. It forwards their access token and lets Postgres
 * answer that question, same as every other call in the app.
 */

import { NextResponse } from 'next/server'
import { runItineraryChat, type ChatTurn } from '@/lib/itinerary-agent'

// The tool loop can take several seconds on a multi-step edit; the Node runtime
// gives a longer ceiling than Edge and the SDK is happier there.
export const runtime = 'nodejs'
export const maxDuration = 60

interface Body {
  tripId?: string
  messages?: ChatTurn[]
}

export async function POST(request: Request) {
  // The client sends the Supabase session token it already holds. There is no
  // second identity here — if this header is missing or stale, PostgREST will
  // reject the RPCs and the traveler sees nothing but their own empty state.
  const auth = request.headers.get('authorization') ?? ''
  const accessToken = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!accessToken) {
    return NextResponse.json({ error: 'not signed in' }, { status: 401 })
  }

  let body: Body
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: 'malformed body' }, { status: 400 })
  }

  const { tripId, messages } = body
  if (!tripId || !Array.isArray(messages) || messages.length === 0) {
    return NextResponse.json({ error: 'tripId and messages are required' }, { status: 400 })
  }
  // The sheet is a short conversation about one screen. Cap it so a long-lived
  // tab cannot grow the prompt without bound.
  if (messages.length > 40) {
    return NextResponse.json({ error: 'conversation too long' }, { status: 413 })
  }

  try {
    const result = await runItineraryChat({
      accessToken,
      tripId,
      messages,
      signal: request.signal,
    })
    return NextResponse.json(result)
  } catch (err) {
    // Never forward the raw error: it can contain the Postgres message, which
    // names tables and columns. Log it server-side, hand the sheet a sentence.
    console.error('[itinerary-chat]', err)
    return NextResponse.json(
      { error: 'I could not change the plan just now. Try again in a moment.' },
      { status: 502 },
    )
  }
}
