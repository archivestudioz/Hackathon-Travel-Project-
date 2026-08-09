# API contract

Everything the UI needs, and nothing it has to reach around. If a screen needs
something that is not here, please raise it rather than querying tables
directly — RLS and the scoring pass both live behind these functions.

**Call convention** — all of it is `supabase.rpc()`:

```ts
const { data, error } = await supabase.rpc('feed', { p_limit: 20 })
```

**Auth** — sign in anonymously once on load. A profile and an empty taste row
are created by trigger, so there is nothing else to set up:

```ts
const { data: { session } } = await supabase.auth.getSession()
if (!session) await supabase.auth.signInAnonymously()
```

No function takes a profile id. The caller is resolved server-side from the JWT,
so a client cannot act as another traveler.

---

## The two stages

The product asks broad questions once, and specific questions only when someone
decides to plan. The schema mirrors that, and it is the single most important
thing to understand before building screens:

| | **Stage 1 — Profile** | **Stage 2 — Trip** |
|---|---|---|
| When | Signup | "Create an itinerary" |
| Scope | Evergreen, one per person | One per journey, many allowed |
| Asks | Countries you travel to · why you travel · interests | Exact city · dates & duration · neighbourhood you're staying in · party · budget · pace |
| Table | `traveler_profiles` | `trips` |

**The feed works in both states.** With no trip it is an *inspiration* feed
driven by interests, countries, and reasons — nothing is penalised for being in
the wrong city or over budget, because the traveler has not said where they are
going. Create a trip and the same feed becomes a *planning* feed: city,
neighbourhood, dates, and budget all start counting, and a wrong city is now
actively penalised.

Saves and dismissals live on the **profile**, not a trip. Someone can save a
Kyoto workshop eighteen months before booking; `trip_suggestions()` then offers
those saves back when they plan a Kyoto trip. That bridge is the reason the two
tables are separate.

---

## Types

```ts
export type BudgetLevel = 'shoestring' | 'moderate' | 'comfortable' | 'splurge'
export type TravelStyle = 'solo' | 'couple' | 'family' | 'group'
export type TripPace    = 'relaxed' | 'balanced' | 'packed'
export type TripStatus  = 'planning' | 'active' | 'past'
export type MediaKind   = 'tiktok' | 'instagram' | 'youtube' | 'hosted_video' | 'image' | 'placeholder'
export type MediaLicense= 'oembed' | 'owned' | 'stock' | 'placeholder'

/** Identical shape from feed() and explore() — build one card component. */
export interface ExperienceCard {
  experience_id: string
  name: string
  short_description: string
  category: string
  tags: string[]
  city: string
  neighborhood: string | null
  venue_name: string | null
  starts_at: string | null        // ISO; null = always-available attraction
  duration_min: number | null
  recurrence_note: string | null
  is_free: boolean
  price_yen: number
  price_note: string | null
  lat: number
  lng: number
  host_name: string | null
  host_verified: boolean
  host_is_local: boolean
  media_kind: MediaKind | null
  media_source_url: string | null   // canonical post URL → resolve via oEmbed
  media_thumbnail_url: string | null
  media_attribution_name: string | null
  media_attribution_url: string | null
  media_license: MediaLicense | null
  save_count: number
  share_count: number
  is_saved: boolean
  in_itinerary: boolean
  score: number
  reasons: string[]                 // ordered; reasons[0] is the one to show
}

export interface Trip {
  trip_id: string
  name: string | null
  city: string
  city_slug: string
  neighborhood: string | null
  country: string
  start_date: string | null
  end_date: string | null
  duration_days: number | null      // derived from the dates
  party: TravelStyle
  budget: BudgetLevel
  pace: TripPace
  status: TripStatus
  stop_count: number
  is_current: boolean
}

export interface ItineraryDay {
  day: string                       // 'YYYY-MM-DD'
  stop_count: number
  total_price_yen: number
  stops: ItineraryStop[]            // already ordered
}
```

---

## Stage 1 — onboarding, one screen

Onboarding is **one screen and three taps**. Not a form — a grid of real
experience cards with "tap three that look good". Tapping art feels like play;
a checklist feels like admin, and admin is where casual users leave.

The taps also carry far more signal than checkboxes would: choosing three cards
reveals category, price tolerance, and how touristy someone likes things, all at
once. Interests are **derived from the taps, never asked for**.

