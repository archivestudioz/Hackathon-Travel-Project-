"use client";

import { Bookmark, CalendarPlus } from "lucide-react";
import type { ScoredExperience } from "@/lib/types";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { ExperienceMedia } from "@/components/media/ExperienceMedia";
import { MatchChip, PricePill, SocialProof } from "@/components/ui/primitives";
import { formatCountdown, formatDayDate, formatTime, formatYen } from "@/lib/format";
import { cn } from "@/lib/cn";

/** Tall card used inside horizontally scrolling browse sections. */
export function RowCard({
  scored,
  badge,
}: {
  scored: ScoredExperience;
  badge?: string;
}) {
  const { openDetail } = useUI();
  const { experience: exp, occurrence } = scored;

  return (
    <button
      onClick={() => openDetail(exp.id)}
      className="relative h-[280px] w-[210px] shrink-0 overflow-hidden rounded-[20px] text-left"
    >
      <ExperienceMedia asset={exp.media[0]} variant="thumb" />
      <div className="absolute inset-0 scrim" />

      {badge && (
        <span className="absolute left-3 top-3 rounded-full bg-white/92 px-2 py-1 text-[10.5px] font-bold uppercase tracking-wide text-ink">
          {badge}
        </span>
      )}
      <span className="absolute right-3 top-3">
        <PricePill yen={exp.priceYen} />
      </span>

      <div className="absolute inset-x-0 bottom-0 p-3.5">
        <p className="font-display text-[19px] leading-[1.12] text-white line-clamp-2">{exp.name}</p>
        <p className="mt-1 text-[12px] font-medium text-white/75">
          {exp.neighborhood}
          {occurrence && ` · ${formatDayDate(occurrence.date)}`}
        </p>
        <SocialProof saves={exp.saveCount} shares={exp.shareCount} className="mt-2" />
      </div>
    </button>
  );
}

/** Horizontal list row used for search results and the map's bottom card. */
export function ListRow({
  scored,
  showMatch = true,
  className,
}: {
  scored: ScoredExperience;
  showMatch?: boolean;
  className?: string;
}) {
  const { openDetail, openSchedule, toast } = useUI();
  const { isSaved, save, unsave } = useApp();
  const { experience: exp, occurrence, headline } = scored;
  const saved = isSaved(exp.id);

  return (
    <div
      className={cn(
        "flex gap-3 rounded-[18px] border border-line bg-white p-3 text-left",
        className,
      )}
    >
      <button
        onClick={() => openDetail(exp.id)}
        aria-label={`Open ${exp.name}`}
        className="h-[92px] w-[76px] shrink-0 overflow-hidden rounded-[12px]"
      >
        <ExperienceMedia asset={exp.media[0]} variant="thumb" />
      </button>

      <div className="min-w-0 flex-1">
        <button onClick={() => openDetail(exp.id)} className="block w-full text-left">
          <p className="line-clamp-2 text-[15px] font-semibold leading-tight text-ink">{exp.name}</p>
          <p className="mt-1 text-[12.5px] text-ink-soft">
            {exp.neighborhood}
            {occurrence && ` · ${formatDayDate(occurrence.date)} · ${formatTime(occurrence.startTime)}`}
          </p>
          <p className="mt-1 text-[13px] font-bold text-ink">{formatYen(exp.priceYen)}</p>
          {showMatch && <MatchChip reason={headline} className="mt-1.5 max-w-full" />}
        </button>
      </div>

      <div className="flex flex-col items-center justify-center gap-2">
        <button
          onClick={() => {
            if (saved) {
              unsave(exp.id);
              toast({ message: "Removed from saved" });
            } else {
              save(exp.id);
              toast({ message: `Saved ${exp.name}` });
            }
          }}
          aria-label={saved ? "Remove from saved" : "Save"}
          className={cn(
            "flex h-9 w-9 items-center justify-center rounded-full border transition-colors",
            saved ? "border-accent bg-accent text-white" : "border-line text-ink-soft",
          )}
        >
          <Bookmark size={16} fill={saved ? "currentColor" : "none"} />
        </button>
        <button
          onClick={() => openSchedule({ experienceId: exp.id })}
          aria-label="Add to itinerary"
          className="flex h-9 w-9 items-center justify-center rounded-full border border-line text-ink-soft"
        >
          <CalendarPlus size={16} />
        </button>
      </div>
    </div>
  );
}

/** Badge text for the "Happening this week" row. */
export function countdownBadge(scored: ScoredExperience): string | undefined {
  return scored.occurrence ? formatCountdown(scored.occurrence.date) : undefined;
}
