/**
 * Roam engine — drop-in typed client.
 *
 * Copy this one file into the Next.js app. It is the entire integration: every
 * screen in the product maps to a function here, and nothing else needs to know
 * the database exists.
 *
 *   npm i @supabase/supabase-js
 *
 *   NEXT_PUBLIC_SUPABASE_URL=...
 *   NEXT_PUBLIC_SUPABASE_ANON_KEY=...
 *
 * The anon key is safe in the browser. It identifies the project, not the user
 * — Row Level Security decides what any given caller can see, and it is
 * enforced inside Postgres rather than by this file. There is no way for a
 * client to read another traveler's saves, trips, or itinerary.
 */

import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export const supabase: SupabaseClient = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  { auth: { persistSession: true, autoRefreshToken: true } },
)

/* ── types ────────────────────────────────────────────────────────────── */

export type AgeBand = 'under_18' | '18_24' | '25_34' | '35_44' | '45_54' | '55_plus' | 'undisclosed'
export type BudgetLevel = 'shoestring' | 'moderate' | 'comfortable' | 'splurge'
export type TravelStyle = 'solo' | 'couple' | 'family' | 'group'
export type TripPace = 'relaxed' | 'balanced' | 'packed'
export type TripStatus = 'planning' | 'active' | 'past'
export type MediaKind = 'tiktok' | 'instagram' | 'youtube' | 'hosted_video' | 'image' | 'placeholder'
export type MediaLicense = 'oembed' | 'owned' | 'stock' | 'placeholder'
export type NextScreen = 'welcome' | 'picker' | 'feed'

/** Identical from feed() and explore(). Build ONE card component. */
export interface ExperienceCard {
  experience_id: string
  name: string
  short_description: string
  category: string
  tags: string[]
  city: string
  neighborhood: string | null
  venue_name: string | null
  starts_at: string | null      // null = always-available attraction
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
  media_source_url: string | null
  media_thumbnail_url: string | null
  media_attribution_name: string | null
  media_attribution_url: string | null
  media_license: MediaLicense | null
  save_count: number
  share_count: number
  is_saved: boolean
  in_itinerary: boolean
  score: number
  reasons: string[]             // reasons[0] is the line to render
}

export interface SessionState {
  signed_in: boolean
  profile_id: string | null
  display_name: string
  is_guest: boolean
  onboarded: boolean
  next_screen: NextScreen
  saved_count: number
  trip_count: number
  confidence: number            // 0–1, how much the engine has learned
  prompt_signup: boolean        // true once a guest has ≥3 saves
}

export interface PickerCard {
  experience_id: string
  name: string
  short_description: string
  category: string
  city: string
  neighborhood: string | null
  is_free: boolean
  price_yen: number
  locality: number
  thumbnail_url: string | null
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
  duration_days: number | null
  party: TravelStyle
  budget: BudgetLevel
  pace: TripPace
  status: TripStatus
  stop_count: number
  is_current: boolean
}

export interface ItineraryStop {
  entry_id: string
  experience_id: string
  position: number
  planned_start: string | null
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

export interface ItineraryDay {
  day: string
  stop_count: number
  total_price_yen: number
  stops: ItineraryStop[]
}

export interface ExploreFilters {
  query?: string
  categories?: string[]
  city?: string
  neighborhood?: string
  from?: string
  to?: string
  freeOnly?: boolean
  maxPrice?: number
  sort?: 'recommended' | 'soonest' | 'price' | 'popular'
  limit?: number
  offset?: number
}

/* ── internals ────────────────────────────────────────────────────────── */

async function call<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(`${fn}: ${error.message}`)
  return data as T
}

/* ── auth ─────────────────────────────────────────────────────────────── */

/** Welcome screen, primary action. */
export const signUp = (email: string, password: string) =>
  supabase.auth.signUp({ email, password })

export const signIn = (email: string, password: string) =>
  supabase.auth.signInWithPassword({ email, password })

/** Welcome screen, small link at the bottom. */
export async function continueAsGuest() {
  const { error } = await supabase.auth.signInAnonymously()
  if (error) throw new Error(`guest sign-in: ${error.message}`)
  return call<{ guest: true; onboarded: true }>('continue_as_guest')
}

/**
 * Guest → real account, IN PLACE. Same auth id, same profile row, so every
 * save, dismissal, trip and itinerary survives. A trigger clears `is_guest`;
 * you do not have to tell the database.
 */
export async function upgradeGuest(email: string, password: string) {
  const { error } = await supabase.auth.updateUser({ email, password })
  if (error) throw new Error(`upgrade: ${error.message}`)
}

/** Promote a guest once they name themselves. Also happens automatically on upgrade. */
export const claimGuestProfile = (displayName?: string) =>
  call<any>('claim_guest_profile', { p_display_name: displayName ?? null })

