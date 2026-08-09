# API contract

Everything the UI needs, and nothing it has to reach around. If a screen needs
something that is not here, that is a gap in the engine — please raise it rather
than querying tables directly, because RLS and the scoring pass both live behind
these functions.

**Call convention** — all of it is `supabase.rpc()`:

```ts
const { data, error } = await supabase.rpc('feed', { p_limit: 20, p_offset: 0 })
```

**Auth** — sign in anonymously once on first load. A profile is minted by
trigger, so there is nothing else to set up:

```ts
const { data: { session } } = await supabase.auth.getSession()
if (!session) await supabase.auth.signInAnonymously()
```

No function takes a profile id. The caller is always resolved server-side from
the JWT, so a client cannot act as another traveler.

---

## Types

```ts
export type BudgetLevel = 'shoestring' | 'moderate' | 'comfortable' | 'splurge'
export type TravelStyle = 'solo' | 'couple' | 'family' | 'group'
export type MediaKind   = 'tiktok' | 'instagram' | 'youtube' | 'hosted_video' | 'image' | 'placeholder'
export type MediaLicense= 'oembed' | 'owned' | 'stock' | 'placeholder'

/** The card. Identical shape from feed(), explore(), and search — build one component. */
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
  recurrence_note: string | null  // "Daily except Sunday"
  is_free: boolean
  price_yen: number
  price_note: string | null
  lat: number
  lng: number
  host_name: string | null
  host_verified: boolean
  host_is_local: boolean
  media_kind: MediaKind | null
  media_source_url: string | null       // canonical post URL → resolve via oEmbed
  media_thumbnail_url: string | null
  media_attribution_name: string | null
  media_attribution_url: string | null
  media_license: MediaLicense | null
  save_count: number
  share_count: number
  is_saved: boolean
  in_itinerary: boolean
  score: number
  reasons: string[]               // ordered; reasons[0] is the one to show
}

export interface ItineraryDay {
  day: string                     // 'YYYY-MM-DD'
  stop_count: number
  total_price_yen: number
  stops: ItineraryStop[]          // already ordered
}

export interface ItineraryStop {
  entry_id: string
  experience_id: string
  position: number
  planned_start: string | null    // 'HH:MM:SS'
  planned_end: string | null
  note: string | null
  name: string
  category: string
  city: string
  neighborhood: string | null
  venue_name: string | null
  address: string | null
  lat: number
  lng: number
  starts_at: string | null
  duration_min: number | null
  is_free: boolean
  price_yen: number
  booking_url: string | null
  stay22_url: string | null
  thumbnail_url: string | null
  host_name: string | null
}
```

---

## Onboarding & profile

| Function | Args | Returns |
|---|---|---|
| `onboarding_options()` | — | `{ interests[], cities[] (each with neighborhoods[]), budgets[], styles[] }` |
| `save_onboarding(...)` | `p_interests text[]`, `p_destinations text[]`, `p_neighborhoods text[]`, `p_trip_start date`, `p_trip_end date`, `p_budget`, `p_style` | the preferences row |
| `my_profile()` | — | identity + preferences + `saved_count` / `itinerary_count` |
| `update_profile(...)` | `p_display_name`, `p_avatar_url`, `p_about` | the profile row |

`onboarding_options()` powers the entire onboarding screen in one request —
render the interest chips and city pickers from it rather than hardcoding, or
the list will drift from what scoring actually understands.

`p_about` is the free-text box on the profile screen. It is not decorative: the
scoring pass matches it against tags and emits *"Matches what you wrote on your
profile"*.

---

## Feed & discovery

| Function | Args | Returns |
|---|---|---|
| `feed(p_limit, p_offset)` | default 20 / 0 | `ExperienceCard[]`, ranked |
| `explore(...)` | see below, all optional | `ExperienceCard[]` |
| `explore_sections(p_city, p_limit)` | both optional | `{ happening_this_week[], hidden_local_gems[], popular_near_you[] }` |
| `experience_detail(p_experience_id)` | uuid | full detail document |

