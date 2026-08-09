"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type {
  AppState,
  Experience,
  ItineraryEntry,
  ScoredExperience,
  TravelerProfile,
} from "@/lib/types";
import { emptyState, localRepository, type Repository } from "@/lib/storage";
import { EXPERIENCES, EXPERIENCE_BY_ID } from "@/lib/data/experiences";
import { buildDeck, rankExperiences, type ScoreContext } from "@/lib/scoring";
import { buildItinerary, groupByDay, makeEntry, type ItineraryDay } from "@/lib/itinerary";

/**
 * Single source of truth for demo state.
 *
 * Swap `repository` for a Supabase-backed implementation of the same
 * interface and every screen keeps working unchanged.
 */
const repository: Repository = localRepository;

export type UndoableAction =
  | { kind: "save"; experienceId: string }
  | { kind: "dismiss"; experienceId: string }
  | { kind: "schedule"; entryId: string; experienceId: string };

interface AppStoreValue {
  /** False until localStorage has been read; screens render skeletons meanwhile. */
  hydrated: boolean;
  state: AppState;
  profile: TravelerProfile;

  /* Derived */
  deck: ScoredExperience[];
  ranked: ScoredExperience[];
  savedExperiences: ScoredExperience[];
  itineraryDays: ItineraryDay[];
  scoreContext: ScoreContext;
  isSaved: (id: string) => boolean;
  isScheduled: (id: string) => boolean;
  scoreFor: (id: string) => ScoredExperience | undefined;

  /* Profile */
  completeOnboarding: (profile: TravelerProfile) => void;
  updateProfile: (patch: Partial<TravelerProfile>) => void;

  /* Activity */
  save: (id: string) => void;
  unsave: (id: string) => void;
  dismiss: (id: string) => void;
  restore: (id: string) => void;
  addToItinerary: (id: string, date: string, time: string, note?: string) => string;
  updateEntry: (entryId: string, patch: Partial<ItineraryEntry>) => void;
  removeEntry: (entryId: string) => void;
  generateItinerary: () => { placed: number; days: number; unplaced: string[] };

  /* Undo */
  lastAction: UndoableAction | null;
  undo: () => void;
  clearLastAction: () => void;

  /* Demo tooling */
  reset: () => void;
}

const AppStoreContext = createContext<AppStoreValue | null>(null);