/** Optional: let a curator set their own interests from the profile screen. */
export const setDeclaredInterests = (
  interests: string[], countries: string[] = [], reasons: string[] = [],
) =>
  call<any>('save_profile_onboarding', {
    p_interests: interests, p_countries: countries, p_reasons: reasons })

export const signOut = () => supabase.auth.signOut()

/**
 * Call this on load and route from `next_screen`. Do not infer account state
 * from three separate fields — that is where clients get the edges wrong.
 */
export const getSessionState = () => call<SessionState>('session_state')

/* ── onboarding: ONE screen, three taps ───────────────────────────────── */

export const getPickerCards = (country = 'JP', limit = 12) =>
  call<PickerCard[]>('cold_start_picks', { p_country: country, p_limit: limit })

/**
 * Finishes onboarding. Interests are DERIVED from what was tapped — never
 * asked. The taps also become real saves, so the Saved tab is never empty on
 * first open.
 */
export const completeOnboarding = (experienceIds: string[], countries: string[] = []) =>
  call<{ onboarded: boolean; saved: number; derived_interests: string[]; countries: string[] }>(
    'complete_cold_start',
    { p_experience_ids: experienceIds, p_countries: countries },
  )

export const getOnboardingOptions = () => call<any>('onboarding_options')
export const getMyProfile = () => call<any>('my_profile')
export const getMyTaste = () => call<any>('my_taste')

export const updateProfile = (patch: {
  displayName?: string
  avatarUrl?: string
  about?: string
  ageBand?: AgeBand
}) =>
  call<any>('update_profile', {
    p_display_name: patch.displayName ?? null,
    p_avatar_url: patch.avatarUrl ?? null,
    p_about: patch.about ?? null,
    p_age_band: patch.ageBand ?? null,
  })

/* ── feed & discovery ─────────────────────────────────────────────────── */

/**
 * The swipe deck. Already-decided cards do not come back.
 * Pass no trip and the engine uses whichever trip is being planned, falling
 * back to an inspiration feed when there is none.
 */
export const getFeed = (opts: { tripId?: string; limit?: number; offset?: number } = {}) =>
  call<ExperienceCard[]>('feed', {
    p_trip_id: opts.tripId ?? null,
    p_limit: opts.limit ?? 20,
    p_offset: opts.offset ?? 0,
  })

export const explore = (f: ExploreFilters = {}) =>
  call<ExperienceCard[]>('explore', {
    p_query: f.query ?? null,
    p_categories: f.categories ?? null,
    p_city: f.city ?? null,
    p_neighborhood: f.neighborhood ?? null,
    p_from: f.from ?? null,
    p_to: f.to ?? null,
    p_free_only: f.freeOnly ?? false,
    p_max_price: f.maxPrice ?? null,
    p_sort: f.sort ?? 'recommended',
    p_limit: f.limit ?? 40,
    p_offset: f.offset ?? 0,
  })

/** The three Explore rails, in one call. */
export const getExploreSections = (city?: string, limit = 8) =>
  call<{
    happening_this_week: any[]
    hidden_local_gems: any[]
    popular_near_you: any[]
  }>('explore_sections', { p_city: city ?? null, p_limit: limit })

/** Card + all media + host + reasons + 6 related. No second round trip. */
export const getExperience = (id: string) =>
  call<any>('experience_detail', { p_experience_id: id })

/* ── swipe actions — all idempotent, safe to double-tap ───────────────── */

export const saveExperience = (id: string) =>
  call<{ experience_id: string; is_saved: boolean; save_count: number }>(
    'save_experience', { p_experience_id: id })

export const unsaveExperience = (id: string) =>
  call<{ experience_id: string; is_saved: boolean; save_count: number }>(
    'unsave_experience', { p_experience_id: id })

export const dismissExperience = (id: string) =>
  call<{ experience_id: string; dismissed: boolean }>(
    'dismiss_experience', { p_experience_id: id })

export const undoDismiss = (id: string) =>
  call<{ experience_id: string; dismissed: boolean }>(
    'undo_dismiss', { p_experience_id: id })

export const shareExperience = (id: string, channel?: string) =>
  call<{ experience_id: string; share_count: number }>(
    'share_experience', { p_experience_id: id, p_channel: channel ?? null })

export const getSaved = () => call<any[]>('my_saved')

/* ── trips ────────────────────────────────────────────────────────────── */

export const getTripOptions = (countryCode = 'JP') =>
  call<any>('trip_options', { p_country_code: countryCode })

