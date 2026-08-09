"use client";

import { useMemo, useRef } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  CalendarDays,
  Clock,
  Footprints,
  MapPin,
  Pencil,
  Sparkles,
  Trash2,
  TrainFront,
} from "lucide-react";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { EXPERIENCE_BY_ID } from "@/lib/data/experiences";
import { estimateTravel, findConflicts } from "@/lib/itinerary";
import {
  eachDay,
  formatDayDate,
  formatDuration,
  formatRange,
  formatTime,
  formatYen,
  fromISODate,
  today,
  WEEKDAY_SHORT,
} from "@/lib/format";
import { ExperienceMedia } from "@/components/media/ExperienceMedia";
import { EmptyState, Skeleton } from "@/components/ui/primitives";
import { cn } from "@/lib/cn";

export default function ItineraryPage() {
  const router = useRouter();
  const { hydrated, profile, itineraryDays, state, removeEntry } = useApp();
  const { openDetail, openSchedule, setChatOpen, toast } = useUI();
  const dayRefs = useRef<Record<string, HTMLDivElement | null>>({});

  const conflicts = useMemo(() => findConflicts(state.itinerary), [state.itinerary]);
  const tripDays = useMemo(() => eachDay(profile.dates), [profile.dates]);
  const todayISO = today();

  const entriesByDate = useMemo(() => {
    const map = new Map<string, number>();
    for (const d of itineraryDays) map.set(d.date, d.entries.length);
    return map;
  }, [itineraryDays]);

  if (!hydrated) {
    return (
      <div className="flex-1 space-y-4 px-5 pt-16">
        <Skeleton className="h-8 w-48 rounded-full bg-black/5" />
        {[0, 1, 2].map((i) => (
          <Skeleton key={i} className="h-24 w-full rounded-[18px] bg-black/5" />
        ))}
      </div>
    );
  }

  const totalYen = itineraryDays.reduce((sum, d) => sum + d.totalYen, 0);

  return (
    <div className="relative flex flex-1 flex-col overflow-hidden">
      {/* Header */}
      <header className="shrink-0 px-5 pt-[max(18px,env(safe-area-inset-top))]">
        <h1 className="font-display text-[32px] leading-none tracking-[-0.02em] text-ink">
          {profile.cities.length > 0
            ? profile.cities.map((c) => c[0].toUpperCase() + c.slice(1)).join(" · ")
            : "Your trip"}
        </h1>
        <p className="mt-1.5 text-[13.5px] text-ink-soft">
          {formatRange(profile.dates)}
          {state.itinerary.length > 0 && ` · ${state.itinerary.length} planned · ${formatYen(totalYen)}`}
        </p>

        {/* Day strip */}
        <div className="-mx-5 mt-3 flex gap-2 overflow-x-auto hide-scrollbar px-5 pb-1">
          {tripDays.map((d) => {
            const count = entriesByDate.get(d) ?? 0;
            const js = fromISODate(d);
            const isToday = d === todayISO;
            return (
              <button
                key={d}
                onClick={() =>
                  dayRefs.current[d]?.scrollIntoView({ behavior: "smooth", block: "start" })
                }
                disabled={count === 0}
                className={cn(
                  "flex h-[62px] w-[52px] shrink-0 flex-col items-center justify-center rounded-[14px] border-2 transition-all",
                  count > 0 ? "border-line bg-white text-ink" : "border-transparent bg-sand/50 text-ink-faint/60",
                  isToday && "border-accent",
                )}
              >
                <span className="text-[10px] font-semibold uppercase">{WEEKDAY_SHORT[js.getDay()]}</span>
                <span className="text-[17px] font-bold leading-tight tabular-nums">{js.getDate()}</span>
                <span className="mt-0.5 flex h-1.5 gap-0.5">
                  {Array.from({ length: Math.min(count, 3) }, (_, i) => (
                    <span key={i} className="h-1.5 w-1.5 rounded-full bg-accent" />
                  ))}
                </span>
              </button>
            );
          })}
        </div>
      </header>

      {/* Timeline */}
      {state.itinerary.length === 0 ? (
        <div className="flex flex-1 items-center justify-center">
          <EmptyState
            icon={<CalendarDays size={24} />}
            title="Your days are open"
            body="Add something from Saved, or let the assistant build a plan from what you've collected."
            action={{ label: "Go to Saved", onClick: () => router.push("/saved") }}
            secondaryAction={{ label: "Find something to do", onClick: () => router.push("/explore") }}
          />
        </div>
      ) : (
        <div className="mt-2 flex-1 overflow-y-auto pb-28 hide-scrollbar">
          {itineraryDays.map((day) => (
            <section
              key={day.date}
              ref={(el) => {
                dayRefs.current[day.date] = el as HTMLDivElement | null;
              }}
              className="scroll-mt-4"
            >
              {/* Day header */}
              <div className="sticky top-0 z-10 flex items-baseline justify-between bg-base/95 px-5 py-2.5 backdrop-blur-sm">
                <h2 className="font-display text-[20px] tracking-tight text-ink">
                  {formatDayDate(day.date)}
                </h2>
                <span className="text-[12px] font-medium text-ink-faint">
                  {day.entries.length} {day.entries.length === 1 ? "thing" : "things"} ·{" "}
                  {formatYen(day.totalYen)}
                </span>
              </div>

              <div className="relative px-5">
                {/* Rail */}
                {/* Rail sits under the node centres: 20px padding + 34px time
                    column + 12px gap + 6px half-node. */}
                <span className="absolute bottom-4 left-[72px] top-2 w-px bg-line" aria-hidden />

                {day.entries.map((entry, i) => {
                  const exp = EXPERIENCE_BY_ID[entry.experienceId];
                  if (!exp) return null;
                  const nextEntry = day.entries[i + 1];
                  const nextExp = nextEntry ? EXPERIENCE_BY_ID[nextEntry.experienceId] : null;
                  const leg = nextExp ? estimateTravel(exp, nextExp) : null;
                  const hasConflict = conflicts.has(entry.id);

                  return (
                    <div key={entry.id}>
                      <div className="relative flex gap-3 py-2">
                        {/* Time */}
                        <span className="w-[34px] shrink-0 pt-3 text-right text-[11px] font-semibold tabular-nums text-ink-faint">
                          {formatTime(entry.time)}
                        </span>

                        {/* Node */}
                        <span className="relative z-10 mt-3.5 h-3 w-3 shrink-0 rounded-full border-2 border-accent bg-base" />

                        {/* Card */}
                        <div
                          className={cn(
                            "min-w-0 flex-1 rounded-[16px] border bg-white p-3",
                            hasConflict ? "border-l-4 border-l-warning border-line" : "border-line",
                          )}
                        >
                          <button
                            onClick={() => openDetail(exp.id)}
                            className="flex w-full gap-3 text-left"
                          >
                            <span className="h-[58px] w-[52px] shrink-0 overflow-hidden rounded-[10px]">
                              <ExperienceMedia asset={exp.media[0]} variant="thumb" />
                            </span>
                            <span className="min-w-0 flex-1">
                              <span className="block line-clamp-2 text-[14.5px] font-semibold leading-tight text-ink">
                                {exp.name}
                              </span>
                              <span className="mt-1 flex items-center gap-1 text-[12px] text-ink-soft">
                                <MapPin size={11} className="shrink-0" />
                                <span className="truncate">
                                  {exp.venue}, {exp.neighborhood}
                                </span>
                              </span>
                              <span className="mt-0.5 flex items-center gap-2.5 text-[12px] text-ink-faint">
                                <span className="inline-flex items-center gap-1">
                                  <Clock size={11} />
                                  {formatDuration(exp.durationMins)}
                                </span>
                                <span className="font-semibold text-ink">{formatYen(exp.priceYen)}</span>
                              </span>
                            </span>
                          </button>

                          {entry.note && (
                            <p className="mt-2 rounded-[10px] bg-sand px-2.5 py-1.5 text-[12px] text-ink-soft">
                              {entry.note}
                            </p>
                          )}

                          {hasConflict && (
                            <p className="mt-2 flex items-center gap-1.5 text-[12px] font-medium text-warning">
                              <AlertTriangle size={12} />
                              Overlaps with something else today
                            </p>
                          )}

                          <div className="mt-2.5 flex gap-2 border-t border-line pt-2.5">
                            <button
                              onClick={() => openSchedule({ experienceId: exp.id, entryId: entry.id })}
                              className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12.5px] font-semibold text-ink-soft hover:bg-sand"
                            >
                              <Pencil size={12} />
                              Reschedule
                            </button>
                            <button
                              onClick={() => {
                                removeEntry(entry.id);
                                toast({ message: `Removed ${exp.name} from your plan` });
                              }}
                              className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12.5px] font-semibold text-accent hover:bg-accent-soft"
                            >
                              <Trash2 size={12} />
                              Remove
                            </button>
                          </div>
                        </div>
                      </div>

                      {/* Travel connector */}
                      {leg && (
                        <div className="flex items-center gap-3 pl-[34px]">
                          <span className="ml-[6px] flex h-7 items-center">
                            <span className="h-full w-px border-l border-dashed border-line" />
                          </span>
                          <span className="inline-flex items-center gap-1.5 text-[11.5px] font-medium text-ink-faint">
                            {leg.mode === "walk" ? <Footprints size={12} /> : <TrainFront size={12} />}
                            {leg.label}
                          </span>
                        </div>
                      )}
                    </div>
                  );
                })}

                {/* Day footer */}
                <p className="mb-2 ml-[54px] pl-3 text-[12px] text-ink-faint">
                  {day.entries.length} {day.entries.length === 1 ? "experience" : "experiences"} ·{" "}
                  {formatYen(day.totalYen)} · {day.neighborhoods.slice(0, 3).join(", ")}
                </p>
              </div>
            </section>
          ))}
        </div>
      )}

      {/* Floating assistant */}
      {state.itinerary.length > 0 && (
        <button
          onClick={() => setChatOpen(true)}
          aria-label="Edit itinerary with the assistant"
          className="absolute bottom-5 right-5 z-20 flex h-14 w-14 items-center justify-center rounded-full bg-accent text-white shadow-[0_10px_30px_-8px_rgba(217,79,61,0.8)] active:scale-95"
        >
          <Sparkles size={22} />
        </button>
      )}
    </div>
  );
}