| Function | Args | Returns |
|---|---|---|
| `cold_start_picks(p_country?, p_limit?)` | default `'JP'`, `12` | 12 diverse cards — one per category, spread across the locality range |
| `complete_cold_start(p_experience_ids[], p_countries?)` | uuid[] | `{ onboarded, saved, derived_interests, countries }` |
| `my_profile()` | — | identity, taste, counts, `active_trip` |
| `update_profile(...)` | `p_display_name`, `p_avatar_url`, `p_about`, `p_age_band` | the profile row |
| `my_taste()` | — | `{ confidence, declared[], learned[] }` |

```ts
const { data: picks } = await supabase.rpc('cold_start_picks', { p_country: 'JP' })
// render picks as a 3×4 grid of images; require 3 taps
await supabase.rpc('complete_cold_start', { p_experience_ids: chosen })
// → straight to the feed. Saved tab already has 3 things in it.
```

**The taps become real saves**, so the traveler never lands on an empty Saved
tab. That is deliberate — the first screen after signup should never be blank.

### What the algorithm does instead of asking

`interest_affinity()` scores every interest from behaviour, weighted by what
each action costs the traveler:

| Signal | Weight |
|---|---|
| Added to an itinerary | **+1.5** — they committed |
| Saved / tapped at cold start | +1.0 |
| Dismissed | −0.75 |

`learned_confidence()` ramps 0 → 1 across roughly twenty interactions. Scoring
blends the two: declared taste carries a brand-new account, learned taste takes
over as evidence accumulates. Card explanations follow — once confidence passes
0.3 the reason changes from *"Because you like restaurants"* to
**"More like the food you keep saving"**, which is both truer and more
persuasive.

Verified: after three taps plus four swipes, the engine had independently
learned `food +5.0 · nightlife +3.0 · traditional +2.0 · art −1.5` and re-ranked
the feed accordingly — with **nothing asked beyond the three taps**.

### Age

`p_age_band` on `update_profile` takes `under_18 · 18_24 · 25_34 · 35_44 ·
45_54 · 55_plus · undisclosed`. A band rather than a birthday: it never goes
stale, it is far less regulated personal data, and it does the one job age
genuinely needs to do here — `under_18` **hard-filters** bars, nightclubs, and
anything tagged `alcohol` out of the feed entirely. Not ranked lower; absent.

`undisclosed` is treated as an adult, so declining to answer never silently
degrades the product.

### Guest mode — skip even the taps

Every account is already anonymous, so there is no signup to skip. Guest mode
skips the *three taps*.

| Function | Args | Returns |
|---|---|---|
| `continue_as_guest()` | — | `{ guest: true, onboarded: true }` |
| `claim_guest_profile(p_display_name?)` | text | the profile row — call when a guest first saves or names themselves |

The feed handles zero signal by **exploring**. `exploration_weight()` runs 1.0 →
0.0 as confidence rises, and while it is high the deck round-robins across
categories rather than ordering purely by score. A cold feed sorted by score
alone returns five variations on one category, which is both boring and the
slowest possible way to learn anything — interleaving reads as variety *and*
makes every swipe discriminate between categories instead of within one.

Verified: a guest's first eight cards covered eight distinct categories; after
eight swipes exploration had decayed and the deck had converged on the two
categories they actually picked.

### Optional: declared interests

`save_profile_onboarding(p_interests[], p_countries[], p_reasons[])` still
exists for the minority who want to curate their own taste from the profile
screen. It is no longer the primary path and should not appear during signup.

## Stage 2 — trips

| Function | Args | Returns |
|---|---|---|
| `trip_options(p_country_code)` | default `'JP'` | cities (with neighbourhoods + `experience_count`), budgets, parties, paces |
| `create_trip(...)` | see below | the trip row |
| `update_trip(p_trip_id, …)` | any field | the trip row |
| `delete_trip(p_trip_id)` | uuid | `{ trip_id, deleted }` |
| `my_trips()` | — | `Trip[]` |
| `trip_suggestions(p_trip_id?)` | uuid, optional | saved items in this trip's city, not yet scheduled |

```ts
await supabase.rpc('create_trip', {
  p_city_slug: 'osaka',
  p_start_date: '2026-09-14',
  p_duration_days: 4,            // or pass p_end_date; either works
  p_neighborhood_slug: 'tenma',  // where they're staying
  p_party: 'group',
  p_budget: 'shoestring',
  p_pace: 'packed',
})
```

Travelers think in *how long*, not *which day I fly home*, so `create_trip`
accepts `p_duration_days` **or** `p_end_date` and derives the other.

Every function that takes `p_trip_id` treats it as optional and falls back to
the traveler's current trip (active first, then the soonest one being planned).
The UI only needs to pass it explicitly when the traveler is looking at a trip
that isn't their current one.

