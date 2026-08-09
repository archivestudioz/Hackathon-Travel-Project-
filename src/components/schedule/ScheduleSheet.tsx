"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { Experience } from "@/lib/types";
import { useRouter } from "next/navigation";
import { AlertTriangle, CalendarPlus, Check } from "lucide-react";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { EXPERIENCE_BY_ID } from "@/lib/data/experiences";
import {
  eachDay,
  formatDayDate,
  formatShortDate,
  formatTime,
  fromISODate,
  occurrencesWithin,
  WEEKDAY_SHORT,
} from "@/lib/format";
import { conflictsForSlot } from "@/lib/itinerary";
import { Sheet } from "@/components/ui/Sheet";
import { ExperienceMedia } from "@/components/media/ExperienceMedia";
import { Button } from "@/components/ui/primitives";
import { cn } from "@/lib/cn";

export function ScheduleSheet() {
  const router = useRouter();
  const { scheduleTarget, closeSchedule, toast } = useUI();
  const { profile, state, addToItinerary, updateEntry } = useApp();

  /* Held through the closing animation so the sheet doesn't empty mid-slide. */
  const liveExp = scheduleTarget ? EXPERIENCE_BY_ID[scheduleTarget.experienceId] ?? null : null;
  const lastExp = useRef<Experience | null>(null);
  if (liveExp) lastExp.current = liveExp;
  const exp = liveExp ?? lastExp.current;
  const editing = scheduleTarget?.entryId
    ? state.itinerary.find((e) => e.id === scheduleTarget.entryId) ?? null
    : null;

  const tripDays = useMemo(() => eachDay(profile.dates), [profile.dates]);
  const availableDates = useMemo(() => {
    if (!exp) return new Set<string>();
    return new Set(occurrencesWithin(exp, profile.dates, 60).map((o) => o.date));
  }, [exp, profile.dates]);

  const [date, setDate] = useState<string>("");
  const [time, setTime] = useState<string>("");
  const [note, setNote] = useState("");

  /* Reset the form each time the sheet opens on a new target. */
  useEffect(() => {
    if (!exp) return;
    const firstAvailable = [...availableDates].sort()[0];
    setDate(editing?.date ?? firstAvailable ?? tripDays[0] ?? "");
    setTime(
      editing?.time ??
        (exp.schedule.kind === "oneoff" ? exp.schedule.startTime : exp.schedule.startTime),
    );
    setNote(editing?.note ?? "");
  }, [exp, editing, availableDates, tripDays]);

  const conflicts = useMemo(() => {
    if (!exp || !date || !time) return [];
    return conflictsForSlot(
      state.itinerary,
      { experienceId: exp.id, date, time },
      editing?.id,
    );
  }, [exp, date, time, state.itinerary, editing?.id]);

  const noneAvailable = availableDates.size === 0;

  if (!exp) return null;

  function commit() {
    if (!exp || !date || !time) return;
    if (editing) {
      updateEntry(editing.id, { date, time, note });
      toast({ message: `Moved to ${formatShortDate(date)}`, actionLabel: "View", onAction: () => router.push("/itinerary") });
    } else {
      addToItinerary(exp.id, date, time, note);
      toast({
        message: `Added to ${formatDayDate(date)}`,
        actionLabel: "View itinerary",
        onAction: () => router.push("/itinerary"),
      });
    }
    closeSchedule();
  }

  const dayIndex = tripDays.indexOf(date) + 1;

  return (
    <Sheet open={Boolean(scheduleTarget)} onClose={closeSchedule} label={`Schedule ${exp.name}`}>
      <div className="flex-1 overflow-y-auto px-5 pb-4 hide-scrollbar">
        {/* Header */}
        <div className="flex items-center gap-3 py-3">
          <div className="h-14 w-14 shrink-0 overflow-hidden rounded-[12px]">
            <ExperienceMedia asset={exp.media[0]} variant="thumb" />
          </div>
          <div className="min-w-0">
            <p className="truncate text-[15.5px] font-semibold text-ink">{exp.name}</p>
            <p className="text-[13px] text-ink-soft">
              {exp.neighborhood} · {exp.durationMins} min
            </p>
          </div>
        </div>

        {noneAvailable && (
          <div className="mb-4 flex items-start gap-2 rounded-[14px] bg-warning-soft px-3 py-2.5 text-[13px] leading-snug text-warning">
            <AlertTriangle size={15} className="mt-0.5 shrink-0" />
            <span>
              This doesn&apos;t run during your travel dates. You can still pencil it in on any day.
            </span>
          </div>
        )}

        {/* Day picker */}
        <h3 className="label-xs mb-2 text-ink-faint">Which day?</h3>
        <div className="-mx-5 flex gap-2 overflow-x-auto hide-scrollbar px-5 pb-1">
          {tripDays.map((d) => {
            const available = noneAvailable || availableDates.has(d);
            const selected = d === date;
            const jsDate = fromISODate(d);
            return (
              <button
                key={d}
                onClick={() => available && setDate(d)}
                disabled={!available}
                aria-pressed={selected}
                className={cn(
                  "flex h-[68px] w-[58px] shrink-0 flex-col items-center justify-center rounded-[14px] border-2 transition-all",
                  selected
                    ? "border-accent bg-accent text-white"
                    : available
                      ? "border-line bg-white text-ink"
                      : "cursor-not-allowed border-transparent bg-sand/60 text-ink-faint/50",
                )}
              >
                <span className="text-[10.5px] font-semibold uppercase tracking-wide">
                  {WEEKDAY_SHORT[jsDate.getDay()]}
                </span>
                <span className="text-[19px] font-bold leading-tight tabular-nums">
                  {jsDate.getDate()}
                </span>
              </button>
            );
          })}
        </div>
        {!noneAvailable && (
          <p className="mt-2 text-[12px] text-ink-faint">
            Greyed-out days are when this isn&apos;t running.
          </p>
        )}

        {/* Time */}
        <h3 className="label-xs mb-2 mt-5 text-ink-faint">Start time</h3>
        <div className="flex items-center gap-3">
          <input
            type="time"
            value={time}
            onChange={(e) => setTime(e.target.value)}
            aria-label="Start time"
            className="rounded-[14px] border border-line bg-white px-4 py-3 text-[16px] font-semibold tabular-nums text-ink outline-none focus:border-accent"
          />
          <p className="text-[13px] text-ink-soft">
            Usually starts at {formatTime(exp.schedule.startTime)}
          </p>
        </div>

        {/* Conflicts */}
        {conflicts.length > 0 && (
          <div className="mt-4 flex items-start gap-2 rounded-[14px] bg-warning-soft px-3 py-2.5">
            <AlertTriangle size={15} className="mt-0.5 shrink-0 text-warning" />
            <div className="text-[13px] leading-snug text-warning">
              <p className="font-semibold">
                Overlaps with{" "}
                {conflicts
                  .map((c) => EXPERIENCE_BY_ID[c.experienceId]?.name)
                  .filter(Boolean)
                  .join(", ")}
              </p>
              <p className="mt-0.5 text-warning/80">
                You can schedule it anyway — we&apos;ll flag it on your timeline.
              </p>
            </div>
          </div>
        )}

        {/* Note */}
        <h3 className="label-xs mb-2 mt-5 text-ink-faint">Note (optional)</h3>
        <input
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Book a table, bring cash…"
          className="w-full rounded-[14px] border border-line bg-white px-4 py-3 text-[15px] text-ink outline-none placeholder:text-ink-faint focus:border-accent"
        />
      </div>

      <div className="border-t border-line bg-base px-5 py-3 pb-[max(14px,env(safe-area-inset-bottom))]">
        <Button full size="lg" onClick={commit} disabled={!date || !time}>
          {editing ? <Check size={18} /> : <CalendarPlus size={18} />}
          {editing ? "Save changes" : `Add to day ${dayIndex > 0 ? dayIndex : 1}`}
        </Button>
      </div>
    </Sheet>
  );
}
