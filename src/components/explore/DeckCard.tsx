"use client";

import type { ScoredExperience } from "@/lib/types";
import { ExperienceMedia } from "@/components/media/ExperienceMedia";
import { MatchChip, PricePill, SocialProof } from "@/components/ui/primitives";
import { formatDayDate, formatTime } from "@/lib/format";

/**
 * The collapsed deck card.
 *
 * Deliberately sparse: name, where, a two-line teaser and social proof. Price,
 * tags, host and the full match reasoning live one tap deeper, on the detail
 * sheet — the deck is for deciding, not for reading.
 */
export function DeckCard({ scored }: { scored: ScoredExperience }) {
  const { experience: exp, occurrence, headline } = scored;

  return (
    <div className="relative h-full w-full overflow-hidden rounded-[28px] bg-night">
      <ExperienceMedia asset={exp.media[0]} label="Vertical video" />

      {/* Readability scrim under the text block */}
      <div className="absolute inset-x-0 bottom-0 h-[62%] scrim" />

      {/* Time-sensitivity flag reads before anything else */}
      {exp.schedule.kind === "oneoff" && (
        <span className="absolute left-4 top-4 rounded-full bg-accent px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide text-white">
          One night only
        </span>
      )}
      <span className="absolute right-4 top-4">
        <PricePill yen={exp.priceYen} />
      </span>

      <div className="absolute inset-x-0 bottom-0 p-5">
        <MatchChip reason={headline} tone="dark" className="mb-3" />

        <h2 className="font-display text-[32px] leading-[1.04] tracking-[-0.02em] text-white line-clamp-2">
          {exp.name}
        </h2>

        <p className="mt-2 text-[13.5px] font-medium text-white/80">
          {exp.neighborhood}, {exp.ward}
          {occurrence && (
            <>
              {" · "}
              {formatDayDate(occurrence.date)} · {formatTime(occurrence.startTime)}
            </>
          )}
        </p>

        <p className="mt-2.5 text-[14px] leading-snug text-white/70 line-clamp-2">
          {exp.shortDescription}
        </p>

        <SocialProof saves={exp.saveCount} shares={exp.shareCount} className="mt-3.5" />
      </div>
    </div>
  );
}