/** Pass a duration or an end date — the engine derives the other. */
export const createTrip = (t: {
  citySlug: string
  startDate?: string
  durationDays?: number
  endDate?: string
  neighborhoodSlug?: string
  party?: TravelStyle
  budget?: BudgetLevel
  pace?: TripPace
  name?: string
  notes?: string
}) =>
  call<any>('create_trip', {
    p_city_slug: t.citySlug,
    p_start_date: t.startDate ?? null,
    p_duration_days: t.durationDays ?? null,
    p_end_date: t.endDate ?? null,
    p_neighborhood_slug: t.neighborhoodSlug ?? null,
    p_party: t.party ?? 'solo',
    p_budget: t.budget ?? 'moderate',
    p_pace: t.pace ?? 'balanced',
    p_name: t.name ?? null,
    p_notes: t.notes ?? null,
  })

export const updateTrip = (
  tripId: string,
  patch: {
    startDate?: string
    endDate?: string
    neighborhoodSlug?: string
    party?: TravelStyle
    budget?: BudgetLevel
    pace?: TripPace
    name?: string
    notes?: string
    status?: TripStatus
  },
) =>
  call<any>('update_trip', {
    p_trip_id: tripId,
    p_start_date: patch.startDate ?? null,
    p_end_date: patch.endDate ?? null,
    p_neighborhood_slug: patch.neighborhoodSlug ?? null,
    p_party: patch.party ?? null,
    p_budget: patch.budget ?? null,
    p_pace: patch.pace ?? null,
    p_name: patch.name ?? null,
    p_notes: patch.notes ?? null,
    p_status: patch.status ?? null,
  })

export const getTrips = () => call<Trip[]>('my_trips')
export const deleteTrip = (tripId: string) => call<any>('delete_trip', { p_trip_id: tripId })

/** "You saved these in Osaka already — add them?" */
export const getTripSuggestions = (tripId?: string) =>
  call<any[]>('trip_suggestions', { p_trip_id: tripId ?? null })

/* ── itinerary ────────────────────────────────────────────────────────── */

/**
 * Also saves, clears any dismissal, and clamps the day inside the trip window.
 * Throws `no trip yet` when there is no trip — that is the cue to open the
 * trip-creation flow, not an error to swallow.
 */
export const addToItinerary = (
  experienceId: string,
  opts: { tripId?: string; day?: string; plannedStart?: string } = {},
) =>
  call<{ entry_id: string; trip_id: string; day: string; in_itinerary: boolean }>(
    'add_to_itinerary', {
      p_experience_id: experienceId,
      p_trip_id: opts.tripId ?? null,
      p_day: opts.day ?? null,
      p_planned_start: opts.plannedStart ?? null,
    })

export const removeFromItinerary = (experienceId: string, tripId?: string) =>
  call<any>('remove_from_itinerary', {
    p_experience_id: experienceId, p_trip_id: tripId ?? null })

export const updateItineraryEntry = (
  entryId: string,
  patch: { day?: string; plannedStart?: string; plannedEnd?: string; position?: number; note?: string },
) =>
  call<any>('update_itinerary_entry', {
    p_entry_id: entryId,
    p_day: patch.day ?? null,
    p_planned_start: patch.plannedStart ?? null,
    p_planned_end: patch.plannedEnd ?? null,
    p_position: patch.position ?? null,
    p_note: patch.note ?? null,
  })

/** Days in order, stops in order. Render as a timeline; no regrouping needed. */
export const getItinerary = (tripId?: string) =>
  call<{ trip: any; days: ItineraryDay[] }>('my_itinerary', { p_trip_id: tripId ?? null })

/* ── media ────────────────────────────────────────────────────────────── */

/**
 * Resolve an embed URL for a card.
 *
 * `media_source_url` is a POINTER to a post that lives on TikTok or Instagram.
 * Nothing is ever downloaded or rehosted — that would be a ToS and copyright
 * problem, and the schema has no column for it. Both oEmbed endpoints are
 * keyless as of 2026.
 *
 * When `media_license === 'oembed'` you MUST render `media_attribution_name`
 * and link `media_attribution_url`. That is the condition on which embedding is
 * permitted, not a nicety.
 */
export function oEmbedUrl(card: Pick<ExperienceCard, 'media_kind' | 'media_source_url'>) {
  if (!card.media_source_url) return null
  const url = encodeURIComponent(card.media_source_url)
  switch (card.media_kind) {
    case 'tiktok':    return `https://www.tiktok.com/oembed?url=${url}`
    case 'instagram': return `https://graph.facebook.com/v20.0/instagram_oembed?url=${url}`
    default:          return null
  }
}

/** Everything is seeded as `placeholder`, so the app looks finished with no keys. */
export const isPlaceholder = (card: Pick<ExperienceCard, 'media_kind'>) =>
  !card.media_kind || card.media_kind === 'placeholder'
