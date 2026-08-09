"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import {
  ArrowRight,
  Check,
  ChevronLeft,
  Heart,
  Sparkles,
  Users,
  User,
  UsersRound,
  Wallet,
} from "lucide-react";
import { useApp } from "@/store/AppStore";
import { emptyProfile } from "@/lib/storage";
import {
  BUDGET_TIERS,
  CITIES,
  CITY_LABELS,
  INTERESTS,
  INTEREST_LABELS,
  TRAVEL_STYLES,
  TRAVEL_STYLE_LABELS,
  type BudgetTierId,
  type CityId,
  type InterestId,
  type TravelerProfile,
  type TravelStyleId,
} from "@/lib/types";
import { formatRange } from "@/lib/format";
import { Button, Chip, Toggle } from "@/components/ui/primitives";
import { ExperienceMedia } from "@/components/media/ExperienceMedia";
import { RangeCalendar } from "@/components/onboarding/RangeCalendar";
import { VoiceInput } from "@/components/onboarding/VoiceInput";
import { cn } from "@/lib/cn";

const TOTAL_STEPS = 7;

const CITY_BLURBS: Record<CityId, string> = {
  tokyo: "Neon, night markets and neighbourhoods that never repeat",
  kyoto: "Shrines at dawn, workshops and the old streets",
  osaka: "Eat until you drop, then find the basement bar",
};

const STYLE_ICONS: Record<TravelStyleId, React.ReactNode> = {
  solo: <User size={20} />,
  couple: <Heart size={20} />,
  family: <Users size={20} />,
  group: <UsersRound size={20} />,
};

const STYLE_BLURBS: Record<TravelStyleId, string> = {
  solo: "Small groups and places that are easy to join alone",
  couple: "Quieter rooms, sunsets and counter dining",
  family: "Daytime, step-free and nothing age-restricted",
  group: "Crawls, tournaments and places that take six",
};

const BUDGET_BLURBS: Record<BudgetTierId, { label: string; range: string; blurb: string }> = {
  budget: { label: "Budget", range: "Under ¥3,000", blurb: "Free events, markets and street food" },
  mid: { label: "Mid-range", range: "¥3,000 – ¥10,000", blurb: "Guided tours, workshops and tastings" },
  splurge: { label: "Splurge", range: "¥10,000+", blurb: "Counter dining and private experiences" },
};

