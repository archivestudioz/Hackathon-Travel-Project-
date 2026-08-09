# Meguri — Japan travel discovery

A mobile-first discovery app for locally hosted events, festivals and experiences
across **Tokyo, Kyoto and Osaka**, and for turning what you find into a
day-by-day itinerary.

Travellers increasingly find what to do through short-form video, but turning
that inspiration into an actual plan is fragmented. Meguri connects visual
discovery directly to event details, saving, and scheduling.

---

## Two halves, one repo

| | Where | Runs on | Status |
|---|---|---|---|
| **App** — swipe deck, detail sheets, scheduling, itinerary chat | `src/`, `preview/` | Local mock data + `localStorage`. No keys, no database. | Demo-ready standalone |
| **Engine** — schema, scoring, planner, RLS | `supabase/`, `scripts/`, `docs/` | Postgres 16 + PostGIS via Supabase | Verified against a real instance |

**They are not wired together yet, and that is deliberate.** The app ships its
own `src/lib/scoring.ts`, `src/lib/itinerary.ts` and `src/lib/data/experiences.ts`
so it demos with nothing running — which is the right call for a judging table
with unreliable wifi. The engine implements the same concepts in Postgres, at
real data volume, with authorization in the database.

`src/lib/storage.ts` is the seam between them. It defines a `Repository`
interface the whole app talks through; connecting to the engine means writing a
second implementation of that interface and changing one line in `AppStore`.
[`docs/backend-features.md`](docs/backend-features.md) has the full migration
path, and [`docs/roam-client.ts`](docs/roam-client.ts) is the client that would
back it.

### Run the app

```bash
npm install
npm run dev        # http://localhost:3000
```

No API keys, no database, no external services. Full walkthrough, design
system, and demo script in **[`docs/frontend.md`](docs/frontend.md)**.

### Run the engine

```bash
cp .env.example .env
```

Then paste [`supabase/ALL.sql`](supabase/ALL.sql) into the Supabase dashboard
SQL editor and enable **Authentication → Providers → Anonymous**. One paste,
every migration and both seeds. Details below.

---

## What this is

There is **no application server**. The client calls Postgres functions through
PostgREST, and Postgres enforces every permission itself via Row Level Security.
That removes the tier which usually breaks under time pressure, and RLS is what
this product would use in production anyway.

- **[`docs/backend-features.md`](docs/backend-features.md)** — complete feature inventory and the frontend migration path
- **[`docs/architecture.md`](docs/architecture.md)** — system diagram, ER model, end-to-end dataflow, scoring breakdown
- **[`docs/api-contract.md`](docs/api-contract.md)** — every RPC, TypeScript types, media rendering rules
- **[`docs/roam-client.ts`](docs/roam-client.ts)** — drop-in typed client. Copy this one file into the Next.js app and the integration is done.
- **[`docs/fixtures.ts`](docs/fixtures.ts)** — real recorded payloads, so screens can be built before the backend exists.
- **[`docs/itinerary-agent.ts`](docs/itinerary-agent.ts)** + **[`docs/itinerary-chat-route.ts`](docs/itinerary-chat-route.ts)** — the AI chat sheet. **Server only.**

## Integrating the UI

The engine is 36 RPC functions and one card shape. There is no REST layer to
learn and no ORM to configure.

```bash
npm i @supabase/supabase-js          # in the UI repo
cp ../engine/docs/roam-client.ts src/lib/roam.ts
```

```ts
import { getSessionState, getFeed, saveExperience } from '@/lib/roam'

const state = await getSessionState()   // route on state.next_screen
const cards = await getFeed()           // ExperienceCard[], already ranked
await saveExperience(cards[0].experience_id)
```

`ExperienceCard` is identical from `feed()` and `explore()`, so the team builds
**one** card component and reuses it on every surface. Each card arrives with
its media, its social proof, whether you have saved it, and `reasons[0]` —
the line explaining why it surfaced.

### Build screens before the backend exists

```bash
NEXT_PUBLIC_ROAM_FIXTURES=1 npm run dev
```

Every function then returns a **real recorded payload** from `fixtures.ts` —
dumped from the seeded database, not hand-written, so the shapes cannot drift
from what the engine actually returns. Components never learn whether the data
is live, so removing the flag is the entire migration.

This matters most for Figma-generated components, which tend to arrive with
invented prop shapes. Bind them to `ExperienceCard` from the first commit and
there is no later refactor of every card.

```
supabase/migrations/0001_schema.sql     tables, generated lat/lng, triggers
supabase/migrations/0002_scoring.sql    experience_cards view, scoring, feed()
supabase/migrations/0003_actions.sql    every button in the product
supabase/migrations/0004_rls.sql        authorization, in the database
supabase/migrations/0005_age_band.sql   age bands; under-18 hard filter
supabase/migrations/0006_ingestion.sql  city bboxes, locality scoring
supabase/migrations/0007_cold_start.sql the three-tap picker, learned affinity
supabase/migrations/0008_guest_*.sql    guest mode, exploration vs exploitation
supabase/migrations/0009_accounts.sql   auth triggers, session_state()
supabase/migrations/0010_attribution.sql creator credit, enforced by constraint
supabase/migrations/0011_multicity_*.sql trip legs, build_itinerary()
supabase/migrations/0012_gambling_*.sql  age gate covers kyotei betting
supabase/seed.sql                       10 countries, 3 cities, 19 neighborhoods, 26 experiences
supabase/seed_catalog.sql               10 more, seeded because there is real video of them
content/video-catalog.md                39 clips your team pulled, described
content/clip-map.tsv                    which reach the product, and why the rest do not
```

