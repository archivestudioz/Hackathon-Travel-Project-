import type { AppState, TravelerProfile } from "@/lib/types";
import { addDays, today } from "@/lib/format";

/**
 * Persistence seam.
 *
 * The demo stores everything in localStorage so a judge can refresh without
 * losing state and without any backend running. `Repository` is the only
 * surface the app talks to — swapping in Supabase means writing a second
 * implementation of this interface and changing one line in `AppStore`.
 */

const STORAGE_KEY = "meguri.state.v1";
const STATE_VERSION = 1;

export interface Repository {
  load(): AppState | null;
  save(state: AppState): void;
  clear(): void;
}

export function emptyProfile(): TravelerProfile {
  return {
    name: "",
    avatarDataUrl: null,
    cities: [],
    dates: { start: addDays(today(), 14), end: addDays(today(), 21) },
    flexibleDates: false,
    interests: [],
    style: "solo",
    budget: "mid",
    freeOnly: false,
    description: "",
    onboardingComplete: false,
  };
}

/** Pre-filled traveller used by the "I already have a trip" shortcut. */
export function demoProfile(): TravelerProfile {
  return {
    name: "Alex Rivera",
    avatarDataUrl: null,
    cities: ["tokyo", "kyoto", "osaka"],
    dates: { start: addDays(today(), 3), end: addDays(today(), 17) },
    flexibleDates: false,
    interests: ["food", "nightlife", "music", "traditional", "art"],
    style: "couple",
    budget: "mid",
    freeOnly: false,
    description:
      "I love tiny jazz bars, street food and vintage shops, and I'd rather avoid crowds where I can.",
    onboardingComplete: true,
  };
}

export function emptyState(): AppState {
  return {
    version: STATE_VERSION,
    profile: emptyProfile(),
    saved: [],
    dismissed: [],
    itinerary: [],
  };
}

/** localStorage-backed repository. Safe to construct during SSR. */
export const localRepository: Repository = {
  load() {
    if (typeof window === "undefined") return null;
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as AppState;
      if (parsed.version !== STATE_VERSION) return null;
      /* Defensive merge so a partially-written state can't crash the app. */
      return {
        ...emptyState(),
        ...parsed,
        profile: { ...emptyProfile(), ...parsed.profile },
        saved: parsed.saved ?? [],
        dismissed: parsed.dismissed ?? [],
        itinerary: parsed.itinerary ?? [],
      };
    } catch {
      return null;
    }
  },
  save(state) {
    if (typeof window === "undefined") return;
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch {
      /* Quota or private-mode failure: the session still works in memory. */
    }
  },
  clear() {
    if (typeof window === "undefined") return;
    try {
      window.localStorage.removeItem(STORAGE_KEY);
    } catch {
      /* no-op */
    }
  },
};
