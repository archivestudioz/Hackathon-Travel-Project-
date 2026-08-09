# What the backend does

Complete inventory. 16 tables, 36 client-facing functions, 11 migrations, all
verified against a real Postgres 16 + PostGIS instance.

There is **no application server**. The browser calls Postgres functions through
PostgREST and Row Level Security decides what comes back, so authorization is
enforced in the database rather than in code someone can forget to write. The
one exception is the AI chat sheet (§13), which needs a route handler purely to
keep an Anthropic key out of the browser — it holds that one secret and makes
no authorization decision of its own.

---

## 1. Accounts and identity

| Capability | How |
|---|---|
| **Sign up** with email + password | `supabase.auth.signUp()` — a trigger mints the profile |
| **Continue as guest** | `continueAsGuest()` — anonymous auth, full functionality |
| **Guest → real account, in place** | `updateUser({email, password})` keeps the same `auth.users.id`, so the same profile row. **Every save, dismissal, trip and itinerary survives.** A trigger clears `is_guest` automatically |
| **Know which screen to show** | `session_state()` returns `next_screen: 'welcome' \| 'picker' \| 'feed'` |
| **Nudge signup at the right moment** | `prompt_signup` fires only once a guest has ≥3 saves — prompting an empty guest is how you lose them |
| Profile editing | `update_profile()` — name, avatar, free-text bio, age band |

**Age is a band, not a birthday** (`under_18 · 18_24 · … · 55_plus · undisclosed`).
Less regulated, never goes stale, and it does real work: `under_18`
**hard-filters** bars, nightclubs and anything tagged `alcohol` out of the feed.
Not ranked lower — absent. `undisclosed` is treated as an adult so declining
never degrades the product.

## 2. Onboarding — one screen, three taps

| Capability | How |
|---|---|
| The picker | `cold_start_picks()` — 12 cards, one per category, spread across the locality range |
| Finish onboarding | `complete_cold_start(ids[])` — **derives interests from the taps** |
| Skip entirely | `continue_as_guest()` — the feed still works |
| Optional manual curation | `save_profile_onboarding()` — for the minority who want to set their own |

The taps **become real saves**, so the Saved tab is never empty on first open.
Interests are inferred by intersecting the tapped rows' categories and tags
against the interest vocabulary — nothing is asked.

## 3. The learning engine

This is the part that makes the product sticky, and it runs with no ML.

| Signal | Weight | Why |
|---|---|---|
| Added to an itinerary | **+1.5** | They committed real plans |
| Saved / tapped at cold start | +1.0 | Interest |
| Dismissed | −0.75 | Counts against the whole category, not one card |

- `interest_affinity()` — learned taste, live, per traveler
- `learned_confidence()` — ramps 0→1 across ~20 interactions
- `my_taste()` — exposes both so the profile screen can show what's been learned

**Scoring blends declared and learned taste.** A new account leans on its three
taps; a returning one is driven almost entirely by behaviour. The card
explanation follows: past 0.3 confidence it stops saying *"Because you like
restaurants"* and starts saying **"More like the food you keep saving"**.

*Verified: three taps plus four swipes produced `food +5.0 · nightlife +3.0 ·
traditional +2.0 · art −1.5` with nothing asked.*

## 4. Exploration vs exploitation

A cold feed sorted purely by score returns five variations on one category —
boring to scroll, and the slowest possible way to learn. `exploration_weight()`
runs 1.0 → 0.0 as confidence rises; while high, the deck **round-robins across
categories**.

*Verified: a guest's first eight cards covered eight distinct categories; after
eight swipes it had converged on the two they actually picked.*

## 5. The feed

`feed(trip_id?, limit, offset)` → `ExperienceCard[]`, ranked, with explanations.

Two modes from the same function:

| | **Inspiration** (no trip) | **Planning** (trip exists) |
|---|---|---|
| Ranks on | interests, reasons, countries, locality | all that **plus** city, neighbourhood, dates, budget, party |
| Wrong city | not penalised — they never said where | **−3.5** |
| Over budget | not penalised | scaled penalty by how far over |

Full weight table: interest ±3.0 · reason +1.2 · country +0.8 · city +2.5/−3.5 ·
neighbourhood +1.0 · in-dates +2.5 / outside −2.0 · budget +1.5/scaled ·
travel style +1.0 · locality ×1.2 · profile-text match +1.5 · this week +0.8 ·
social proof (log-damped, capped at 1.0).

Score and explanation come from the **same expression**, so the "why" on a card
literally *is* the reason it ranked. They cannot drift apart.

## 6. Local-first ranking

The product promises local over touristic, so "local" is a number, not a vibe.

`locality` (0–1) is computed geospatially: **count the famous things within
250 m**. A café beside a major shrine is in a tourist zone whatever its own tags
claim; an identical café two neighbourhoods away is not. Adjusted by wikidata
presence, chain status, and whether the host is local.

*Verified on the car scene: Daikoku Futo `0.94` (no organiser, people just turn
up) → Nissan Crossing `0.22` (brand showroom on the Ginza crossing).*

