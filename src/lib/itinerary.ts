import type {
  CityId,
  Experience,
  ItineraryEntry,
  TravelerProfile,
} from "@/lib/types";
import { EXPERIENCE_BY_ID } from "@/lib/data/experiences";
import { addMinutes, eachDay, occurrencesWithin, toMinutes } from "@/lib/format";

/* ------------------------------------------------------------------ */
/* Travel time between two experiences                                 */
/* ------------------------------------------------------------------ */

function haversineKm(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 + Math.sin(dLng / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  return 2 * R * Math.asin(Math.sqrt(h));
}

export interface TravelLeg {
  minutes: number;
  mode: "walk" | "train";
  label: string;
}

/**
 * Rough door-to-door estimate. Walking under ~1.2km, otherwise train with a
 * fixed allowance for getting to and from platforms.
 */
export function estimateTravel(from: Experience, to: Experience): TravelLeg {
  const km = haversineKm(from, to);
  if (km < 1.2) {
    const minutes = Math.max(5, Math.round(km * 13));
    return { minutes, mode: "walk", label: `~${minutes} min walk` };
  }
  const minutes = Math.round(9 + km * 2.2);
  return { minutes, mode: "train", label: `~${minutes} min by train` };
}

/* ------------------------------------------------------------------ */
/* Conflicts                                                           */
/* ------------------------------------------------------------------ */

export interface ConflictInfo {
  entryId: string;
  conflictsWith: string[];
}

function entryWindow(entry: ItineraryEntry): [number, number] | null {
  const exp = EXPERIENCE_BY_ID[entry.experienceId];
  if (!exp) return null;
  const start = toMinutes(entry.time);
  return [start, start + exp.durationMins];
}

function overlaps(a: ItineraryEntry, b: ItineraryEntry): boolean {
  if (a.date !== b.date) return false;
  const wa = entryWindow(a);
  const wb = entryWindow(b);
  if (!wa || !wb) return false;
  return wa[0] < wb[1] && wb[0] < wa[1];
}

export function findConflicts(entries: ItineraryEntry[]): Map<string, string[]> {
  const map = new Map<string, string[]>();
  for (const a of entries) {
    const hits = entries.filter((b) => b.id !== a.id && overlaps(a, b)).map((b) => b.id);
    if (hits.length > 0) map.set(a.id, hits);
  }
  return map;
}

/** Used by the schedule sheet to warn before an entry is committed. */
export function conflictsForSlot(
  entries: ItineraryEntry[],
  candidate: { experienceId: string; date: string; time: string },
  ignoreEntryId?: string,
): ItineraryEntry[] {
  const probe: ItineraryEntry = {
    id: "__probe__",
    experienceId: candidate.experienceId,
    date: candidate.date,
    time: candidate.time,
    note: "",
    addedAt: 0,
  };
  return entries.filter((e) => e.id !== ignoreEntryId && overlaps(probe, e));
}

/* ------------------------------------------------------------------ */
/* Grouping                                                            */
/* ------------------------------------------------------------------ */

export interface ItineraryDay {
  date: string;
  entries: ItineraryEntry[];
  totalYen: number;
  neighborhoods: string[];
}

export function groupByDay(entries: ItineraryEntry[]): ItineraryDay[] {
  const byDate = new Map<string, ItineraryEntry[]>();
  for (const e of entries) {
    const list = byDate.get(e.date) ?? [];
    list.push(e);
    byDate.set(e.date, list);
  }
  return [...byDate.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, list]) => {
      const sorted = [...list].sort((a, b) => toMinutes(a.time) - toMinutes(b.time));
      const experiences = sorted
        .map((e) => EXPERIENCE_BY_ID[e.experienceId])
        .filter(Boolean) as Experience[];
      return {
        date,
        entries: sorted,
        totalYen: experiences.reduce((sum, e) => sum + e.priceYen, 0),
        neighborhoods: Array.from(new Set(experiences.map((e) => e.neighborhood))),
      };
    });
}

/* ------------------------------------------------------------------ */
/* Automatic build from saved items                                    */
/* ------------------------------------------------------------------ */

/** Splits the trip into contiguous blocks, one per selected city, in order. */
export function cityBlocks(profile: TravelerProfile): Map<CityId, string[]> {
  const days = eachDay(profile.dates);
  const cities = profile.cities.length > 0 ? profile.cities : (["tokyo"] as CityId[]);
  const per = Math.max(1, Math.floor(days.length / cities.length));
  const blocks = new Map<CityId, string[]>();
  cities.forEach((city, i) => {
    const start = i * per;
    const end = i === cities.length - 1 ? days.length : start + per;
    blocks.set(city, days.slice(start, end));
  });
  return blocks;
}

let entryCounter = 0;
function nextEntryId(): string {
  entryCounter += 1;
  return `it-${entryCounter}-${Math.random().toString(36).slice(2, 8)}`;
}

export function makeEntry(
  experienceId: string,
  date: string,
  time: string,
  note = "",
): ItineraryEntry {
  return { id: nextEntryId(), experienceId, date, time, note, addedAt: Date.now() };
}

export interface BuildResult {
  entries: ItineraryEntry[];
  /** Saved items with no occurrence inside the trip window. */
  unplaced: string[];
}

/**
 * Greedy scheduler behind the "Build my itinerary" button.
 *
 * Ordering matters: items with the fewest possible days are placed first so a
 * one-night-only festival never loses its slot to a market that runs daily.
 * Within that, we prefer days that fall inside the city's block and days that
 * are not already busy, so the plan reads as geographically sensible.
 */
export function buildItinerary(
  savedIds: string[],
  profile: TravelerProfile,
  existing: ItineraryEntry[] = [],
): BuildResult {
  const blocks = cityBlocks(profile);
  const placed: ItineraryEntry[] = [...existing];
  const unplaced: string[] = [];

  const candidates = savedIds
    .map((id) => EXPERIENCE_BY_ID[id])
    .filter((e): e is Experience => Boolean(e))
    .map((exp) => ({
      exp,
      days: occurrencesWithin(exp, profile.dates, 30),
    }))
    .filter((c) => {
      if (c.days.length === 0) {
        unplaced.push(c.exp.id);
        return false;
      }
      return true;
    })
    .sort((a, b) => a.days.length - b.days.length);

  for (const { exp, days } of candidates) {
    if (placed.some((e) => e.experienceId === exp.id)) continue;
    const block = blocks.get(exp.city) ?? [];

    const ranked = [...days].sort((a, b) => {
      const inBlock = (d: string) => (block.includes(d) ? 0 : 1);
      const load = (d: string) => placed.filter((e) => e.date === d).length;
      const clash = (d: string) =>
        conflictsForSlot(placed, { experienceId: exp.id, date: d, time: a.startTime }).length;
      return (
        inBlock(a.date) - inBlock(b.date) ||
        clash(a.date) - clash(b.date) ||
        load(a.date) - load(b.date) ||
        a.date.localeCompare(b.date)
      );
    });

    const chosen = ranked[0];
    placed.push(makeEntry(exp.id, chosen.date, chosen.startTime));
  }

  return { entries: placed, unplaced };
}

/** Suggests a start time that clears everything already on that day. */
export function suggestTime(
  entries: ItineraryEntry[],
  experienceId: string,
  date: string,
  preferred: string,
): string {
  let time = preferred;
  for (let i = 0; i < 12; i++) {
    if (conflictsForSlot(entries, { experienceId, date, time }).length === 0) return time;
    time = addMinutes(time, 60);
    if (toMinutes(time) > 22 * 60) break;
  }
  return preferred;
}
