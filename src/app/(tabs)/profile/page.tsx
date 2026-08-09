"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronDown, RotateCcw, Sparkles } from "lucide-react";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { EXPERIENCE_BY_ID } from "@/lib/data/experiences";
import {
  BUDGET_LABELS,
  BUDGET_TIERS,
  CITIES,
  CITY_LABELS,
  INTERESTS,
  INTEREST_LABELS,
  TRAVEL_STYLES,
  TRAVEL_STYLE_LABELS,
} from "@/lib/types";
import { formatRange } from "@/lib/format";
import { RangeCalendar } from "@/components/onboarding/RangeCalendar";
import { VoiceInput } from "@/components/onboarding/VoiceInput";
import { Button, Chip, Skeleton, Toggle } from "@/components/ui/primitives";
import { cn } from "@/lib/cn";

export default function ProfilePage() {
  const router = useRouter();
  const { hydrated, profile, state, updateProfile, restore, reset, ranked } = useApp();
  const { toast } = useUI();
  const [description, setDescription] = useState(profile.description);
  const [datesOpen, setDatesOpen] = useState(false);
  const [passedOpen, setPassedOpen] = useState(false);

  if (!hydrated) {
    return (
      <div className="flex-1 space-y-4 px-5 pt-16">
        <Skeleton className="h-24 w-full rounded-[20px] bg-black/5" />
        <Skeleton className="h-40 w-full rounded-[20px] bg-black/5" />
      </div>
    );
  }

  const plannedCount = state.itinerary.length;
  const dayCount = new Set(state.itinerary.map((e) => e.date)).size;
  const monogram = (profile.name || "T").trim().slice(0, 1).toUpperCase();

  function saveDescription() {
    const before = ranked.slice(0, 8).map((s) => s.experience.id);
    updateProfile({ description });
    /* Recomputed on the next render — compare to show a concrete result. */
    window.setTimeout(() => {
      const after = ranked.slice(0, 8).map((s) => s.experience.id);
      const changed = after.filter((id) => !before.includes(id)).length;
      toast({
        message: changed > 0 ? `Feed updated — ${changed} new matches` : "Feed updated",
        actionLabel: "See it",
        onAction: () => router.push("/explore"),
      });
    }, 60);
  }

  return (
    <div className="flex-1 overflow-y-auto pb-10 hide-scrollbar">
      {/* Header */}
      <header
        className="px-5 pb-5 pt-[max(22px,env(safe-area-inset-top))]"
        style={{
          background:
            "linear-gradient(160deg, rgba(251,234,230,0.95) 0%, rgba(250,248,245,0) 100%)",
        }}
      >
        <div className="flex items-center gap-4">
          <span className="flex h-[68px] w-[68px] items-center justify-center rounded-full bg-ink text-[26px] font-bold text-white">
            {monogram}
          </span>
          <div className="min-w-0">
            <h1 className="truncate font-display text-[28px] leading-tight tracking-tight text-ink">
              {profile.name || "Traveller"}
            </h1>
            <p className="text-[13px] text-ink-soft">
              {profile.cities.map((c) => CITY_LABELS[c]).join(" · ") || "No cities yet"}
            </p>
            <p className="text-[13px] text-ink-faint">{formatRange(profile.dates)}</p>
          </div>
        </div>

        {/* Stats */}
        <div className="mt-4 grid grid-cols-3 gap-2">
          {[
            { label: "Saved", value: state.saved.length },
            { label: "Planned", value: plannedCount },
            { label: "Days", value: dayCount },
          ].map((s) => (
            <div key={s.label} className="rounded-[14px] border border-line bg-white px-3 py-2.5">
              <p className="text-[20px] font-bold tabular-nums leading-none text-ink">{s.value}</p>
              <p className="label-xs mt-1 text-ink-faint">{s.label}</p>
            </div>
          ))}
        </div>
      </header>

      {/* About you */}
      <Section title="About you" caption="This shapes your feed.">
        <div className="flex items-start gap-3">
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={4}
            placeholder="I love tiny jazz bars and vintage shops, and I'd rather avoid crowds…"
            className="flex-1 resize-none rounded-[16px] border border-line bg-white p-3.5 text-[14.5px] leading-relaxed text-ink outline-none placeholder:text-ink-faint focus:border-accent"
          />
          <VoiceInput
            size={44}
            onTranscript={(t) => setDescription((d) => (d ? `${d} ${t}` : t))}
          />
        </div>
        <Button
          size="sm"
          variant="accent"
          className="mt-3"
          disabled={description === profile.description}
          onClick={saveDescription}
        >
          <Sparkles size={14} />
          Update my feed
        </Button>
      </Section>

      {/* Interests */}
      <Section title="Interests" caption="Tap to add or remove.">
        <div className="flex flex-wrap gap-2">
          {INTERESTS.map((i) => {
            const on = profile.interests.includes(i);
            return (
              <Chip
                key={i}
                size="sm"
                selected={on}
                onClick={() =>
                  updateProfile({
                    interests: on
                      ? profile.interests.filter((x) => x !== i)
                      : [...profile.interests, i],
                  })
                }
              >
                {INTEREST_LABELS[i]}
              </Chip>
            );
          })}
        </div>
      </Section>

      {/* Destinations */}
      <Section title="Destinations">
        <div className="flex flex-wrap gap-2">
          {CITIES.map((c) => {
            const on = profile.cities.includes(c);
            return (
              <Chip
                key={c}
                selected={on}
                onClick={() =>
                  updateProfile({
                    cities: on ? profile.cities.filter((x) => x !== c) : [...profile.cities, c],
                  })
                }
              >
                {CITY_LABELS[c]}
              </Chip>
            );
          })}
        </div>
      </Section>

      {/* Dates */}
      <Section title="Travel dates">
        <button
          onClick={() => setDatesOpen((o) => !o)}
          className="flex w-full items-center justify-between rounded-[16px] border border-line bg-white px-4 py-3.5"
        >
          <span className="text-[15px] font-medium text-ink">{formatRange(profile.dates)}</span>
          <ChevronDown
            size={18}
            className={cn("text-ink-soft transition-transform", datesOpen && "rotate-180")}
          />
        </button>
        {datesOpen && (
          <div className="mt-3">
            <RangeCalendar value={profile.dates} onChange={(dates) => updateProfile({ dates })} />
          </div>
        )}
      </Section>

      {/* Style & budget */}
      <Section title="Travel style">
        <div className="flex flex-wrap gap-2">
          {TRAVEL_STYLES.map((s) => (
            <Chip
              key={s}
              size="sm"
              selected={profile.style === s}
              onClick={() => updateProfile({ style: s })}
            >
              {TRAVEL_STYLE_LABELS[s]}
            </Chip>
          ))}
        </div>
      </Section>

      <Section title="Budget">
        <div className="flex flex-wrap gap-2">
          {BUDGET_TIERS.map((b) => (
            <Chip
              key={b}
              size="sm"
              selected={profile.budget === b}
              onClick={() => updateProfile({ budget: b })}
            >
              {BUDGET_LABELS[b]}
            </Chip>
          ))}
        </div>
        <div className="mt-3 rounded-[16px] border border-line bg-white p-4">
          <Toggle
            checked={profile.freeOnly}
            onChange={(v) => updateProfile({ freeOnly: v })}
            label="Only show free experiences"
          />
        </div>
      </Section>

      {/* Passed */}
      {state.dismissed.length > 0 && (
        <Section title="Passed experiences">
          <button
            onClick={() => setPassedOpen((o) => !o)}
            className="flex w-full items-center justify-between rounded-[16px] border border-line bg-white px-4 py-3.5"
          >
            <span className="text-[15px] font-medium text-ink">
              {state.dismissed.length} passed on
            </span>
            <ChevronDown
              size={18}
              className={cn("text-ink-soft transition-transform", passedOpen && "rotate-180")}
            />
          </button>
          {passedOpen && (
            <ul className="mt-2 space-y-2">
              {state.dismissed.map((d) => {
                const exp = EXPERIENCE_BY_ID[d.experienceId];
                if (!exp) return null;
                return (
                  <li
                    key={d.experienceId}
                    className="flex items-center gap-3 rounded-[14px] border border-line bg-white px-3 py-2.5"
                  >
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-[14px] font-medium text-ink">
                        {exp.name}
                      </span>
                      <span className="block text-[12px] text-ink-faint">{exp.neighborhood}</span>
                    </span>
                    <button
                      onClick={() => {
                        restore(exp.id);
                        toast({ message: `${exp.name} is back in your deck` });
                      }}
                      className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-line px-3 py-1.5 text-[12.5px] font-semibold text-ink-soft"
                    >
                      <RotateCcw size={12} />
                      Restore
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </Section>
      )}

      {/* Demo tooling */}
      <Section title="Demo">
        <button
          onClick={() => {
            if (window.confirm("Reset all demo data and start over?")) {
              reset();
              router.replace("/");
            }
          }}
          className="w-full rounded-[16px] border border-accent/40 bg-white px-4 py-3.5 text-left text-[15px] font-semibold text-accent"
        >
          Reset demo data
        </button>
        <p className="mt-2 text-[12px] leading-snug text-ink-faint">
          Everything is stored in this browser only. Refreshing keeps your state; resetting clears
          it and returns you to the start.
        </p>
      </Section>
    </div>
  );
}

function Section({
  title,
  caption,
  children,
}: {
  title: string;
  caption?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mt-6 px-5">
      <h2 className="label-xs text-ink-faint">{title}</h2>
      {caption && <p className="mb-2.5 mt-1 text-[13px] text-ink-soft">{caption}</p>}
      <div className={caption ? "" : "mt-2.5"}>{children}</div>
    </section>
  );
}
