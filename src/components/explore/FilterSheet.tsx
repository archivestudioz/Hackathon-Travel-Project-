"use client";

import { CITIES, CITY_LABELS, INTERESTS, INTEREST_LABELS } from "@/lib/types";
import type { ExploreFilters } from "@/lib/filters";
import { emptyFilters } from "@/lib/filters";
import { useApp } from "@/store/AppStore";
import { eachDay, formatShortDate, fromISODate, WEEKDAY_SHORT } from "@/lib/format";
import { Sheet } from "@/components/ui/Sheet";
import { Button, Chip, Toggle } from "@/components/ui/primitives";
import { cn } from "@/lib/cn";

const PRICE_STEPS = [
  { label: "Any price", value: null },
  { label: "Under ¥3,000", value: 3000 },
  { label: "Under ¥6,000", value: 6000 },
  { label: "Under ¥10,000", value: 10000 },
];

export function FilterSheet({
  open,
  onClose,
  filters,
  onChange,
  resultCount,
}: {
  open: boolean;
  onClose: () => void;
  filters: ExploreFilters;
  onChange: (f: ExploreFilters) => void;
  resultCount: number;
}) {
  const { profile } = useApp();
  const tripDays = eachDay(profile.dates).slice(0, 21);

  function patch(p: Partial<ExploreFilters>) {
    onChange({ ...filters, ...p });
  }

  return (
    <Sheet open={open} onClose={onClose} label="Filters">
      <div className="flex-1 overflow-y-auto px-5 pb-4 hide-scrollbar">
        <div className="flex items-center justify-between py-2">
          <h2 className="font-display text-[24px] text-ink">Filters</h2>
          <button
            onClick={() => onChange({ ...emptyFilters(), query: filters.query })}
            className="text-[13.5px] font-semibold text-accent"
          >
            Clear all
          </button>
        </div>

        <h3 className="label-xs mb-2 mt-4 text-ink-faint">City</h3>
        <div className="flex flex-wrap gap-2">
          {CITIES.map((c) => (
            <Chip
              key={c}
              selected={filters.cities.includes(c)}
              onClick={() =>
                patch({
                  cities: filters.cities.includes(c)
                    ? filters.cities.filter((x) => x !== c)
                    : [...filters.cities, c],
                })
              }
            >
              {CITY_LABELS[c]}
            </Chip>
          ))}
        </div>

        <h3 className="label-xs mb-2 mt-6 text-ink-faint">Category</h3>
        <div className="flex flex-wrap gap-2">
          {INTERESTS.map((i) => (
            <Chip
              key={i}
              size="sm"
              selected={filters.interests.includes(i)}
              onClick={() =>
                patch({
                  interests: filters.interests.includes(i)
                    ? filters.interests.filter((x) => x !== i)
                    : [...filters.interests, i],
                })
              }
            >
              {INTEREST_LABELS[i]}
            </Chip>
          ))}
        </div>

        <h3 className="label-xs mb-2 mt-6 text-ink-faint">Date</h3>
        <div className="-mx-5 flex gap-2 overflow-x-auto hide-scrollbar px-5 pb-1">
          <button
            onClick={() => patch({ onDate: null })}
            className={cn(
              "flex h-[62px] shrink-0 items-center rounded-[14px] border-2 px-4 text-[13px] font-semibold transition-all",
              filters.onDate === null ? "border-accent bg-accent text-white" : "border-line bg-white text-ink",
            )}
          >
            Any day
          </button>
          {tripDays.map((d) => {
            const selected = filters.onDate === d;
            const js = fromISODate(d);
            return (
              <button
                key={d}
                onClick={() => patch({ onDate: selected ? null : d })}
                className={cn(
                  "flex h-[62px] w-[54px] shrink-0 flex-col items-center justify-center rounded-[14px] border-2 transition-all",
                  selected ? "border-accent bg-accent text-white" : "border-line bg-white text-ink",
                )}
              >
                <span className="text-[10px] font-semibold uppercase">{WEEKDAY_SHORT[js.getDay()]}</span>
                <span className="text-[17px] font-bold tabular-nums">{js.getDate()}</span>
              </button>
            );
          })}
        </div>

        <h3 className="label-xs mb-2 mt-6 text-ink-faint">Price</h3>
        <div className="flex flex-wrap gap-2">
          {PRICE_STEPS.map((p) => (
            <Chip
              key={p.label}
              size="sm"
              selected={filters.maxPrice === p.value}
              onClick={() => patch({ maxPrice: p.value })}
            >
              {p.label}
            </Chip>
          ))}
        </div>

        <div className="mt-4 rounded-[18px] border border-line bg-white p-4">
          <Toggle
            checked={filters.freeOnly}
            onChange={(v) => patch({ freeOnly: v })}
            label="Free experiences only"
          />
        </div>

        {filters.onDate && (
          <p className="mt-3 text-[13px] text-ink-soft">
            Showing things running on {formatShortDate(filters.onDate)}.
          </p>
        )}
      </div>

      <div className="border-t border-line bg-base px-5 py-3 pb-[max(14px,env(safe-area-inset-bottom))]">
        <Button full size="lg" onClick={onClose}>
          Show {resultCount} {resultCount === 1 ? "experience" : "experiences"}
        </Button>
      </div>
    </Sheet>
  );
}
