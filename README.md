# Japan travel discovery — backend engine

A personalised, social-media-style discovery feed for locally hosted events and
experiences in **Tokyo, Kyoto, and Osaka**. Travelers increasingly find what to
do through short-form video, but turning that inspiration into an actual
itinerary is fragmented. This engine connects visual discovery to real event
details, saving, and day-by-day planning.

**Scope: backend and engine only.** The UI is built by a separate team against
[`docs/api-contract.md`](docs/api-contract.md).

---

## What this is

There is **no application server**. The client calls Postgres functions through
PostgREST, and Postgres enforces every permission itself via Row Level Security.
That removes the tier which usually breaks under time pressure, and RLS is what
this product would use in production anyway.

- **[`docs/architecture.md`](docs/architecture.md)** — system diagram, ER model, end-to-end dataflow, scoring breakdown
- **[`docs/api-contract.md`](docs/api-contract.md)** — every RPC, TypeScript types, media rendering rules

```
supabase/migrations/0001_schema.sql     tables, generated lat/lng, triggers
supabase/migrations/0002_scoring.sql    experience_cards view, scoring, feed()
supabase/migrations/0003_actions.sql    every button in the product
supabase/migrations/0004_rls.sql        authorization, in the database
supabase/seed.sql                       10 countries, 3 cities, 19 neighborhoods, 20 experiences
```

## Setup

```bash
cp .env.example .env        # fill in Supabase credentials

for f in supabase/migrations/*.sql supabase/seed.sql; do
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