`explore` arguments: `p_query`, `p_categories text[]`, `p_city` (slug),
`p_neighborhood` (slug), `p_from date`, `p_to date`, `p_free_only bool`,
`p_max_price int`, `p_sort` (`recommended` \| `soonest` \| `price` \| `popular`),
`p_limit`, `p_offset`.

Two behaviours worth knowing:

- **`feed()` excludes what you have already saved or dismissed.** It is the
  swipe deck, so a card you have decided on does not come back. Use `explore()`
  when you want everything regardless of state.
- **Date filters never hide always-on attractions.** An experience with
  `starts_at = null` passes any date range, because filtering to "this week"
  should not remove teamLab from the results.

`experience_detail()` returns one document containing the card, **all** media,
the host, `reasons`, and six related experiences — so the detail page never
needs a second round trip.

---

## Actions

| Function | Args | Returns |
|---|---|---|
| `save_experience(p_experience_id)` | uuid | `{ experience_id, is_saved, save_count }` |
| `unsave_experience(p_experience_id)` | uuid | `{ experience_id, is_saved, save_count }` |
| `dismiss_experience(p_experience_id)` | uuid | `{ experience_id, dismissed }` |
| `undo_dismiss(p_experience_id)` | uuid | `{ experience_id, dismissed }` |
| `share_experience(p_experience_id, p_channel)` | uuid, text | `{ experience_id, share_count }` |
| `my_saved()` | — | saved rows, newest first |
| `add_to_itinerary(p_experience_id, p_day, p_planned_start)` | day/time optional | `{ entry_id, experience_id, day, in_itinerary }` |
| `update_itinerary_entry(...)` | `p_day`, `p_planned_start`, `p_planned_end`, `p_position`, `p_note` | the entry |
| `remove_from_itinerary(p_experience_id)` | uuid | `{ experience_id, in_itinerary }` |
| `my_itinerary()` | — | `ItineraryDay[]`, grouped and ordered |

All of these are safe to call twice — a double-tap will not error.

Three implicit behaviours the UI can rely on rather than reimplement:

- **Saving clears a dismissal**, and **dismissing clears a save**. The last
  gesture wins.
- **Adding to the itinerary also saves**, and clears any dismissal. Committing
  to something is a stronger signal than a swipe.
- **`add_to_itinerary` picks a sensible day** when you do not pass one: the
  event's own date, else the traveler's `trip_start`, else today.

Counts returned by save/share are the **new** value, so the UI can update
optimistically and reconcile from the response.

---

## Media: how to render it, and the one hard rule

`experience_media` stores **pointers and attribution only**. No video file is
ever copied or rehosted — that would be a ToS and copyright problem, and the
schema has no column for it.

```ts
switch (card.media_kind) {
  case 'tiktok':
    // Public, keyless.
    // https://www.tiktok.com/oembed?url=<encoded source_url>
  case 'instagram':
    // Keyless since June 2026 (App Review no longer required).
    // https://graph.facebook.com/v20.0/instagram_oembed?url=<encoded source_url>
  case 'hosted_video':
  case 'image':
    // Ours or licensed — render src directly.
  case 'placeholder':
  default:
    // Render the branded placeholder using `short_description` as alt text.
}
```

**Always render `media_attribution_name` and link `media_attribution_url`** when
`media_license === 'oembed'`. That is the condition on which embedding is
permitted.

Everything is currently seeded as `placeholder`, so the app looks finished with
zero API keys. Swapping in a real post is a data change, not a code change: set
`kind`, `source_url`, and the attribution fields.

---

## Error handling

Functions raise on genuine problems; `error.message` is safe to surface in dev.

| Message | Cause |
|---|---|
| `not signed in` | No anonymous session — call `signInAnonymously()` |
| `itinerary entry not found` | Removed in another tab |

Reads return empty arrays rather than raising, so empty states are the normal
path, not an error path.

---

## Local setup

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/0001_schema.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0002_scoring.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0003_actions.sql
psql "$SUPABASE_DB_URL" -f supabase/migrations/0004_rls.sql
psql "$SUPABASE_DB_URL" -f supabase/seed.sql
```

Then enable **Authentication → Providers → Anonymous** in the Supabase
dashboard. That is the whole setup.