## Setup

```bash
cp .env.example .env        # fill in Supabase credentials

for f in supabase/migrations/*.sql supabase/seed.sql supabase/seed_catalog.sql; do
  psql "$SUPABASE_DB_URL" -f "$f"
done
```

Then enable **Authentication → Providers → Anonymous** in the Supabase
dashboard. That is the entire setup — no keys required for the app to run.

### Smoke test

```sql
-- a food-and-nightlife traveler going to Osaka
select left(name,38), city, score, reasons[1] from feed(5);
```

## Two-stage onboarding

Signup asks **broad questions only** — which countries you travel to, why you
travel, what you are into. No city, no dates, no budget: those are trip
questions, and asking them at signup would force someone to have a trip planned
before they are allowed to look at anything.

The deeper questions come later, when the traveler decides to plan: exact city,
dates and duration, the neighbourhood they are staying in, party, budget, pace.

| | Stage 1 — profile | Stage 2 — trip |
|---|---|---|
| When | Signup | "Create an itinerary" |
| Scope | Evergreen, one per person | One per journey, many allowed |
| Table | `traveler_profiles` | `trips` |

**The feed works in both states.** With no trip it is an *inspiration* feed on
interests, countries, and reasons — nothing is penalised for being in the wrong
city, because the traveler has not said where they are going. Create a trip and
it becomes a *planning* feed where city, dates, and budget all count.

Saves live on the **profile**, not a trip, so someone can save a Kyoto workshop
eighteen months out; `trip_suggestions()` hands it back when they finally plan
Kyoto. That bridge is why the two tables are separate.

There is no password and no email — anonymous auth means a traveler is scrolling
within seconds, and onboarding can be skipped entirely without the app breaking.

## The engine

**Personalisation is deterministic, not learned.** Two reasons that is the right
call and not just the fast one: a judge can be shown exactly why any card
surfaced, and the same inputs always produce the same feed, so a demo cannot
embarrass you by ranking differently on the third run.

Score and explanation are produced by the same expression, so they cannot drift
apart — the "why" on the card *is* the reason it ranked.

```
Because you like street food · In Shibuya, where you're staying
Happening during your Osaka dates · Locally hosted, not on the tourist trail
```

Signals: interest overlap, destination match, trip-date fit, budget fit, travel
style, save/dismiss affinity by category, a locality bonus, and damped social
proof. Full weighting table in [`docs/architecture.md`](docs/architecture.md).

**Local over touristic.** `experiences.locality` (0–1) actively promotes
locally-hosted, lesser-known things and drives the *Hidden local gems* rail.
Well-known attractions are seeded deliberately — without them the score has
nothing to rank against.

## The chat sheet — the one place with a server

> *"Make Day 2 lighter." · "Move the ramen tour later." · "Add something free on Thursday."*

Claude **Sonnet 5** sits on top of the itinerary with eight tools, and every one
of them is an RPC the screen's own buttons already call. It has no database
connection and writes no SQL — anything the sheet can do, a thumb could have
done. It returns the plan *after* the edits, so the timeline re-renders without
a refetch.

This is the only surface in the product with a server tier, and it exists for
exactly one reason: an Anthropic key cannot ship to a browser the way the
Supabase anon key can. The route holds that one secret and makes no
authorization decision — it forwards the traveler's own access token and lets
RLS answer, same as every other call. The trip id is pinned server-side and
never comes from the model.

```bash
npm i @anthropic-ai/sdk zod
echo 'ANTHROPIC_API_KEY=sk-ant-...' >> .env.local   # NOT NEXT_PUBLIC_
```

## Media, and the one hard rule

`experience_media` stores **pointers and attribution only**. No video is ever
downloaded or rehosted; the schema has no column for it. Embeds resolve
client-side through the official TikTok and Instagram oEmbed endpoints, both
keyless as of 2026, with creator attribution rendered alongside.

Everything ships seeded as `placeholder`, so the app looks finished with zero
API keys. Swapping in a real post is a data change, not a code change.

## Sponsors

All integrations run **offline, before a demo**, and write to the database, so
nothing in the request path can be broken by a third party being slow.

| Sponsor | Role |
|---|---|
| **Stay22** | Direct Travel API — accommodation near a venue → `experiences.stay22_url` |
| **Tavily** | Build-time enrichment: descriptions, hidden-gem signals, finding embeddable posts |
| **AeroXplorer** | Optional arrival context; not on the core path |

## Verified

Applied and exercised against a real Postgres 16 + PostGIS instance:

- Clean install of all four migrations plus seed
- Two travelers with different profiles receive **genuinely different feeds** with different explanations
- The **inspiration feed works with no trip**, and creating one visibly re-ranks it toward that city
- Skipping onboarding entirely still returns a sensible feed — no blank screen
- Budget, destination, and interest weighting all change ranking as intended
- Full journey: signup → feed → save → create trip → suggestions → itinerary grouped by day
- A second trip leaves taste and the first trip untouched
- Itinerary days are clamped inside the trip window
- **RLS isolation**: traveler B sees 0 of traveler A's saves and itinerary, while both see all 20 catalogue rows; signed-out browsing still works
