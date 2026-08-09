# Meguri — Japan travel discovery

A mobile-first discovery app for locally hosted events, festivals and experiences across
**Tokyo, Kyoto and Osaka** — and for turning what you find into a day-by-day itinerary.

The premise: travellers increasingly discover what to do through short-form video, but turning
that inspiration into an actual plan is fragmented. Meguri connects visual discovery directly to
event details, saving, and scheduling.

---

## Running it

```bash
npm install
npm run dev        # http://localhost:3000
```

No API keys, no database, no external services. Everything runs from local mock data and
`localStorage`. Refreshing the page keeps your state.

```bash
npm run build && npm start   # production build
```

Designed at **390 × 844**. On desktop the app stays phone-width and centres against an ambient
ground so it reads as a mobile product rather than a stretched page.

---

## Demo flow

1. **Splash** — "Get started", or **"I already have a trip"** to skip onboarding with a
   pre-filled traveller (useful on a second run-through).
2. **Onboarding** — a preview of how the app works, then destinations, interests, travel style,
   dates, budget, and a free-text "tell us more" step with voice dictation.
3. **Explore → Deck** — swipe right to save, left to pass, up to schedule. Tap a card for detail.
   Every card carries a match chip explaining *why* it surfaced.
4. **Event detail** — full description, facts, location, organiser, tags, related experiences,
   and the full list of reasons it was picked for you.
5. **Save / Add to itinerary** — two distinct actions. Saving is a wishlist; adding asks for a
   day and time, and warns about clashes.
6. **Saved** — a gallery of what you liked, with **Build my itinerary** to place everything at once.
7. **Itinerary** — a date-grouped timeline with times, venues, travel legs between stops, clash
   flags and per-day costs. The sparkle button opens an assistant that can move, remove, lighten
   or add.
8. **Profile** — everything from onboarding, editable. Change the description box, tap
   **Update my feed**, and the deck visibly re-ranks.

**Keyboard equivalents on the deck** (also the easiest way to demo on a laptop):
`←` pass · `→` save · `↑` add to itinerary · `Enter` details · `S` share · `Z` undo

---

## Architecture

```
src/
├─ app/
│  ├─ page.tsx                 splash + route decision
│  ├─ onboarding/              7-step flow, voice step, generating screen
│  └─ (tabs)/                  tab shell: Saved · Explore · Itinerary · Profile
├─ components/
│  ├─ explore/                 swipe deck, cards, filters, browse sections, map
│  ├─ detail/                  event detail sheet, location preview
│  ├─ schedule/                day/time picker with clash detection
│  ├─ itinerary/               assistant chat sheet
│  ├─ media/                   the one place any visual is rendered
│  ├─ onboarding/              calendar, voice input
│  ├─ nav/                     bottom navigation
│  └─ ui/                      primitives, sheet, toaster
├─ lib/
│  ├─ types.ts                 domain types
│  ├─ data/experiences.ts      21 seeded experiences
│  ├─ scoring.ts               deterministic, explainable recommender
│  ├─ itinerary.ts             auto-scheduler, clashes, travel estimates
│  ├─ filters.ts               search, filters, browse sections
│  ├─ ai.ts                    itinerary assistant intents
│  ├─ voice.ts                 speech-to-text hook
│  ├─ format.ts                dates, money, recurrence expansion
│  └─ storage.ts               persistence seam
└─ store/                      AppStore (data) · UIStore (overlays, toasts)
```

### Personalization

`lib/scoring.ts` is a deterministic scoring function — no ML, and the same inputs always produce
the same ranking. Every point a card scores traces back to one traveller-facing sentence, which is
what the match chip renders:

| Signal | Example explanation |
| --- | --- |
| Interest overlap | "Because you like street food" |
| Destination / neighbourhood | "In Ueno, on your Tokyo list" |
| Date compatibility | "Only on while you're here — 21 Aug" |
| Budget fit | "Fits your budget" / "Free to attend" |
| Travel style | "A good one for two" |
| Saved / dismissed history | "You've saved 3 other food things" |
| Free-text description | "You mentioned 'jazz' and 'vintage'" |

