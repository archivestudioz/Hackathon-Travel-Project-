import type { DateRange, Experience, Occurrence } from "@/lib/types";

const DAY_MS = 86_400_000;

export const WEEKDAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
export const MONTH_SHORT = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/* ------------------------------------------------------------------ */
/* Dates                                                               */
/* ------------------------------------------------------------------ */

/** YYYY-MM-DD for a Date, in local time (never UTC-shifted). */
export function toISODate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;
}

/** Parses YYYY-MM-DD into a local-midnight Date. */
export function fromISODate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function today(): string {
  return toISODate(new Date());
}

export function addDays(iso: string, n: number): string {
  return toISODate(new Date(fromISODate(iso).getTime() + n * DAY_MS));
}

export function daysBetween(a: string, b: string): number {
  return Math.round((fromISODate(b).getTime() - fromISODate(a).getTime()) / DAY_MS);
}

/** Inclusive list of every date in a range. */
export function eachDay(range: DateRange): string[] {
  const out: string[] = [];
  const total = Math.max(0, daysBetween(range.start, range.end));
  for (let i = 0; i <= total; i++) out.push(addDays(range.start, i));
  return out;
}

export function isWithin(iso: string, range: DateRange): boolean {
  return iso >= range.start && iso <= range.end;
}

/** "Fri 14 Mar" */
export function formatDayDate(iso: string): string {
  const d = fromISODate(iso);
  return `${WEEKDAY_SHORT[d.getDay()]} ${d.getDate()} ${MONTH_SHORT[d.getMonth()]}`;
}

/** "14 Mar" */
export function formatShortDate(iso: string): string {
  const d = fromISODate(iso);
  return `${d.getDate()} ${MONTH_SHORT[d.getMonth()]}`;
}

/** "Mar 14 – Mar 21 · 8 days" */
export function formatRange(range: DateRange): string {
  const nights = Math.max(0, daysBetween(range.start, range.end)) + 1;
  return `${formatShortDate(range.start)} – ${formatShortDate(range.end)} · ${nights} ${
    nights === 1 ? "day" : "days"
  }`;
}

/** "7:00 PM" */
export function formatTime(hhmm: string): string {
  const [h, m] = hhmm.split(":").map(Number);
  const period = h >= 12 ? "PM" : "AM";
  const hour = h % 12 === 0 ? 12 : h % 12;
  return `${hour}:${String(m).padStart(2, "0")} ${period}`;
}

export function addMinutes(hhmm: string, mins: number): string {
  const [h, m] = hhmm.split(":").map(Number);
  const total = (h * 60 + m + mins) % 1440;
  return `${String(Math.floor(total / 60)).padStart(2, "0")}:${String(total % 60).padStart(2, "0")}`;
}

export function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

/** "2h 30m" */
export function formatDuration(mins: number): string {
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

/** "in 2 days" / "Tomorrow" / "Today" */
export function formatCountdown(iso: string): string {
  const diff = daysBetween(today(), iso);
  if (diff < 0) return "Past";
  if (diff === 0) return "Today";
  if (diff === 1) return "Tomorrow";
  if (diff < 7) return `in ${diff} days`;
  if (diff < 14) return "next week";
  return `in ${Math.round(diff / 7)} weeks`;
}

/* ------------------------------------------------------------------ */
/* Money                                                               */
/* ------------------------------------------------------------------ */

export function formatYen(yen: number): string {
  if (yen === 0) return "Free";
  return `¥${yen.toLocaleString("en-US")}`;
}

/* ------------------------------------------------------------------ */
/* Counts                                                              */
/* ------------------------------------------------------------------ */

export function formatCount(n: number): string {
  if (n < 1000) return String(n);
  return `${(n / 1000).toFixed(n < 10000 ? 1 : 0)}k`;
}

/* ------------------------------------------------------------------ */
/* Occurrences                                                         */
/* ------------------------------------------------------------------ */

/**
 * Resolves an experience to the concrete dates it can be attended on within a
 * window. Recurring items expand across matching weekdays; one-off items yield
 * at most one occurrence (or a run of them for multi-day festivals).
 */
export function occurrencesWithin(
  exp: Experience,
  range: DateRange,
  limit = 12,
): Occurrence[] {
  const out: Occurrence[] = [];
  if (exp.schedule.kind === "oneoff") {
    const { date, endDate, startTime } = exp.schedule;
    const last = endDate ?? date;
    for (const day of eachDay({ start: date, end: last })) {
      if (isWithin(day, range)) out.push({ date: day, startTime });
      if (out.length >= limit) break;
    }
    return out;
  }
  const { daysOfWeek, startTime } = exp.schedule;
  for (const day of eachDay(range)) {
    if (daysOfWeek.includes(fromISODate(day).getDay())) {
      out.push({ date: day, startTime });
      if (out.length >= limit) break;
    }
  }
  return out;
}

/** The soonest date an experience runs inside the window, if any. */
export function nextOccurrence(exp: Experience, range: DateRange): Occurrence | null {
  return occurrencesWithin(exp, range, 1)[0] ?? null;
}

/** Human-readable recurrence, e.g. "Thu–Sun" or "Sat & Sun". */
export function describeSchedule(exp: Experience): string {
  if (exp.schedule.kind === "oneoff") {
    return exp.schedule.endDate
      ? `${formatShortDate(exp.schedule.date)} – ${formatShortDate(exp.schedule.endDate)}`
      : formatDayDate(exp.schedule.date);
  }
  const days = [...exp.schedule.daysOfWeek].sort((a, b) => a - b);
  if (days.length === 7) return "Daily";
  if (days.length === 1) return `${WEEKDAY_SHORT[days[0]]}s`;
  return days.map((d) => WEEKDAY_SHORT[d]).join(" · ");
}
