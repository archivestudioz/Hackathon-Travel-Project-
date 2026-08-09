"use client";

import { useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Bookmark,
  CalendarPlus,
  ChevronLeft,
  Clock,
  ExternalLink,
  Share2,
  Ticket,
  Users,
  Wallet,
} from "lucide-react";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { EXPERIENCE_BY_ID } from "@/lib/data/experiences";
import type { Experience } from "@/lib/types";
import {
  describeSchedule,
  formatCount,
  formatDayDate,
  formatDuration,
  formatTime,
  formatYen,
} from "@/lib/format";
import { Sheet } from "@/components/ui/Sheet";
import { ExperienceMedia } from "@/components/media/ExperienceMedia";
import { MapPreview } from "@/components/detail/MapPreview";
import {
  Button,
  Chip,
  IconButton,
  MatchChip,
  SocialProof,
  VerifiedTick,
} from "@/components/ui/primitives";
import { cn } from "@/lib/cn";

export async function shareExperience(exp: Experience): Promise<"shared" | "copied" | "failed"> {
  const url = exp.externalUrl;
  const text = `${exp.name} — ${exp.neighborhood}`;
  try {
    if (typeof navigator === "undefined") return "failed";
    const nav = navigator as Navigator & { share?: (d: ShareData) => Promise<void> };
    if (typeof nav.share === "function") {
      await nav.share({ title: exp.name, text, url });
      return "shared";
    }
    await nav.clipboard.writeText(`${text} — ${url}`);
    return "copied";
  } catch {
    return "failed";
  }
}