export function AppStoreProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<AppState>(() => emptyState());
  const [hydrated, setHydrated] = useState(false);
  const [lastAction, setLastAction] = useState<UndoableAction | null>(null);
  const skipPersist = useRef(true);

  /* Read persisted state once on mount. */
  useEffect(() => {
    const loaded = repository.load();
    if (loaded) setState(loaded);
    setHydrated(true);
  }, []);

  /* Write on every change after hydration. */
  useEffect(() => {
    if (!hydrated) return;
    if (skipPersist.current) {
      skipPersist.current = false;
      return;
    }
    repository.save(state);
  }, [state, hydrated]);

  const profile = state.profile;

  const scoreContext = useMemo<ScoreContext>(
    () => ({ profile, saved: state.saved, dismissed: state.dismissed }),
    [profile, state.saved, state.dismissed],
  );

  const ranked = useMemo(
    () => rankExperiences(EXPERIENCES, scoreContext),
    [scoreContext],
  );

  const deck = useMemo(() => buildDeck(EXPERIENCES, scoreContext), [scoreContext]);

  const scoreIndex = useMemo(() => {
    const map = new Map<string, ScoredExperience>();
    for (const s of ranked) map.set(s.experience.id, s);
    return map;
  }, [ranked]);

  const scheduledIds = useMemo(
    () => new Set(state.itinerary.map((e) => e.experienceId)),
    [state.itinerary],
  );

  const savedExperiences = useMemo(() => {
    return [...state.saved]
      .sort((a, b) => b.savedAt - a.savedAt)
      .map((s) => scoreIndex.get(s.experienceId))
      .filter((s): s is ScoredExperience => Boolean(s));
  }, [state.saved, scoreIndex]);

  const itineraryDays = useMemo(() => groupByDay(state.itinerary), [state.itinerary]);

  /* ---------------------------------------------------------------- */
  /* Actions                                                           */
  /* ---------------------------------------------------------------- */

  const completeOnboarding = useCallback((next: TravelerProfile) => {
    setState((s) => ({ ...s, profile: { ...next, onboardingComplete: true } }));
  }, []);

  const updateProfile = useCallback((patch: Partial<TravelerProfile>) => {
    setState((s) => ({ ...s, profile: { ...s.profile, ...patch } }));
  }, []);

  const save = useCallback((id: string) => {
    setState((s) => {
      if (s.saved.some((x) => x.experienceId === id)) return s;
      return {
        ...s,
        saved: [...s.saved, { experienceId: id, savedAt: Date.now() }],
        dismissed: s.dismissed.filter((d) => d.experienceId !== id),
      };
    });
    setLastAction({ kind: "save", experienceId: id });
  }, []);

  const unsave = useCallback((id: string) => {
    setState((s) => ({ ...s, saved: s.saved.filter((x) => x.experienceId !== id) }));
  }, []);

  const dismiss = useCallback((id: string) => {
    setState((s) => {
      if (s.dismissed.some((x) => x.experienceId === id)) return s;
      return {
        ...s,
        dismissed: [...s.dismissed, { experienceId: id, dismissedAt: Date.now() }],
        saved: s.saved.filter((x) => x.experienceId !== id),
      };
    });
    setLastAction({ kind: "dismiss", experienceId: id });
  }, []);

  const restore = useCallback((id: string) => {
    setState((s) => ({
      ...s,
      dismissed: s.dismissed.filter((x) => x.experienceId !== id),
    }));
  }, []);

  const addToItinerary = useCallback(
    (id: string, date: string, time: string, note = "") => {
      const entry = makeEntry(id, date, time, note);
      setState((s) => ({
        ...s,
        itinerary: [...s.itinerary.filter((e) => e.experienceId !== id), entry],
        /* Scheduling implies interest, so it also leaves the deck. */
        saved: s.saved.some((x) => x.experienceId === id)
          ? s.saved
          : [...s.saved, { experienceId: id, savedAt: Date.now() }],
      }));
      setLastAction({ kind: "schedule", entryId: entry.id, experienceId: id });
      return entry.id;
    },
    [],
  );

  const updateEntry = useCallback((entryId: string, patch: Partial<ItineraryEntry>) => {
    setState((s) => ({
      ...s,
      itinerary: s.itinerary.map((e) => (e.id === entryId ? { ...e, ...patch } : e)),
    }));
  }, []);

  const removeEntry = useCallback((entryId: string) => {
    setState((s) => ({ ...s, itinerary: s.itinerary.filter((e) => e.id !== entryId) }));
  }, []);

  const generateItinerary = useCallback(() => {
    let summary = { placed: 0, days: 0, unplaced: [] as string[] };
    setState((s) => {
      const savedIds = s.saved.map((x) => x.experienceId);
      const result = buildItinerary(savedIds, s.profile, []);
      summary = {
        placed: result.entries.length,
        days: new Set(result.entries.map((e) => e.date)).size,
        unplaced: result.unplaced,
      };
      return { ...s, itinerary: result.entries };
    });
    return summary;
  }, []);

  const undo = useCallback(() => {
    setState((s) => {
      if (!lastAction) return s;
      switch (lastAction.kind) {
        case "save":
          return { ...s, saved: s.saved.filter((x) => x.experienceId !== lastAction.experienceId) };
        case "dismiss":
          return {
            ...s,
            dismissed: s.dismissed.filter((x) => x.experienceId !== lastAction.experienceId),
          };
        case "schedule":
          return { ...s, itinerary: s.itinerary.filter((e) => e.id !== lastAction.entryId) };
      }
    });
    setLastAction(null);
  }, [lastAction]);

  const reset = useCallback(() => {
    repository.clear();
    skipPersist.current = true;
    setState(emptyState());
    setLastAction(null);
  }, []);

  const value = useMemo<AppStoreValue>(
    () => ({
      hydrated,
      state,
      profile,
      deck,
      ranked,
      savedExperiences,
      itineraryDays,
      scoreContext,
      isSaved: (id) => state.saved.some((x) => x.experienceId === id),
      isScheduled: (id) => scheduledIds.has(id),
      scoreFor: (id) => scoreIndex.get(id),
      completeOnboarding,
      updateProfile,
      save,
      unsave,
      dismiss,
      restore,
      addToItinerary,
      updateEntry,
      removeEntry,
      generateItinerary,
      lastAction,
      undo,
      clearLastAction: () => setLastAction(null),
      reset,
    }),
    [
      hydrated, state, profile, deck, ranked, savedExperiences, itineraryDays,
      scoreContext, scheduledIds, scoreIndex, completeOnboarding, updateProfile,
      save, unsave, dismiss, restore, addToItinerary, updateEntry, removeEntry,
      generateItinerary, lastAction, undo, reset,
    ],
  );

  return <AppStoreContext.Provider value={value}>{children}</AppStoreContext.Provider>;
}

export function useApp(): AppStoreValue {
  const ctx = useContext(AppStoreContext);
  if (!ctx) throw new Error("useApp must be used inside AppStoreProvider");
  return ctx;
}

export function useExperience(id: string | null): Experience | null {
  return id ? EXPERIENCE_BY_ID[id] ?? null : null;
}
