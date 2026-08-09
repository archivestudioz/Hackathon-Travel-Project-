"use client";

import { useMemo, useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import type { DateRange } from "@/lib/types";
import { fromISODate, today, toISODate, MONTH_SHORT } from "@/lib/format";
import { cn } from "@/lib/cn";

const WEEKDAY_INITIALS = ["S", "M", "T", "W", "T", "F", "S"];

/** Tap a start date, then an end date. Tapping again starts a new range. */
export function RangeCalendar({
  value,
  onChange,
}: {
  value: DateRange;
  onChange: (r: DateRange) => void;
}) {
  const [cursor, setCursor] = useState(() => {
    const d = fromISODate(value.start);
    return { year: d.getFullYear(), month: d.getMonth() };
  });
  const [pendingStart, setPendingStart] = useState<string | null>(null);
  const todayISO = today();

  const grid = useMemo(() => {
    const first = new Date(cursor.year, cursor.month, 1);
    const daysInMonth = new Date(cursor.year, cursor.month + 1, 0).getDate();
    const lead = first.getDay();
    const cells: (string | null)[] = Array.from({ length: lead }, () => null);
    for (let d = 1; d <= daysInMonth; d++) {
      cells.push(toISODate(new Date(cursor.year, cursor.month, d)));
    }
    return cells;
  }, [cursor]);

  function shiftMonth(delta: number) {
    setCursor((c) => {
      const d = new Date(c.year, c.month + delta, 1);
      return { year: d.getFullYear(), month: d.getMonth() };
    });
  }

  function pick(iso: string) {
    if (iso < todayISO) return;
    if (pendingStart === null) {
      setPendingStart(iso);
      onChange({ start: iso, end: iso });
      return;
    }
    if (iso < pendingStart) {
      setPendingStart(iso);
      onChange({ start: iso, end: iso });
      return;
    }
    onChange({ start: pendingStart, end: iso });
    setPendingStart(null);
  }

  return (
    <div className="rounded-[20px] border border-line bg-white p-4">
      <div className="mb-3 flex items-center justify-between">
        <button
          onClick={() => shiftMonth(-1)}
          aria-label="Previous month"
          className="flex h-9 w-9 items-center justify-center rounded-full text-ink-soft hover:bg-sand"
        >
          <ChevronLeft size={18} />
        </button>
        <p className="text-[15px] font-semibold text-ink">
          {MONTH_SHORT[cursor.month]} {cursor.year}
        </p>
        <button
          onClick={() => shiftMonth(1)}
          aria-label="Next month"
          className="flex h-9 w-9 items-center justify-center rounded-full text-ink-soft hover:bg-sand"
        >
          <ChevronRight size={18} />
        </button>
      </div>

      <div className="mb-1 grid grid-cols-7">
        {WEEKDAY_INITIALS.map((d, i) => (
          <span key={i} className="py-1 text-center text-[11px] font-semibold text-ink-faint">
            {d}
          </span>
        ))}
      </div>

      <div className="grid grid-cols-7 gap-y-1">
        {grid.map((iso, i) => {
          if (!iso) return <span key={`e${i}`} />;
          const day = fromISODate(iso).getDate();
          const past = iso < todayISO;
          const isStart = iso === value.start;
          const isEnd = iso === value.end;
          const inRange = iso > value.start && iso < value.end;
          return (
            <button
              key={iso}
              onClick={() => pick(iso)}
              disabled={past}
              aria-label={iso}
              aria-pressed={isStart || isEnd}
              className={cn(
                "relative flex h-10 items-center justify-center text-[14px] font-medium transition-colors",
                past && "cursor-not-allowed text-ink-faint/40",
                !past && !isStart && !isEnd && !inRange && "text-ink hover:bg-sand rounded-full",
                inRange && "bg-accent-soft text-accent-deep",
                (isStart || isEnd) && "text-white",
              )}
            >
              {(isStart || isEnd) && (
                <span className="absolute inset-y-0 left-1/2 h-10 w-10 -translate-x-1/2 rounded-full bg-accent" />
              )}
              <span className="relative">{day}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