`recompute_localness()` leaves hand-curated rows alone unless forced — the first
version flattened every seeded row to one value.

## 7. Explore, search and filters

`explore()` supports: free text (name, description, venue, tags) · category ·
city · neighbourhood · date range · free-only · max price · four sort modes.

`explore_sections()` returns the three rails in one call:
**Happening this week · Hidden local gems · Popular near you**

Date filters never hide always-on attractions — `starts_at = null` passes any
range, so filtering to "this week" doesn't remove teamLab.

## 8. Swipe actions

`save` · `unsave` · `dismiss` · `undo_dismiss` · `share` · `my_saved`

All idempotent — a double-tap never errors. Behaviours the UI gets free:

- **Saving clears a dismissal; dismissing clears a save.** Last gesture wins.
- Save and share return the **new count**, so optimistic UI reconciles from the response.
- Saves live on the **profile**, not a trip — someone can save a Kyoto workshop
  eighteen months before booking.

## 9. Trips

`trip_options` · `create_trip` · `update_trip` · `delete_trip` · `my_trips` ·
`trip_suggestions`

- Many trips per traveler; taste is never disturbed by planning one
- Accepts **duration or end date** — people think in "four nights", not "which day I fly home"
- `trip_suggestions()` surfaces things already saved in that city and not yet scheduled

## 10. Multi-city trips

A Japan trip is Tokyo then Kyoto then Osaka. `trip_cities` holds the legs in
order, with optional arrival and departure dates; when those are absent the trip
is **split evenly across the legs**, which is what a traveler who has not booked
trains yet expects. `create_trip_multi(['tokyo','kyoto','osaka'], …)`.

Scoring tests city *membership*, not equality — before this, a Kyoto card scored
−3.5 on a trip that literally included Kyoto.

## 11. The planner — "Build my itinerary"

`build_itinerary(trip_id)` turns saves into a day-by-day plan. It does the three
things a person would:

1. **Pins fixed-time events to their own date.** A festival on the 24th cannot
   be moved to balance a day out.
2. **Clusters each day by neighbourhood.** Each day gets an anchor — the best
   unscheduled thing in that day's city — then fills outward from the same
   neighbourhood, so a day is walkable rather than four train rides.
3. **Places each stop at the hour it would actually happen.** Markets at 10:00,
   food at 12:30, izakaya at 21:00, a Daikoku car meet at 21:30.

It **spreads rather than front-loads**: what remains for a city is divided by
the days that city still has, so two Kyoto saves become one on each of two days
instead of both on the first with an empty day after.

Returns `{ scheduled, days_used, unplaced, neighborhoods[], conflicts, summary }`
— the summary string is the toast copy.

**Deterministic.** Verified by rebuilding twice and hashing: identical. A demo
cannot rank differently on the third run.

Supporting functions: `trip_days()` (every day **including empty ones**, for the
day strip), `itinerary_conflicts()`, and `travel_estimate()` which produces the
"~18 min by train" connector between consecutive stops.

## 12. Itinerary

`add_to_itinerary` · `update_itinerary_entry` · `remove_from_itinerary` · `my_itinerary`

- `my_itinerary()` returns **days in order, stops in order** — render as a timeline, no regrouping
- Per-day stop count and total price, precomputed
- Adding also saves and clears any dismissal
- **The day is chosen for you**: the event's own date, else the trip's first day,
  else today — then **clamped inside the trip window**, so a stop can't land on
  a date the traveler isn't there
- Raises `no trip yet` when there's no trip — the cue to open trip creation

## 13. The AI chat sheet — "Make Day 2 lighter"

`docs/itinerary-agent.ts` · `docs/itinerary-chat-route.ts` · `askAboutItinerary()`

Claude **Sonnet 5** sitting on top of the itinerary, driven by eight tools that
are all RPCs from the sections above — `get_plan`, `search_experiences`,
`list_saved`, `add_stop`, `move_stop`, `remove_stop`, `rebuild_plan`,
`check_conflicts`. No database connection, no SQL. Anything the sheet can do, a
thumb could already have done on the same screen.

- Returns `{ reply, actions, plan }` — the plan **after** the edits, so the
  timeline re-renders with no refetch, and `actions` says which row to animate
- The system prompt carries the day strip inline, so "Day 2" means the day
  numbered 2 on the traveler's screen — including the empty ones, which are
  usually the right answer to "add something"
- Display names are resolved to slugs before searching, because `explore()`
  filters on `city_slug` and a name that doesn't match returns zero rows with
  no error — the worst failure mode, since the model would then confidently say
  there's nothing free in Kyoto
- Fixture mode returns a canned reply over the recorded plan, so the sheet gets
  built before anyone has an API key

**The only server tier in the product**, and it exists for exactly one reason:
an Anthropic key can't ship to the browser the way the Supabase anon key can.
The route holds that one secret and nothing else — it forwards the traveler's
own access token, so RLS answers the authorization question, same as every
other call. The trip id is pinned server-side and never comes from the model.

Model notes: `claude-sonnet-5`, adaptive thinking by default, **`budget_tokens`
/ `temperature` / `top_p` / `top_k` all return 400** — `output_config.effort` is
the only dial.