Dismissing several things in a category visibly pushes that category down.

### Scheduling

Experiences are either **one-off** (a festival, a concert) or **recurring** (a market, a
restaurant, a weekly session). `occurrencesWithin()` expands both against the traveller's dates,
which is why the feed is never empty whatever dates are picked, and why one-off events can be
flagged as time-sensitive.

`buildItinerary()` places the fewest-option items first, so a one-night festival never loses its
slot to a market that runs daily. It prefers days inside each city's block and days that aren't
already busy. Overlaps are surfaced, never silently resolved.

### Media

`components/media/ExperienceMedia.tsx` is the only component that renders an experience visual.
This build ships **no imagery** — every slot draws a marked placeholder so layout, typography and
contrast can be judged without art.

To connect real media, point a `MediaAsset` at a source; no screen changes are needed:

```ts
{ id: "m1", provider: "video",     url: "https://…/clip.mp4", poster: "…", alt: "…" }
{ id: "m2", provider: "instagram", url: "https://www.instagram.com/p/…/embed", alt: "…" }
```

Instagram and TikTok go through their **official embed endpoints** only. Nothing is scraped,
downloaded or rehosted. A failed video or embed silently falls back to the placeholder — a broken
player is never shown.

---

## Connecting real services

Everything degrades gracefully; nothing blocks on a missing key.

| Capability | Today | To connect |
| --- | --- | --- |
| **Persistence** | `localStorage` via `Repository` in `lib/storage.ts` | Write a second `Repository` implementation (e.g. Supabase) and change one line in `store/AppStore.tsx`. The domain types map directly onto tables. |
| **Maps** | Schematic preview plotting real lat/lng; "Get directions" already opens the platform map app | Set `NEXT_PUBLIC_MAPS_EMBED_KEY` — `MapPreview` swaps to a real embed automatically. |
| **Speech to text** | Browser `SpeechRecognition`, with a typed fallback when unavailable | Implement a `/api/transcribe` route against ElevenLabs Scribe and record with `MediaRecorder`; `useVoiceInput` keeps its shape (see the note in `lib/voice.ts`). |
| **Itinerary assistant** | Deterministic intent matching in `lib/ai.ts` — offline, reproducible | Have `interpret()` call a model and return the same `AiAction` shape. The chat UI and apply/undo flow are unchanged. |
| **Event data** | 21 seeded experiences in `lib/data/experiences.ts` | Replace the seed module with a fetch. `Experience` is the contract. |

---

## Product decisions worth knowing

- **Saved and Itinerary are deliberately separate.** Saved means "I'm interested"; Itinerary means
  "this is happening, at this time". Every card therefore has two distinct positive actions.
- **No likes, no comments.** Social proof is saves and shares only, so the product reads as a
  planning tool rather than a feed.
- **One accent colour.** Vermillion is reserved for saving, active navigation, match chips and the
  timeline's today marker. Nothing else competes.
- **Every state is designed.** Skeletons shaped like real content, empty states that always carry a
  working button, and no dead controls anywhere.
- **Explanations are everywhere.** The match chip appears on the deck, in detail, in Saved and in
  search results — the consistency is what makes the personalization legible.

### Assumptions made

- Content is realistic but demo data; prices, hosts and save counts are representative, and
  one-off dates are generated relative to today so the feed is always current.
- The traveller's trip is a single contiguous date range across up to three cities.
- Travel legs are straight-line estimates, not routed transit times.

### Not in this build

Drag-to-reorder within a day (Reschedule covers it), swipe-to-reveal row actions (buttons are
visible instead), and profile photo upload (a monogram avatar is used).

---

## Accessibility

- Every swipe has a button and a keyboard equivalent; the deck card is focusable and announces
  its name, price and match reason.
- Overlay text always sits on a gradient scrim, so contrast holds regardless of what's behind it.
- `prefers-reduced-motion` is respected throughout.
- Sheets trap escape, lock background scroll, and are labelled.
