"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Bookmark, CalendarPlus, Sparkles, X } from "lucide-react";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { CITY_LABELS, type CityId } from "@/lib/types";
import { formatDayDate, formatYen } from "@/lib/format";
import { ExperienceMedia } from "@/components/media/ExperienceMedia";
import { Button, Chip, EmptyState, MatchChip, Skeleton } from "@/components/ui/primitives";
import { cn } from "@/lib/cn";

type SortKey = "recent" | "date" | "price";

export default function SavedPage() {
  const router = useRouter();
  const { hydrated, savedExperiences, state, unsave, generateItinerary } = useApp();
  const { openDetail, openSchedule, toast } = useUI();
  const [city, setCity] = useState<CityId | "all">("all");
  const [sort, setSort] = useState<SortKey>("recent");
  const [building, setBuilding] = useState(false);

  const visible = useMemo(() => {
    const list = savedExperiences.filter((s) => city === "all" || s.experience.city === city);
    if (sort === "price") return [...list].sort((a, b) => a.experience.priceYen - b.experience.priceYen);
    if (sort === "date")
      return [...list].sort((a, b) =>
        (a.occurrence?.date ?? "9999").localeCompare(b.occurrence?.date ?? "9999"),
      );
    return list;
  }, [savedExperiences, city, sort]);

  const unscheduledCount = savedExperiences.filter(
    (s) => !state.itinerary.some((e) => e.experienceId === s.experience.id),
  ).length;

  function build() {
    setBuilding(true);
    window.setTimeout(() => {
      const result = generateItinerary();
      setBuilding(false);
      toast({
        message: `${result.placed} experiences scheduled across ${result.days} days`,
        actionLabel: "View",
        onAction: () => router.push("/itinerary"),
      });
      router.push("/itinerary");
    }, 1400);
  }

  if (!hydrated) {
    return (
      <div className="flex-1 space-y-3 px-5 pt-16">
        <Skeleton className="h-8 w-32 rounded-full bg-black/5" />
        <div className="grid grid-cols-2 gap-3">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-[220px] rounded-[20px] bg-black/5" />
          ))}
        </div>
      </div>
    );
  }

  if (building) return <BuildingOverlay />;

  return (
    <div className="flex-1 overflow-y-auto pb-8 hide-scrollbar">
      <header className="px-5 pt-[max(18px,env(safe-area-inset-top))]">
        <h1 className="font-display text-[34px] leading-none tracking-[-0.02em] text-ink">Saved</h1>
        <p className="mt-1.5 text-[14px] text-ink-soft">
          {savedExperiences.length}{" "}
          {savedExperiences.length === 1 ? "experience" : "experiences"}
          {unscheduledCount > 0 && ` · ${unscheduledCount} not yet planned`}
        </p>
      </header>

      {savedExperiences.length === 0 ? (
        <EmptyState
          icon={<Bookmark size={24} />}
          title="Nothing saved yet"
          body="Swipe right on anything you like and it lands here, ready to slot into a day."
          action={{ label: "Go to Explore", onClick: () => router.push("/explore") }}
        />
      ) : (
        <>
          {/* The AI moment */}
          {unscheduledCount > 0 && (
            <section className="mx-5 mt-4 overflow-hidden rounded-[20px] border border-accent/25 bg-accent-soft p-4">
              <p className="flex items-center gap-1.5 text-[15px] font-semibold text-ink">
                <Sparkles size={15} className="text-accent" />
                Turn {savedExperiences.length} saves into a day-by-day plan
              </p>
              <p className="mt-1 text-[13px] leading-snug text-ink-soft">
                We&apos;ll group them by neighbourhood, respect the days each one actually runs,
                and keep your evenings from clashing.
              </p>
              <Button size="sm" variant="accent" className="mt-3" onClick={build}>
                Build my itinerary
              </Button>
            </section>
          )}

          {/* Filters */}
          <div className="-mx-0 mt-4 flex gap-2 overflow-x-auto hide-scrollbar px-5">
            <Chip size="sm" selected={city === "all"} onClick={() => setCity("all")}>
              All
            </Chip>
            {(["tokyo", "kyoto", "osaka"] as CityId[]).map((c) => (
              <Chip key={c} size="sm" selected={city === c} onClick={() => setCity(c)}>
                {CITY_LABELS[c]}
              </Chip>
            ))}
            <span className="mx-1 w-px shrink-0 bg-line" />
            {(
              [
                ["recent", "Recent"],
                ["date", "By date"],
                ["price", "By price"],
              ] as [SortKey, string][]
            ).map(([key, label]) => (
              <Chip key={key} size="sm" selected={sort === key} onClick={() => setSort(key)}>
                {label}
              </Chip>
            ))}
          </div>

          {/* Grid */}
          <div className="mt-4 grid grid-cols-2 gap-3 px-5">
            {visible.map((s) => {
              const exp = s.experience;
              const scheduled = state.itinerary.some((e) => e.experienceId === exp.id);
              return (
                <div key={exp.id} className="flex flex-col">
                  <div className="relative">
                    <button
                      onClick={() => openDetail(exp.id)}
                      className="relative block h-[190px] w-full overflow-hidden rounded-[18px]"
                      aria-label={`Open ${exp.name}`}
                    >
                      <ExperienceMedia asset={exp.media[0]} variant="thumb" />
                      <div className="absolute inset-0 scrim" />
                      <span className="absolute bottom-2.5 left-2.5 rounded-full bg-white/92 px-2 py-0.5 text-[11px] font-bold text-ink">
                        {formatYen(exp.priceYen)}
                      </span>
                      {scheduled && (
                        <span className="absolute bottom-2.5 right-2.5 rounded-full bg-success px-2 py-0.5 text-[10px] font-bold uppercase text-white">
                          Planned
                        </span>
                      )}
                    </button>

                    <button
                      onClick={() => {
                        unsave(exp.id);
                        toast({ message: `Removed ${exp.name}` });
                      }}
                      aria-label={`Remove ${exp.name} from saved`}
                      className="absolute left-2.5 top-2.5 flex h-7 w-7 items-center justify-center rounded-full bg-black/45 text-white backdrop-blur-sm"
                    >
                      <X size={14} />
                    </button>

                    <button
                      onClick={() => openSchedule({ experienceId: exp.id })}
                      aria-label={`Add ${exp.name} to itinerary`}
                      className="absolute right-2.5 top-2.5 flex h-8 w-8 items-center justify-center rounded-full bg-accent text-white shadow"
                    >
                      <CalendarPlus size={16} />
                    </button>
                  </div>

                  <p className="mt-2 line-clamp-2 text-[14px] font-semibold leading-tight text-ink">
                    {exp.name}
                  </p>
                  <p className="text-[12px] text-ink-soft">
                    {exp.neighborhood}
                    {s.occurrence && ` · ${formatDayDate(s.occurrence.date)}`}
                  </p>
                  <MatchChip reason={s.headline} className="mt-1.5 self-start" />
                </div>
              );
            })}
          </div>

          {visible.length === 0 && (
            <p className={cn("px-5 py-10 text-center text-[14px] text-ink-soft")}>
              Nothing saved in {city === "all" ? "that filter" : CITY_LABELS[city as CityId]} yet.
            </p>
          )}
        </>
      )}
    </div>
  );
}

function BuildingOverlay() {
  const lines = [
    "Grouping by neighbourhood…",
    "Checking what runs on each day…",
    "Balancing your days…",
    "Avoiding clashes…",
  ];
  const [i, setI] = useState(0);
  useMemo(() => {
    const t = window.setInterval(() => setI((v) => Math.min(v + 1, lines.length - 1)), 340);
    window.setTimeout(() => window.clearInterval(t), 1400);
    return t;
  }, [lines.length]);

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-5 px-8">
      <Sparkles size={26} className="animate-pulse text-accent" />
      <p className="text-center text-[16px] font-medium text-ink">{lines[i]}</p>
      <div className="h-[3px] w-40 overflow-hidden rounded-full bg-line">
        <div className="h-full w-full origin-left animate-[shimmer_1.4s_linear] bg-accent" />
      </div>
    </div>
  );
}