## 14. Media

`experience_media` stores **pointers and attribution only**. No video is ever
copied; the schema has no column for one.

- `kind`: `tiktok · instagram · youtube · hosted_video · image · placeholder`
- Client resolves embeds through the **official oEmbed endpoints** (both keyless as of 2026)
- **A check constraint rejects any embed without both a creator name and a link back**
- `media_credit` is formatted server-side so every surface credits identically
- Everything ships as `placeholder`, so the app looks finished with zero keys

## 15. Content pipeline (offline, never during a demo)

| Script | Does |
|---|---|
| `ingest_places.py` | Overpass → experiences. 13 category→OSM-tag mappings, incl. car culture. Also captures wheelchair access, opening hours, alcohol |
| `enrich_tavily.py` | Descriptions + a capped locality nudge from web sentiment |
| `stay22_links.py` | Accommodation affiliate URLs per venue |
| `attach_media.py` | Recovers post URLs from downloaded filenames, resolves creator + thumbnail, attaches |

Everything third-party runs **before** a demo and writes to the database, so
nothing in the request path can be broken by Overpass being slow.

## 16. Security

RLS on all 15 tables:

- **Public read**: countries, interests, reasons, cities, neighbourhoods, hosts,
  published experiences, media — browsing works before signup
- **Owner only**: taste, trips, saves, dismissals, itinerary — filtered by
  `current_profile_id()` resolved from the JWT
- No function takes a profile id, so a client cannot act as another traveler

*Verified: traveler B sees **0** of traveler A's saves, trips and itinerary,
while both see all 26 catalogue rows, and signed-out browsing still works.*

## 17. Seeded content

36 experiences · 13 categories · 19 neighbourhoods · 25 hosts · 14 interests ·
10 countries · 3 cities (Tokyo, Kyoto, Osaka)

Ten of the 36 exist because there is **real short-form video** of them —
`content/video-catalog.md` catalogues 39 clips the team pulled from TikTok and
Instagram, and `content/clip-map.tsv` triages every one. Fifteen are elsewhere
in Japan, two are in Brooklyn, ten have no identifiable venue; the map says so
per clip rather than quietly using a third and implying it used all of them.

That pass closed two real holes. **Kyoto had zero nightlife rows** — not thin,
zero — so a Kyoto leg left every evening empty. And **Osaka's lowest locality
was 0.55**, meaning "hidden local gems" in Osaka ranked against nothing;
Umeda Sky Building now sits at 0.15 on purpose.

Weighted toward locally-organised and time-sensitive things, with a few
well-known attractions included deliberately — without them the locality score
has nothing to rank against and "hidden gems" means nothing.

---

## Migrating the frontend onto this

### Step 0 — build with no backend at all (today)

```bash
cp engine/docs/roam-client.ts engine/docs/fixtures.ts src/lib/
echo "NEXT_PUBLIC_ROAM_FIXTURES=1" >> .env.local
npm run dev
```

Every read returns a **real recorded payload** dumped from the seeded database.
Build and review every screen before Supabase exists.

### Step 1 — stand up Supabase (~10 min, one person)

1. Create a project
2. **Authentication → Providers → Anonymous: ON** (the single most common miss)
3. Run the migrations in order, then the seed:

```bash
for f in supabase/migrations/*.sql supabase/seed.sql; do
  psql "$SUPABASE_DB_URL" -f "$f"
done
```

4. Put the URL and anon key in `.env.local`

### Step 2 — flip the flag

```bash
# delete this line
NEXT_PUBLIC_ROAM_FIXTURES=1
```

That is the migration. Components never learn whether data is live, because
every call goes through the same typed wrapper.

### Step 3 — wire screens in this order

| Screen | Calls |
|---|---|
| Welcome | `signUp()` / `continueAsGuest()` |
| Picker | `getPickerCards()` → `completeOnboarding(ids)` |
| Feed | `getFeed()` → `saveExperience` / `dismissExperience` |
| Detail | `getExperience(id)` → `addToItinerary` |
| Explore | `explore(filters)` + `getExploreSections()` |
| Saved | `getSaved()` |
| Trip setup | `getTripOptions()` → `createTrip()` |
| Itinerary | `getItinerary()` → `updateItineraryEntry` |
| Profile | `getMyProfile()` + `my_taste()` |

### Five things that will save the frontend team a day

1. **Build one card component.** `ExperienceCard` is identical from `feed()` and
   `explore()`. Bind Figma output to that type from the first commit.
2. **Route on `session_state().next_screen`**, don't infer account state from
   three fields — that's where clients get the edges wrong.
3. **Render `reasons[0]`** on every card. The explanation is the product.
4. **Handle `media_source_url === null`.** `isPlaceholder(card)` tells you. Design
   the placeholder well and the demo looks intentional.
5. **`no trip yet` is not an error to swallow** — it's the cue to open trip creation.

### What the frontend never has to do

Permissions · ranking · deduping the swipe deck (decided cards don't come back) ·
grouping the itinerary by day (pre-grouped) · counting saves (denormalised) ·
picking an itinerary day (chosen and clamped server-side).
