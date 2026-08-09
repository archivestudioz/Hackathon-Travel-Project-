import type { ItineraryEntry, ScoredExperience, TravelerProfile } from "@/lib/types";
import { EXPERIENCE_BY_ID } from "@/lib/data/experiences";
import {
  addMinutes,
  eachDay,
  formatDayDate,
  formatTime,
  fromISODate,
  occurrencesWithin,
  toMinutes,
  WEEKDAY_SHORT,
} from "@/lib/format";

/**
 * Deterministic itinerary assistant.
 *
 * Intentionally not a language model: the demo must work offline, with no key,
 * and give the same answer every time a judge types the same thing. It handles
 * four intents — move, remove, lighten a day, and add something free — which
 * covers the suggested prompts shown in the composer.
 *
 * To swap in a real model, keep this module's signature and have `interpret`
 * call your endpoint, returning the same `AiAction` shape. The chat UI and the
 * apply/undo flow stay unchanged.
 */

export type AiAction =
  | { kind: "move"; entryId: string; date: string; time: string }
  | { kind: "remove"; entryId: string }
  | { kind: "add"; experienceId: string; date: string; time: string }
  | null;

export interface AiResult {
  reply: string;
  action: AiAction;
  /** Rendered on the preview card above Apply / Undo. */
  previewTitle?: string;
  previewDetail?: string;
}

export interface AiContext {
  itinerary: ItineraryEntry[];
  profile: TravelerProfile;
  ranked: ScoredExperience[];
}

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

/** Resolves "friday", "day 3", "tomorrow" to a date inside the trip. */
function resolveDate(text: string, profile: TravelerProfile): string | null {
  const days = eachDay(profile.dates);
  const dayMatch = text.match(/day\s*(\d+)/);
  if (dayMatch) {
    const idx = Number(dayMatch[1]) - 1;
    if (idx >= 0 && idx < days.length) return days[idx];
  }
  if (/tomorrow/.test(text)) return days[1] ?? days[0] ?? null;
  for (let i = 0; i < WEEKDAYS.length; i++) {
    if (text.includes(WEEKDAYS[i])) {
      const hit = days.find((d) => fromISODate(d).getDay() === i);
      if (hit) return hit;
    }
  }
  return null;
}

/** Loose name match against what's already scheduled. */
function findEntry(text: string, entries: ItineraryEntry[]): ItineraryEntry | null {
  let best: { entry: ItineraryEntry; score: number } | null = null;
  for (const entry of entries) {
    const exp = EXPERIENCE_BY_ID[entry.experienceId];
    if (!exp) continue;
    const words = `${exp.name} ${exp.neighborhood} ${exp.tags.join(" ")}`.toLowerCase().split(/\s+/);
    const score = words.filter((w) => w.length > 3 && text.includes(w)).length;
    if (score > 0 && (!best || score > best.score)) best = { entry, score };
  }
  return best?.entry ?? null;
}