export default function OnboardingPage() {
  const router = useRouter();
  const { hydrated, completeOnboarding } = useApp();
  const [step, setStep] = useState(0);
  const [generating, setGenerating] = useState(false);
  const [draft, setDraft] = useState<TravelerProfile>(() => emptyProfile());

  function patch(p: Partial<TravelerProfile>) {
    setDraft((d) => ({ ...d, ...p }));
  }

  const canContinue = useMemo(() => {
    switch (step) {
      case 0: return true;
      case 1: return draft.cities.length > 0;
      case 2: return draft.interests.length >= 3;
      case 3: return true;
      case 4: return Boolean(draft.dates.start && draft.dates.end);
      case 5: return true;
      case 6: return true;
      default: return true;
    }
  }, [step, draft]);

  function next() {
    if (step < TOTAL_STEPS - 1) {
      setStep((s) => s + 1);
      return;
    }
    finish();
  }

  function finish() {
    setGenerating(true);
    completeOnboarding({
      ...draft,
      name: draft.name.trim() || "Traveller",
    });
  }

  if (generating) return <GeneratingScreen cities={draft.cities} onDone={() => router.replace("/explore")} />;

  return (
    <div className="flex min-h-dvh flex-col bg-base">
      {/* Progress */}
      <div className="sticky top-0 z-10 bg-base px-5 pt-[max(14px,env(safe-area-inset-top))] pb-3">
        <div className="flex gap-1.5" role="progressbar" aria-valuenow={step + 1} aria-valuemin={1} aria-valuemax={TOTAL_STEPS}>
          {Array.from({ length: TOTAL_STEPS }, (_, i) => (
            <span
              key={i}
              className={cn(
                "h-[3px] flex-1 rounded-full transition-colors duration-300",
                i <= step ? "bg-accent" : "bg-line",
              )}
            />
          ))}
        </div>
        {step > 0 && (
          <button
            onClick={() => setStep((s) => s - 1)}
            className="-ml-2 mt-3 flex h-9 w-9 items-center justify-center rounded-full text-ink-soft hover:bg-sand"
            aria-label="Back"
          >
            <ChevronLeft size={20} />
          </button>
        )}
      </div>

      <div className="flex flex-1 flex-col px-5 pb-4">
        <AnimatePresence mode="wait">
          <motion.div
            key={step}
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
            className="flex flex-1 flex-col"
          >
            {step === 0 && <PreviewStep />}

            {step === 1 && (
              <StepFrame
                title="Where in Japan?"
                helper="Pick every city you'll be in — we'll group your days by them."
              >
                <div className="flex flex-col gap-3">
                  {CITIES.map((city) => {
                    const selected = draft.cities.includes(city);
                    return (
                      <button
                        key={city}
                        onClick={() =>
                          patch({
                            cities: selected
                              ? draft.cities.filter((c) => c !== city)
                              : [...draft.cities, city],
                          })
                        }
                        aria-pressed={selected}
                        className={cn(
                          "relative h-[124px] overflow-hidden rounded-[20px] border-2 text-left transition-all duration-200",
                          selected ? "border-accent" : "border-transparent",
                        )}
                      >
                        <ExperienceMedia variant="thumb" label={CITY_LABELS[city]} />
                        <div className="absolute inset-0 scrim" />
                        <div className="absolute inset-x-0 bottom-0 p-4">
                          <p className="font-display text-[26px] leading-none text-white">
                            {CITY_LABELS[city]}
                          </p>
                          <p className="mt-1.5 text-[12.5px] leading-snug text-white/70">
                            {CITY_BLURBS[city]}
                          </p>
                        </div>
                        {selected && (
                          <span className="absolute right-3 top-3 flex h-7 w-7 items-center justify-center rounded-full bg-accent text-white">
                            <Check size={15} strokeWidth={3} />
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              </StepFrame>
            )}

            {step === 2 && (
              <StepFrame
                title="What are you into?"
                helper={`Pick at least three. ${draft.interests.length} of ${INTERESTS.length} selected.`}
              >
                <div className="flex flex-wrap gap-2">
                  {INTERESTS.map((i: InterestId) => {
                    const selected = draft.interests.includes(i);
                    return (
                      <Chip
                        key={i}
                        selected={selected}
                        onClick={() =>
                          patch({
                            interests: selected
                              ? draft.interests.filter((x) => x !== i)
                              : [...draft.interests, i],
                          })
                        }
                      >
                        {INTEREST_LABELS[i]}
                      </Chip>
                    );
                  })}
                </div>
              </StepFrame>
            )}

            {step === 3 && (
              <StepFrame title="Who's going?" helper="This changes what we put in front of you.">
                <div className="flex flex-col gap-2.5">
                  {TRAVEL_STYLES.map((s) => {
                    const selected = draft.style === s;
                    return (
                      <button
                        key={s}
                        onClick={() => patch({ style: s })}
                        aria-pressed={selected}
                        className={cn(
                          "flex items-center gap-4 rounded-[18px] border-2 bg-white p-4 text-left transition-all",
                          selected ? "border-accent" : "border-line",
                        )}
                      >
                        <span
                          className={cn(
                            "flex h-11 w-11 shrink-0 items-center justify-center rounded-full",
                            selected ? "bg-accent text-white" : "bg-sand text-ink-soft",
                          )}
                        >
                          {STYLE_ICONS[s]}
                        </span>
                        <span className="flex-1">
                          <span className="block text-[16px] font-semibold text-ink">
                            {TRAVEL_STYLE_LABELS[s]}
                          </span>
                          <span className="block text-[13px] leading-snug text-ink-soft">
                            {STYLE_BLURBS[s]}
                          </span>
                        </span>
                      </button>
                    );
                  })}
                </div>
              </StepFrame>
            )}

            {step === 4 && (
              <StepFrame title="When are you there?" helper="We only show things running while you're in town.">
                <p className="mb-3 text-[15px] font-semibold text-accent-deep">
                  {formatRange(draft.dates)}
                </p>
                <RangeCalendar value={draft.dates} onChange={(dates) => patch({ dates })} />
                <div className="mt-4 rounded-[18px] border border-line bg-white p-4">
                  <Toggle
                    checked={draft.flexibleDates}
                    onChange={(v) => patch({ flexibleDates: v })}
                    label="My dates are flexible"
                  />
                </div>
              </StepFrame>
            )}

            {step === 5 && (
              <StepFrame title="What's a night out worth?" helper="Per experience, roughly. You can change this later.">
                <div className="flex flex-col gap-2.5">
                  {BUDGET_TIERS.map((b) => {
                    const selected = draft.budget === b;
                    const info = BUDGET_BLURBS[b];
                    return (
                      <button
                        key={b}
                        onClick={() => patch({ budget: b })}
                        aria-pressed={selected}
                        className={cn(
                          "flex items-center gap-4 rounded-[18px] border-2 bg-white p-4 text-left transition-all",
                          selected ? "border-accent" : "border-line",
                        )}
                      >
                        <span
                          className={cn(
                            "flex h-11 w-11 shrink-0 items-center justify-center rounded-full",
                            selected ? "bg-accent text-white" : "bg-sand text-ink-soft",
                          )}
                        >
                          <Wallet size={20} />
                        </span>
                        <span className="flex-1">
                          <span className="flex items-baseline gap-2">
                            <span className="text-[16px] font-semibold text-ink">{info.label}</span>
                            <span className="text-[13px] font-medium tabular-nums text-ink-soft">
                              {info.range}
                            </span>
                          </span>
                          <span className="block text-[13px] leading-snug text-ink-soft">
                            {info.blurb}
                          </span>
                        </span>
                      </button>
                    );
                  })}
                </div>
                <div className="mt-4 rounded-[18px] border border-line bg-white p-4">
                  <Toggle
                    checked={draft.freeOnly}
                    onChange={(v) => patch({ freeOnly: v })}
                    label="Only show free experiences"
                  />
                </div>
              </StepFrame>
            )}

            {step === 6 && (
              <StepFrame
                title="Anything else?"
                helper="Say it however you like — this is matched against every listing."
              >
                <label className="mb-4 block">
                  <span className="label-xs mb-1.5 block text-ink-faint">What should we call you?</span>
                  <input
                    value={draft.name}
                    onChange={(e) => patch({ name: e.target.value })}
                    placeholder="Alex"
                    className="w-full rounded-[14px] border border-line bg-white px-4 py-3 text-[15px] text-ink outline-none placeholder:text-ink-faint focus:border-accent"
                  />
                </label>

                <div className="flex items-start gap-3">
                  <textarea
                    value={draft.description}
                    onChange={(e) => patch({ description: e.target.value })}
                    rows={5}
                    placeholder="I love tiny jazz bars and vintage shops, and I'd rather avoid crowds…"
                    className="flex-1 resize-none rounded-[18px] border border-line bg-white p-4 text-[15px] leading-relaxed text-ink outline-none placeholder:text-ink-faint focus:border-accent"
                  />
                  <VoiceInput
                    onTranscript={(text) =>
                      patch({
                        description: draft.description ? `${draft.description} ${text}` : text,
                      })
                    }
                  />
                </div>

                <button
                  onClick={finish}
                  className="mt-4 self-start py-2 text-[14px] font-medium text-ink-soft underline underline-offset-4"
                >
                  Skip this step
                </button>
              </StepFrame>
            )}
          </motion.div>
        </AnimatePresence>

        <div className="sticky bottom-0 mt-6 bg-base pb-[max(16px,env(safe-area-inset-bottom))] pt-3">
          <Button size="lg" full onClick={next} disabled={!canContinue || !hydrated}>
            {step === TOTAL_STEPS - 1 ? "Build my feed" : step === 0 ? "Let's go" : "Continue"}
            <ArrowRight size={18} />
          </Button>
        </div>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Shell                                                               */
/* ------------------------------------------------------------------ */

function StepFrame({
  title,
  helper,
  children,
}: {
  title: string;
  helper: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex flex-1 flex-col">
      <h1 className="font-display text-[34px] leading-[1.05] tracking-[-0.02em] text-ink">
        {title}
      </h1>
      <p className="mb-6 mt-2 text-[14.5px] leading-snug text-ink-soft">{helper}</p>
      {children}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Step 0 — how the app works                                          */
/* ------------------------------------------------------------------ */

const PREVIEW_PHASES = [
  { title: "Swipe through what's on", body: "Right to save, left to pass. Only things running while you're here." },
  { title: "We learn as you go", body: "Every card tells you exactly why it was picked for you." },
  { title: "Turn saves into a plan", body: "Your itinerary builds itself, grouped by day and neighbourhood." },
];

function PreviewStep() {
  const [phase, setPhase] = useState(0);

  useEffect(() => {
    const t = window.setInterval(() => setPhase((p) => (p + 1) % PREVIEW_PHASES.length), 2600);
    return () => window.clearInterval(t);
  }, []);

  return (
    <div className="flex flex-1 flex-col">
      <h1 className="font-display text-[34px] leading-[1.05] tracking-[-0.02em] text-ink">
        Here&apos;s how it works
      </h1>
      <p className="mb-5 mt-2 text-[14.5px] leading-snug text-ink-soft">
        Three steps, about a minute.
      </p>

      <div className="relative flex-1 overflow-hidden rounded-[24px] border border-line bg-white">
        <AnimatePresence mode="wait">
          <motion.div
            key={phase}
            initial={{ opacity: 0, scale: 0.96 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 1.02 }}
            transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
            className="absolute inset-0 flex items-center justify-center p-6"
          >
            {phase === 0 && <PreviewSwipe />}
            {phase === 1 && <PreviewMatch />}
            {phase === 2 && <PreviewItinerary />}
          </motion.div>
        </AnimatePresence>
      </div>

      <div className="mt-5 min-h-[68px]">
        <AnimatePresence mode="wait">
          <motion.div
            key={phase}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.25 }}
          >
            <p className="text-[18px] font-semibold text-ink">{PREVIEW_PHASES[phase].title}</p>
            <p className="mt-1 text-[14px] leading-snug text-ink-soft">
              {PREVIEW_PHASES[phase].body}
            </p>
          </motion.div>
        </AnimatePresence>
      </div>

      <div className="mt-3 flex justify-center gap-1.5">
        {PREVIEW_PHASES.map((_, i) => (
          <span
            key={i}
            className={cn(
              "h-1.5 rounded-full transition-all duration-300",
              i === phase ? "w-5 bg-accent" : "w-1.5 bg-line",
            )}
          />
        ))}
      </div>
    </div>
  );
}

function PreviewSwipe() {
  return (
    <div className="relative h-full w-full max-w-[200px]">
      {[2, 1, 0].map((depth) => (
        <motion.div
          key={depth}
          className="absolute inset-x-0 top-1/2 -translate-y-1/2 rounded-[18px] border-2 border-dashed border-line bg-sand"
          style={{ height: "72%" }}
          animate={
            depth === 0
              ? { x: [0, 120, 120, 0], rotate: [0, 12, 12, 0], opacity: [1, 0, 0, 1] }
              : { scale: 1 - depth * 0.05, y: depth * 8 }
          }
          transition={
            depth === 0
              ? { duration: 2.6, times: [0, 0.45, 0.75, 0.76], repeat: Infinity }
              : { duration: 0.3 }
          }
        >
          {depth === 0 && (
            <div className="flex h-full flex-col justify-end p-3">
              <span className="mb-2 h-2 w-14 rounded-full bg-line" />
              <span className="h-2 w-20 rounded-full bg-line" />
            </div>
          )}
        </motion.div>
      ))}
      <motion.span
        className="absolute right-0 top-1/2 -translate-y-1/2 rounded-full bg-accent px-2.5 py-1 text-[11px] font-bold text-white"
        animate={{ opacity: [0, 1, 1, 0] }}
        transition={{ duration: 2.6, times: [0.25, 0.4, 0.6, 0.7], repeat: Infinity }}
      >
        SAVE
      </motion.span>
    </div>
  );
}

function PreviewMatch() {
  return (
    <div className="w-full max-w-[230px] space-y-2.5">
      {["Because you like street food", "Near your stay in Shibuya", "Only on while you're here"].map(
        (label, i) => (
          <motion.div
            key={label}
            initial={{ opacity: 0, x: -12 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.15 + i * 0.25 }}
            className="flex items-center gap-2 rounded-full bg-accent-soft px-3 py-2"
          >
            <Sparkles size={13} className="shrink-0 text-accent" />
            <span className="text-[12.5px] font-semibold text-accent-deep">{label}</span>
          </motion.div>
        ),
      )}
    </div>
  );
}

function PreviewItinerary() {
  return (
    <div className="w-full max-w-[230px]">
      <div className="relative pl-6">
        <span className="absolute left-[7px] top-2 bottom-2 w-px bg-line" />
        {["09:00", "13:30", "19:00"].map((time, i) => (
          <motion.div
            key={time}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.15 + i * 0.28 }}
            className="relative mb-3 flex items-center gap-3"
          >
            <span className="absolute -left-6 h-3.5 w-3.5 rounded-full border-2 border-accent bg-white" />
            <span className="w-11 shrink-0 text-[11px] font-semibold tabular-nums text-ink-faint">
              {time}
            </span>
            <span className="h-11 flex-1 rounded-[12px] border border-line bg-sand" />
          </motion.div>
        ))}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Generating                                                          */
/* ------------------------------------------------------------------ */

function GeneratingScreen({ cities, onDone }: { cities: CityId[]; onDone: () => void }) {
  const lines = useMemo(
    () => [
      "Reading your interests…",
      `Finding local events in ${cities[0] ? CITY_LABELS[cities[0]] : "Tokyo"}…`,
      "Checking what's on during your dates…",
      "Ranking experiences for you…",
    ],
    [cities],
  );
  const [line, setLine] = useState(0);

  useEffect(() => {
    const step = window.setInterval(() => setLine((l) => Math.min(l + 1, lines.length - 1)), 460);
    const done = window.setTimeout(onDone, 1900);
    return () => {
      window.clearInterval(step);
      window.clearTimeout(done);
    };
  }, [lines.length, onDone]);

  return (
    <div className="relative flex min-h-dvh flex-col items-center justify-center overflow-hidden bg-night px-8">
      <div
        aria-hidden
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(600px 480px at 50% 38%, rgba(217,79,61,0.35), transparent 65%), radial-gradient(520px 400px at 20% 84%, rgba(180,120,60,0.22), transparent 62%)",
        }}
      />
      <motion.div
        animate={{ rotate: 360 }}
        transition={{ duration: 2.6, repeat: Infinity, ease: "linear" }}
        className="relative mb-8"
      >
        <Sparkles size={30} className="text-accent" />
      </motion.div>
      <AnimatePresence mode="wait">
        <motion.p
          key={line}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: -8 }}
          transition={{ duration: 0.22 }}
          className="relative text-center text-[17px] font-medium text-white/85"
        >
          {lines[line]}
        </motion.p>
      </AnimatePresence>
      <div className="relative mt-8 h-[3px] w-40 overflow-hidden rounded-full bg-white/15">
        <motion.div
          className="h-full bg-accent"
          initial={{ width: "0%" }}
          animate={{ width: "100%" }}
          transition={{ duration: 1.9, ease: "easeInOut" }}
        />
      </div>
    </div>
  );
}