---

## Feed & discovery

| Function | Args | Returns |
|---|---|---|
| `feed(p_trip_id?, p_limit, p_offset)` | defaults `null, 20, 0` | `ExperienceCard[]`, ranked |
| `explore(...)` | all optional | `ExperienceCard[]` |
| `explore_sections(p_city?, p_limit)` | | `{ happening_this_week[], hidden_local_gems[], popular_near_you[] }` |
| `experience_detail(p_experience_id)` | uuid | full detail document |

`explore` arguments: `p_query`, `p_categories text[]`, `p_city` (slug),
`p_neighborhood` (slug), `p_from date`, `p_to date`, `p_free_only bool`,
`p_max_price int`, `p_sort` (`recommended` \| `soonest` \| `price` \| `popular`),
`p_limit`, `p_offset`.

Two behaviours worth knowing:

- **`feed()` excludes what you've already saved or dismissed.** It's the swipe
  deck, so a decided card doesn't come back. Use `explore()` for everything.
- **Date filters never hide always-on attractions.** `starts_at = null` passes
  any range — filtering to "this week" shouldn't remove teamLab.

`experience_detail()` returns the card, **all** media, the host, `reasons`, and
six related experiences, so the detail page never needs a second round trip.

---

## Actions

| Function | Args | Returns |
|---|---|---|
| `save_experience(id)` | uuid | `{ experience_id, is_saved, save_count }` |
| `unsave_experience(id)` | uuid | same |
| `dismiss_experience(id)` | uuid | `{ experience_id, dismissed }` |
| `undo_dismiss(id)` | uuid | same |
| `share_experience(id, p_channel?)` | uuid, text | `{ experience_id, share_count }` |
| `my_saved()` | — | saved rows, newest first |
| `add_to_itinerary(id, p_trip_id?, p_day?, p_planned_start?)` | | `{ entry_id, trip_id, day, in_itinerary }` |
| `update_itinerary_entry(p_entry_id, …)` | day/time/position/note | the entry |
| `remove_from_itinerary(id, p_trip_id?)` | | `{ experience_id, in_itinerary }` |
| `my_itinerary(p_trip_id?)` | | `{ trip, days: ItineraryDay[] }` |

All are safe to call twice — a double-tap won't error.

Behaviours the UI can rely on rather than reimplement:

- **Saving clears a dismissal; dismissing clears a save.** Last gesture wins.
- **Adding to the itinerary also saves, and clears any dismissal.**
- **`add_to_itinerary` picks the day**: the event's own date, else the trip's
  first day, else today — then **clamps it inside the trip window**, so you
  can't create a stop on a date the traveler isn't there.
- Save and share return the **new** count, so you can update optimistically and
  reconcile from the response.

`add_to_itinerary` raises **`no trip yet`** when the traveler has none. That is
not a failure case to hide — it's the cue to open the Stage 2 questions, which
is exactly where trip creation belongs in the flow.

---

## Media: how to render it, and the one hard rule

`experience_media` stores **pointers and attribution only**. No video is ever
copied or rehosted — the schema has no column for it.

```ts
switch (card.media_kind) {
  case 'tiktok':
    // Public, keyless: https://www.tiktok.com/oembed?url=<encoded source_url>
  case 'instagram':
    // Keyless since June 2026 (App Review no longer required):
    // https://graph.facebook.com/v20.0/instagram_oembed?url=<encoded source_url>
  case 'hosted_video':
  case 'image':
    // Ours or licensed — render directly.
  case 'placeholder':
  default:
    // Branded placeholder; use `short_description` as alt text.
}
```

**Always render `media_attribution_name` and link `media_attribution_url`** when
`media_license === 'oembed'`. That's the condition on which embedding is
permitted.

Everything is currently seeded as `placeholder`, so the app looks finished with
zero API keys. Swapping in a real post is a data change, not a code change.

---

## Errors

| Message | Cause |
|---|---|
| `not signed in` | No anonymous session — call `signInAnonymously()` |
| `no trip yet` | Scheduling before Stage 2 — prompt trip creation |
| `unknown city <slug>` | Bad slug; use one from `trip_options()` |
| `trip not found` / `itinerary entry not found` | Deleted in another tab |

Reads return empty arrays rather than raising, so empty states are the normal
path, not an error path.

---

## Setup

```bash
for f in supabase/migrations/*.sql supabase/seed.sql; do
  psql "$SUPABASE_DB_URL" -f "$f"
done
```

Then enable **Authentication → Providers → Anonymous** in the Supabase
dashboard. That's the whole setup.