export function interpret(input: string, ctx: AiContext): AiResult {
  const text = input.toLowerCase().trim();
  const { itinerary, profile, ranked } = ctx;

  if (itinerary.length === 0) {
    return {
      reply: "There's nothing on your itinerary yet. Save a few things and I'll place them for you.",
      action: null,
    };
  }

  /* --- Lighten a day --------------------------------------------- */
  if (/lighter|less busy|too much|free up|clear/.test(text)) {
    const date = resolveDate(text, profile);
    const pool = date ? itinerary.filter((e) => e.date === date) : itinerary;
    if (pool.length === 0) {
      return { reply: `Nothing is scheduled on ${date ? formatDayDate(date) : "that day"}.`, action: null };
    }
    const target = [...pool].sort((a, b) => toMinutes(b.time) - toMinutes(a.time))[0];
    const exp = EXPERIENCE_BY_ID[target.experienceId];
    return {
      reply: `I'd drop the last thing on ${formatDayDate(target.date)} to give you the evening back.`,
      action: { kind: "remove", entryId: target.id },
      previewTitle: `Remove ${exp?.name ?? "that entry"}`,
      previewDetail: `${formatDayDate(target.date)} · ${formatTime(target.time)}`,
    };
  }

  /* --- Remove ----------------------------------------------------- */
  if (/^(remove|delete|drop|cancel)\b/.test(text)) {
    const entry = findEntry(text, itinerary);
    if (!entry) return { reply: "I couldn't tell which one you meant — try using its name.", action: null };
    const exp = EXPERIENCE_BY_ID[entry.experienceId];
    return {
      reply: `Taking ${exp?.name} off your plan.`,
      action: { kind: "remove", entryId: entry.id },
      previewTitle: `Remove ${exp?.name}`,
      previewDetail: `${formatDayDate(entry.date)} · ${formatTime(entry.time)}`,
    };
  }

  /* --- Add something free ----------------------------------------- */
  if (/\badd\b/.test(text)) {
    const date = resolveDate(text, profile) ?? profile.dates.start;
    const wantsFree = /free|cheap|nothing|no money/.test(text);
    const scheduled = new Set(itinerary.map((e) => e.experienceId));
    const candidate = ranked.find((s) => {
      if (scheduled.has(s.experience.id)) return false;
      if (wantsFree && s.experience.priceYen !== 0) return false;
      return occurrencesWithin(s.experience, { start: date, end: date }, 1).length > 0;
    });
    if (!candidate) {
      return {
        reply: `I couldn't find anything ${wantsFree ? "free " : ""}running on ${formatDayDate(date)}.`,
        action: null,
      };
    }
    const occ = occurrencesWithin(candidate.experience, { start: date, end: date }, 1)[0];
    return {
      reply: `${candidate.experience.name} is on that day — ${candidate.headline.toLowerCase()}.`,
      action: { kind: "add", experienceId: candidate.experience.id, date, time: occ.startTime },
      previewTitle: `Add ${candidate.experience.name}`,
      previewDetail: `${formatDayDate(date)} · ${formatTime(occ.startTime)} · ${
        candidate.experience.priceYen === 0 ? "Free" : `¥${candidate.experience.priceYen.toLocaleString()}`
      }`,
    };
  }

  /* --- Move / reschedule ------------------------------------------ */
  if (/move|reschedule|shift|swap|later|earlier|push/.test(text)) {
    const entry = findEntry(text, itinerary);
    if (!entry) {
      return { reply: "Which one should I move? Naming it works best.", action: null };
    }
    const exp = EXPERIENCE_BY_ID[entry.experienceId];
    const targetDate = resolveDate(text, profile);

    if (targetDate && targetDate !== entry.date) {
      const runs = occurrencesWithin(
        EXPERIENCE_BY_ID[entry.experienceId]!,
        { start: targetDate, end: targetDate },
        1,
      );
      if (runs.length === 0) {
        return {
          reply: `${exp?.name} doesn't run on ${formatDayDate(targetDate)}, so I've left it where it is.`,
          action: null,
        };
      }
      return {
        reply: `Moving ${exp?.name} to ${formatDayDate(targetDate)}.`,
        action: { kind: "move", entryId: entry.id, date: targetDate, time: runs[0].startTime },
        previewTitle: `Move ${exp?.name}`,
        previewDetail: `${formatDayDate(entry.date)} → ${formatDayDate(targetDate)} · ${formatTime(runs[0].startTime)}`,
      };
    }

    const delta = /earlier/.test(text) ? -120 : 120;
    const newTime = addMinutes(entry.time, delta);
    return {
      reply: `Shifting ${exp?.name} ${delta > 0 ? "two hours later" : "two hours earlier"}.`,
      action: { kind: "move", entryId: entry.id, date: entry.date, time: newTime },
      previewTitle: `Move ${exp?.name}`,
      previewDetail: `${formatTime(entry.time)} → ${formatTime(newTime)} on ${formatDayDate(entry.date)}`,
    };
  }

  /* --- Fallback ---------------------------------------------------- */
  const busiest = [...itinerary].reduce<Record<string, number>>((acc, e) => {
    acc[e.date] = (acc[e.date] ?? 0) + 1;
    return acc;
  }, {});
  const heaviest = Object.entries(busiest).sort(([, a], [, b]) => b - a)[0];
  return {
    reply: heaviest
      ? `You've got ${itinerary.length} things planned, and ${formatDayDate(heaviest[0])} is your busiest with ${heaviest[1]}. Try "make ${WEEKDAY_SHORT[fromISODate(heaviest[0]).getDay()].toLowerCase()} lighter", "move the market to Friday", or "add something free on Thursday".`
      : "Try “make day 2 lighter”, “move the food crawl to Friday”, or “add something free on Thursday”.",
    action: null,
  };
}