export function EventDetailSheet() {
  const router = useRouter();
  const { detailId, closeDetail, openSchedule, openDetail, toast } = useUI();
  const { isSaved, isScheduled, save, unsave, scoreFor, ranked } = useApp();
  const [expanded, setExpanded] = useState(false);
  const [activeMedia, setActiveMedia] = useState(0);

  /* Keep the last experience around while the sheet animates closed, so the
     content doesn't vanish before the slide-down finishes. */
  const liveExp = detailId ? EXPERIENCE_BY_ID[detailId] ?? null : null;
  const lastExp = useRef<Experience | null>(null);
  if (liveExp) lastExp.current = liveExp;
  const exp = liveExp ?? lastExp.current;
  const scored = exp ? scoreFor(exp.id) : undefined;

  const related = useMemo(() => {
    if (!exp) return [];
    return ranked
      .filter(
        (s) =>
          s.experience.id !== exp.id &&
          (s.experience.city === exp.city ||
            s.experience.interests.some((i) => exp.interests.includes(i))),
      )
      .slice(0, 4);
  }, [exp, ranked]);

  if (!exp) return null;

  const saved = isSaved(exp.id);
  const scheduled = isScheduled(exp.id);
  const occurrence = scored?.occurrence ?? null;

  async function onShare() {
    if (!exp) return;
    const result = await shareExperience(exp);
    if (result === "copied") toast({ message: "Link copied to clipboard" });
    if (result === "failed") toast({ message: "Couldn't share — try again", tone: "warning" });
  }

  function onTagClick(tag: string) {
    closeDetail();
    router.push(`/explore?q=${encodeURIComponent(tag)}`);
  }

  return (
    <Sheet open={Boolean(detailId)} onClose={closeDetail} height="full" label={exp.name}>
      <div className="relative flex-1 overflow-y-auto overscroll-contain hide-scrollbar pb-28">
        {/* ---------------------------------------------------------- */}
        {/* Hero                                                        */}
        {/* ---------------------------------------------------------- */}
        <div className="relative h-[52vh] min-h-[320px] w-full">
          <ExperienceMedia asset={exp.media[activeMedia]} label="Vertical video" />
          <div className="absolute inset-x-0 top-0 h-32 scrim-top" />
          <div className="absolute inset-x-0 bottom-0 h-40 scrim" />

          <div className="absolute inset-x-0 top-0 flex items-center justify-between p-4 pt-[max(16px,env(safe-area-inset-top))]">
            <IconButton diameter={40} tone="glass" label="Back" onClick={closeDetail}>
              <ChevronLeft size={20} />
            </IconButton>
            <IconButton diameter={40} tone="glass" label="Share" onClick={onShare}>
              <Share2 size={17} />
            </IconButton>
          </div>

          <div className="absolute inset-x-0 bottom-0 p-5">
            <SocialProof saves={exp.saveCount} shares={exp.shareCount} />
          </div>
        </div>

        {/* Photo strip */}
        {exp.media.length > 1 && (
          <div className="flex gap-2 overflow-x-auto hide-scrollbar px-5 py-3">
            {exp.media.map((m, i) => (
              <button
                key={m.id}
                onClick={() => setActiveMedia(i)}
                aria-label={`View ${m.alt}`}
                aria-pressed={i === activeMedia}
                className={cn(
                  "relative h-16 w-14 shrink-0 overflow-hidden rounded-[10px] border-2 transition-all",
                  i === activeMedia ? "border-accent" : "border-transparent opacity-70",
                )}
              >
                <ExperienceMedia asset={m} variant="thumb" />
              </button>
            ))}
          </div>
        )}

        {/* ---------------------------------------------------------- */}
        {/* Title block                                                 */}
        {/* ---------------------------------------------------------- */}
        <div className="px-5 pt-2">
          <h1 className="font-display text-[30px] leading-[1.08] tracking-[-0.02em] text-ink">
            {exp.name}
          </h1>
          <p className="mt-2 text-[14px] font-medium text-ink-soft">
            {exp.neighborhood}, {exp.ward}
            {occurrence && <> · {formatDayDate(occurrence.date)} · {formatTime(occurrence.startTime)}</>}
          </p>
          {scored && <MatchChip reason={scored.headline} className="mt-3" />}
        </div>

        {/* ---------------------------------------------------------- */}
        {/* Fact row                                                    */}
        {/* ---------------------------------------------------------- */}
        <div className="mt-5 grid grid-cols-3 gap-2 px-5">
          <Fact icon={<Clock size={15} />} label="Runs" value={describeSchedule(exp)} />
          <Fact icon={<Ticket size={15} />} label="Duration" value={formatDuration(exp.durationMins)} />
          <Fact icon={<Wallet size={15} />} label="Price" value={formatYen(exp.priceYen)} />
        </div>

        {/* ---------------------------------------------------------- */}
        {/* Description                                                 */}
        {/* ---------------------------------------------------------- */}
        <div className="mt-6 px-5">
          <p
            className={cn(
              "text-[15px] leading-[1.65] text-ink/85",
              !expanded && "line-clamp-4",
            )}
          >
            {exp.description}
          </p>
          <button
            onClick={() => setExpanded((e) => !e)}
            className="mt-2 text-[14px] font-semibold text-accent"
          >
            {expanded ? "Read less" : "Read more"}
          </button>
        </div>

        {/* ---------------------------------------------------------- */}
        {/* Why this matched                                            */}
        {/* ---------------------------------------------------------- */}
        {scored && scored.reasons.filter((r) => r.points > 0).length > 1 && (
          <section className="mt-7 px-5">
            <h2 className="label-xs mb-2.5 text-ink-faint">Why we picked this for you</h2>
            <ul className="space-y-1.5">
              {scored.reasons
                .filter((r) => r.points > 0)
                .sort((a, b) => b.points - a.points)
                .slice(0, 4)
                .map((r, i) => (
                  <li key={i} className="flex items-start gap-2 text-[14px] text-ink/80">
                    <span className="mt-[7px] h-1.5 w-1.5 shrink-0 rounded-full bg-accent" />
                    {r.label}
                  </li>
                ))}
            </ul>
          </section>
        )}

        {/* ---------------------------------------------------------- */}
        {/* Location                                                    */}
        {/* ---------------------------------------------------------- */}
        <section className="mt-7 px-5">
          <h2 className="label-xs mb-2.5 text-ink-faint">Where</h2>
          <MapPreview experience={exp} />
          <p className="mt-3 text-[15px] font-semibold text-ink">{exp.venue}</p>
          <p className="text-[13.5px] text-ink-soft">{exp.address}</p>
          <p className="text-[13.5px] text-ink-faint">{exp.addressJa}</p>
          <p className="mt-2 text-[13px] text-ink-soft">{exp.accessNote}</p>
        </section>

        {/* ---------------------------------------------------------- */}
        {/* Organizer                                                   */}
        {/* ---------------------------------------------------------- */}
        <section className="mt-7 px-5">
          <h2 className="label-xs mb-2.5 text-ink-faint">Hosted by</h2>
          <div className="flex items-start gap-3 rounded-[18px] border border-line bg-white p-4">
            <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-sand text-[15px] font-bold text-ink-soft">
              {exp.host.name.slice(0, 1)}
            </span>
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-1.5 text-[15px] font-semibold text-ink">
                <span className="truncate">{exp.host.name}</span>
                {exp.host.verified && <VerifiedTick />}
              </p>
              <p className="mt-0.5 text-[13px] leading-snug text-ink-soft">{exp.host.bio}</p>
              <p className="mt-1.5 flex items-center gap-1.5 text-[12px] text-ink-faint">
                <Users size={12} />
                {formatCount(exp.host.followers)} followers · {exp.host.eventsHosted} hosted
              </p>
            </div>
          </div>
        </section>

        {/* ---------------------------------------------------------- */}
        {/* Tags                                                        */}
        {/* ---------------------------------------------------------- */}
        <section className="mt-7 px-5">
          <h2 className="label-xs mb-2.5 text-ink-faint">Tags</h2>
          <div className="flex flex-wrap gap-2">
            {exp.tags.map((t) => (
              <Chip key={t} size="sm" onClick={() => onTagClick(t)}>
                {t}
              </Chip>
            ))}
          </div>
        </section>

        {/* ---------------------------------------------------------- */}
        {/* Booking                                                     */}
        {/* ---------------------------------------------------------- */}
        <section className="mt-6 px-5">
          <a
            href={exp.externalUrl}
            target="_blank"
            rel="noreferrer"
            className="flex w-full items-center justify-center gap-2 rounded-full border border-line bg-white py-3.5 text-[15px] font-semibold text-ink"
          >
            View on organiser&apos;s site
            <ExternalLink size={15} />
          </a>
        </section>

        {/* ---------------------------------------------------------- */}
        {/* Related                                                     */}
        {/* ---------------------------------------------------------- */}
        {related.length > 0 && (
          <section className="mt-8">
            <h2 className="label-xs mb-2.5 px-5 text-ink-faint">You might also like</h2>
            <div className="flex gap-3 overflow-x-auto hide-scrollbar px-5 pb-2">
              {related.map((r) => (
                <button
                  key={r.experience.id}
                  onClick={() => {
                    setExpanded(false);
                    setActiveMedia(0);
                    openDetail(r.experience.id);
                  }}
                  className="w-[164px] shrink-0 text-left"
                >
                  <div className="relative h-[112px] overflow-hidden rounded-[14px]">
                    <ExperienceMedia asset={r.experience.media[0]} variant="thumb" />
                    <div className="absolute inset-0 scrim" />
                    <span className="absolute bottom-2 left-2 rounded-full bg-white/90 px-2 py-0.5 text-[11px] font-bold text-ink">
                      {formatYen(r.experience.priceYen)}
                    </span>
                  </div>
                  <p className="mt-2 line-clamp-2 text-[13.5px] font-semibold leading-snug text-ink">
                    {r.experience.name}
                  </p>
                  <p className="text-[12px] text-ink-faint">{r.experience.neighborhood}</p>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>

      {/* ------------------------------------------------------------ */}
      {/* Sticky action bar                                             */}
      {/* ------------------------------------------------------------ */}
      <div className="absolute inset-x-0 bottom-0 flex items-center gap-3 border-t border-line bg-base/97 px-5 py-3 pb-[max(12px,env(safe-area-inset-bottom))] backdrop-blur-md">
        <IconButton
          diameter={48}
          tone={saved ? "accent" : "outline"}
          label={saved ? "Remove from saved" : "Save"}
          onClick={() => {
            if (saved) {
              unsave(exp.id);
              toast({ message: "Removed from saved" });
            } else {
              save(exp.id);
              toast({ message: "Saved" });
            }
          }}
        >
          <Bookmark size={19} fill={saved ? "currentColor" : "none"} />
        </IconButton>
        <Button
          full
          size="lg"
          onClick={() => openSchedule({ experienceId: exp.id })}
          variant={scheduled ? "secondary" : "primary"}
        >
          <CalendarPlus size={18} />
          {scheduled ? "Change your slot" : "Add to itinerary"}
        </Button>
      </div>
    </Sheet>
  );
}

function Fact({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <div className="rounded-[14px] border border-line bg-white px-3 py-2.5">
      <p className="flex items-center gap-1.5 text-ink-faint">
        <span aria-hidden>{icon}</span>
        <span className="label-xs">{label}</span>
      </p>
      <p className="mt-1 text-[13.5px] font-semibold leading-tight text-ink">{value}</p>
    </div>
  );
}
