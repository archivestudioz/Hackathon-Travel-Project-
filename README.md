# Roam

**The first travel guide you listen to instead of read.**

Roam connects travelers with **local guides — on foot, by car, or by boat** — and helps them find
what's actually worth doing: restaurants, beaches, attractions, hikes, culture, and live events.
Stops narrate themselves in your language as you approach them. A **wifi layer** runs underneath,
because travelers usually don't have international service.

Built at **Checkout**, NYC's travel & hospitality hackathon. Track 3 — *Local & experiences*.

---

## Why this doesn't already exist

The market splits cleanly in half, and nobody has joined it:

| | Human guide | Audio | Live | On-demand |
|---|:---:|:---:|:---:|:---:|
| Viator · GetYourGuide | ✅ | ❌ | ❌ | ❌ book days ahead |
| Airbnb Experiences | ✅ | ❌ | ❌ | ❌ scheduled |
| VoiceMap · izi.TRAVEL · GPSmyCity | ❌ you're alone | ✅ | ❌ | ✅ |
| **Roam** | ✅ | ✅ | ✅ | ✅ |

Audio tour apps give you narration but no human. Marketplaces give you a human but no live
experience. Roam is the first that's both.

---

## Three cities, three transport realities

Each demo city breaks a different assumption, which is how we prove nothing is hardcoded:

| City | Modes | What it stresses |
|---|---|---|
| **New York** | walk · drive | Density, huge event inventory, LinkNYC free wifi |
| **San Juan** | walk · drive | Beaches, Spanish-first, cruise-day time windows |
| **Venice** | walk · **boat** | **No cars exist.** The vaporetto is the vehicle. |

Venice is the point: `travel_mode` is a first-class column with its own matching radius, speed,
and stop count — not a toggle. Adding `boat` was one enum value and zero special cases.

---

## Architecture

**There is no application server.** The browser talks to Postgres through PostgREST, and Postgres
enforces every permission itself via Row Level Security. That removes the tier that usually breaks
under time pressure, and RLS is the pattern this product would use in production anyway.

```
Browser (static HTML/JS, no build step)
   │  supabase-js ──────► Postgres RPC   nearby_places · match_guide · plan_route
   │  Realtime    ──────► ride_positions INSERT, rides UPDATE   (WAL → WebSocket)
   │  MapLibre    ──────► Protomaps global  |  ./tiles/*.pmtiles offline fallback
   ▼
Supabase: Postgres + PostGIS + RLS + Realtime + Storage (narration audio)
   ▲ service-role
scripts/simulate_guide.py   — drives the guide's dot; the 2nd device without a 2nd device
scripts/fetch_places.py     — Overpass → seed SQL      (build time)
scripts/narrate.py          — ElevenLabs → MP3 → Storage (build time)
```

**The one trick everything depends on:** every `geography` column carries generated `lat`/`lng`
companions. PostgREST serialises geography as hex EWKB, which the browser can't read — so the
generated columns mean Realtime delivers plain numbers and there's **no decode step in the live
path**.

**Events intertwine with guides for one nullable column.** `ride_stops` takes either a `place_id`
or an `event_id`, so an event is just a stop with a fixed start time. Matching, routing, and live
tracking all work unchanged.

---

## Quickstart

```bash
cp .env.example .env          # fill in Supabase + Protomaps keys
psql "$SUPABASE_DB_URL" -f supabase/migrations/0001_schema.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0002_functions.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0003_rls.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0004_realtime.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0005_auth_hook.sql
psql "$SUPABASE_DB_URL" -f supabase/seed.sql

cp web/config.example.js web/config.js   # paste anon key + Protomaps key
python -m http.server 8080 --directory web
```

In the Supabase dashboard, enable **Authentication → Providers → Anonymous**. The app signs in
anonymously on load, which gives every session a real `auth.uid()` so RLS is genuinely enforced
rather than simulated.

### Smoke test

```sql
select name, category, round(distance_m) from nearby_places(40.7580, -73.9855, 'eat');
select display_name, eta_min from nearby_guides(45.4408, 12.3155, 'boat');  -- Venice
```

---

## Sponsors, and why none of them can break the demo

**Every integration runs at build time, never during judging.** That satisfies the sponsor
requirement and the no-live-third-party-calls rule at the same time.

- **ElevenLabs** — narration in 5 languages (multilingual v2 covers 29), pre-generated into
  Supabase Storage. Audio is the *interface*, not a feature: a traveler is walking with their hands
  full and their eyes on the street, so a screen is the wrong surface. It's also the honest
  accessibility story — low literacy, low vision, unfamiliar script.
- **Stay22** — monetized stays near a tour. Embed needs no API key.
- **Tavily** — build-time enrichment: blurbs, "known for", hidden gems, long-tail local events
  that no ticketing API carries.

## Business model

Ticket affiliate + Stay22 accommodation (30%+ commission) + guide booking fee. One night out
monetizes three ways, and none of it is a subscription charged to the traveler.

## Repo layout

```
supabase/migrations/   schema · functions · RLS · realtime · auth hook
supabase/seed.sql      3 cities, 7 guides, 35 places, 7 events
scripts/               ingestion, narration, guide simulator, demo reset
web/                   the app — one map, one bottom sheet, zero navigation
docs/                  build plan, architecture, demo script
```
