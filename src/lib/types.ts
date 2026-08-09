/**
 * Core domain types for the Japan travel discovery app.
 *
 * These are intentionally backend-agnostic. The demo persists them in
 * localStorage via `lib/storage.ts`, but the same shapes map cleanly onto
 * Supabase tables (see README "Swapping in a real backend").
 */

/* ------------------------------------------------------------------ */
/* Taxonomy                                                            */
/* ------------------------------------------------------------------ */

export const CITIES = ["tokyo", "kyoto", "osaka"] as const;
export type CityId = (typeof CITIES)[number];

export const CITY_LABELS: Record<CityId, string> = {
  tokyo: "Tokyo",
  kyoto: "Kyoto",
  osaka: "Osaka",
};

export const INTERESTS = [
  "food",
  "nightlife",
  "art",
  "anime",
  "music",
  "nature",
  "shopping",
  "festivals",
  "wellness",
  "traditional",
] as const;
export type InterestId = (typeof INTERESTS)[number];

export const INTEREST_LABELS: Record<InterestId, string> = {
  food: "Food",
  nightlife: "Nightlife",
  art: "Art",
  anime: "Anime",
  music: "Music",
  nature: "Nature",
  shopping: "Shopping",
  festivals: "Festivals",
  wellness: "Wellness",
  traditional: "Traditional",
};

export const TRAVEL_STYLES = ["solo", "couple", "family", "group"] as const;
export type TravelStyleId = (typeof TRAVEL_STYLES)[number];

export const TRAVEL_STYLE_LABELS: Record<TravelStyleId, string> = {
  solo: "Solo",
  couple: "Couple",
  family: "Family",
  group: "Group",
};

export const BUDGET_TIERS = ["budget", "mid", "splurge"] as const;
export type BudgetTierId = (typeof BUDGET_TIERS)[number];

/** Upper bound in yen for a single experience within each tier. */
export const BUDGET_CEILINGS: Record<BudgetTierId, number> = {
  budget: 3000,
  mid: 10000,
  splurge: Number.POSITIVE_INFINITY,
};

export const BUDGET_LABELS: Record<BudgetTierId, string> = {
  budget: "Budget",
  mid: "Mid-range",
  splurge: "Splurge",
};

/* ------------------------------------------------------------------ */
/* Media                                                               */
/* ------------------------------------------------------------------ */

/**
 * Media is deliberately abstracted behind a provider so the demo can render
 * marked placeholders today and swap to real Instagram/TikTok embeds or hosted
 * video later without touching any screen component.
 *
 * We never scrape or rehost third-party video. `instagram` / `tiktok` kinds
 * render an official embed iframe when a URL is supplied, and fall back to a
 * labelled placeholder when one is not.
 */
export type MediaProvider = "placeholder" | "video" | "photo" | "instagram" | "tiktok";

export interface MediaAsset {
  id: string;
  provider: MediaProvider;
  /** Direct file URL (video/photo) or canonical post URL (instagram/tiktok). */
  url?: string;
  /** Poster frame for video, if any. */
  poster?: string;
  alt: string;
  /** Shown as a small credit line on the media when present. */
  attribution?: string;
}

/* ------------------------------------------------------------------ */
/* Experiences                                                         */
/* ------------------------------------------------------------------ */

export interface Host {
  id: string;
  name: string;
  bio: string;
  verified: boolean;
  eventsHosted: number;
  followers: number;
}

/** A one-off event: a festival weekend, a concert, a pop-up opening. */
export interface OneOffSchedule {
  kind: "oneoff";
  /** Local date, YYYY-MM-DD. */
  date: string;
  /** Local time, HH:mm (24h). */
  startTime: string;
  /** Optional multi-day run, inclusive. */
  endDate?: string;
}

/** A recurring experience: a market, a restaurant, a weekly session. */
export interface RecurringSchedule {
  kind: "recurring";
  /** 0 = Sunday … 6 = Saturday. */
  daysOfWeek: number[];
  startTime: string;
}

export type Schedule = OneOffSchedule | RecurringSchedule;

export interface Experience {
  id: string;
  name: string;
  city: CityId;
  neighborhood: string;
  ward: string;
  venue: string;
  address: string;
  addressJa: string;
  lat: number;
  lng: number;
  schedule: Schedule;
  durationMins: number;
  /** 0 means free. */
  priceYen: number;
  /** One-line teaser used on deck cards. */
  shortDescription: string;
  /** Full copy used on the detail sheet. */
  description: string;
  interests: InterestId[];
  tags: string[];
  host: Host;
  media: MediaAsset[];
  saveCount: number;
  shareCount: number;
  externalUrl: string;
  accessNote: string;
  /** Low save counts + strong local character surface in "Hidden local gems". */
  localGem: boolean;
}

/** An experience resolved to a concrete date within the traveller's trip. */
export interface Occurrence {
  /** YYYY-MM-DD */
  date: string;
  /** HH:mm */
  startTime: string;
}

/* ------------------------------------------------------------------ */
/* Traveller                                                           */
/* ------------------------------------------------------------------ */

export interface DateRange {
  /** YYYY-MM-DD */
  start: string;
  /** YYYY-MM-DD */
  end: string;
}

export interface TravelerProfile {
  name: string;
  /** Data URL when the traveller picks a photo; otherwise a monogram is shown. */
  avatarDataUrl: string | null;
  cities: CityId[];
  dates: DateRange;
  flexibleDates: boolean;
  interests: InterestId[];
  style: TravelStyleId;
  budget: BudgetTierId;
  freeOnly: boolean;
  /** Free text from the voice/typing step. Re-ranks the feed. */
  description: string;
  onboardingComplete: boolean;
}

/* ------------------------------------------------------------------ */
/* User activity                                                       */
/* ------------------------------------------------------------------ */

export interface SavedItem {
  experienceId: string;
  savedAt: number;
}

export interface DismissedItem {
  experienceId: string;
  dismissedAt: number;
}

export interface ItineraryEntry {
  id: string;
  experienceId: string;
  /** YYYY-MM-DD */
  date: string;
  /** HH:mm */
  time: string;
  note: string;
  addedAt: number;
}

/* ------------------------------------------------------------------ */
/* Personalization                                                     */
/* ------------------------------------------------------------------ */

export type ReasonKind =
  | "interest"
  | "destination"
  | "dates"
  | "budget"
  | "style"
  | "affinity"
  | "keyword"
  | "gem";

export interface MatchReason {
  kind: ReasonKind;
  /** Traveller-facing copy, e.g. "Because you like street food". */
  label: string;
  points: number;
}

export interface ScoredExperience {
  experience: Experience;
  score: number;
  reasons: MatchReason[];
  /** The single strongest reason, shown as the match chip. */
  headline: string;
  /** Next occurrence inside the traveller's trip window, if any. */
  occurrence: Occurrence | null;
}

/* ------------------------------------------------------------------ */
/* Persisted demo state                                                */
/* ------------------------------------------------------------------ */

export interface AppState {
  version: number;
  profile: TravelerProfile;
  saved: SavedItem[];
  dismissed: DismissedItem[];
  itinerary: ItineraryEntry[];
}
