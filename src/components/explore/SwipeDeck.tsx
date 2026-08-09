"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  AnimatePresence,
  motion,
  useMotionValue,
  useTransform,
  type PanInfo,
} from "framer-motion";
import { Bookmark, CalendarPlus, RotateCcw, Share2, Sparkles, X } from "lucide-react";
import type { ScoredExperience } from "@/lib/types";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { DeckCard } from "@/components/explore/DeckCard";
import { shareExperience } from "@/components/detail/EventDetailSheet";
import { EmptyState, IconButton, Skeleton } from "@/components/ui/primitives";

type Direction = "left" | "right" | "up";

/** Past this fraction of the card's width, releasing commits the action. */
const COMMIT_FRACTION = 0.35;

export function SwipeDeck({
  deck,
  loading,
  onBrowse,
  onLoosenFilters,
}: {
  deck: ScoredExperience[];
  loading: boolean;
  onBrowse: () => void;
  onLoosenFilters: () => void;
}) {
  const { save, dismiss, lastAction, undo, clearLastAction } = useApp();
  const { openDetail, openSchedule, toast } = useUI();
  const [exitDir, setExitDir] = useState<Direction>("left");
  const [undoLabel, setUndoLabel] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const rotate = useTransform(x, [-260, 0, 260], [-12, 0, 12]);
  const saveOpacity = useTransform(x, [30, 150], [0, 1]);
  const passOpacity = useTransform(x, [-150, -30], [1, 0]);
  const saveWash = useTransform(x, [0, 200], [0, 0.28]);
  const passWash = useTransform(x, [-200, 0], [0.28, 0]);

  const top = deck[0];
  const behind = deck.slice(1, 3);

  const resetMotion = useCallback(() => {
    x.set(0);
    y.set(0);
  }, [x, y]);

  const act = useCallback(
    (dir: Direction) => {
      if (!top) return;
      const exp = top.experience;
      setExitDir(dir);
      if (dir === "right") {
        save(exp.id);
        setUndoLabel(`Saved ${exp.name}`);
      } else if (dir === "left") {
        dismiss(exp.id);
        setUndoLabel(`Passed on ${exp.name}`);
      } else {
        openSchedule({ experienceId: exp.id });
      }
      resetMotion();
    },
    [top, save, dismiss, openSchedule, resetMotion],
  );

  function onDragEnd(_: unknown, info: PanInfo) {
    const width = containerRef.current?.offsetWidth ?? 320;
    const threshold = width * COMMIT_FRACTION;
    if (info.offset.y < -110 && Math.abs(info.offset.x) < 90) {
      act("up");
      return;
    }
    if (info.offset.x > threshold || info.velocity.x > 700) {
      act("right");
      return;
    }
    if (info.offset.x < -threshold || info.velocity.x < -700) {
      act("left");
      return;
    }
    resetMotion();
  }

  /* Keyboard equivalents — also how the demo is driven on a laptop. */
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const target = e.target as HTMLElement | null;
      if (target && /input|textarea|select/i.test(target.tagName)) return;
      if (!top) return;
      switch (e.key) {
        case "ArrowLeft": e.preventDefault(); act("left"); break;
        case "ArrowRight": e.preventDefault(); act("right"); break;
        case "ArrowUp": e.preventDefault(); act("up"); break;
        case "Enter": e.preventDefault(); openDetail(top.experience.id); break;
        case "s": case "S": void shareExperience(top.experience); break;
        case "z": case "Z":
          if (lastAction) { undo(); setUndoLabel(null); }
          break;
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [top, act, openDetail, lastAction, undo]);

  /* The undo pill is transient; it never blocks the card underneath. */
  useEffect(() => {
    if (!undoLabel) return;
    const t = window.setTimeout(() => setUndoLabel(null), 4000);
    return () => window.clearTimeout(t);
  }, [undoLabel]);

  if (loading) return <DeckSkeleton />;

  if (!top) {
    return (
      <div className="flex flex-1 items-center justify-center">
        <EmptyState
          icon={<Sparkles size={26} />}
          title="That's everything matching your filters"
          body="Widen your filters to see more, or start turning what you've saved into a plan."
          action={{ label: "Loosen filters", onClick: onLoosenFilters }}
          secondaryAction={{ label: "Review your saves", onClick: onBrowse }}
        />
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      {/* Undo pill */}
      <div className="pointer-events-none absolute inset-x-0 top-[76px] z-30 flex justify-center px-5">
        <AnimatePresence>
          {undoLabel && (
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="pointer-events-auto flex max-w-full items-center gap-2 rounded-full bg-ink/92 px-3.5 py-2 backdrop-blur-sm"
            >
              <p className="truncate text-[12.5px] font-medium text-white">{undoLabel}</p>
              <button
                onClick={() => { undo(); setUndoLabel(null); clearLastAction(); }}
                className="flex shrink-0 items-center gap-1 text-[12.5px] font-bold text-white underline underline-offset-2"
              >
                <RotateCcw size={12} />
                Undo
              </button>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Card stack */}
      <div ref={containerRef} className="relative flex-1 px-3 pb-2 pt-[68px]">
        {behind
          .map((s, i) => (
            <div
              key={s.experience.id}
              aria-hidden
              className="absolute inset-x-3 top-[68px] bottom-2 origin-top"
              style={{
                transform: `scale(${1 - (i + 1) * 0.04}) translateY(${(i + 1) * 8}px)`,
                zIndex: 1 - i,
              }}
            >
              <div className="h-full w-full overflow-hidden rounded-[28px] bg-night/90 shadow-lg" />
            </div>
          ))
          .reverse()}

        <AnimatePresence mode="popLayout" initial={false}>
          <motion.div
            key={top.experience.id}
            className="deck-card absolute inset-x-3 top-[68px] bottom-2 z-10 cursor-grab touch-none active:cursor-grabbing"
            style={{ x, y, rotate }}
            drag
            dragElastic={0.55}
            dragConstraints={{ left: 0, right: 0, top: 0, bottom: 0 }}
            onDragEnd={onDragEnd}
            initial={{ scale: 0.96, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{
              x: exitDir === "right" ? 460 : exitDir === "left" ? -460 : 0,
              y: exitDir === "up" ? -560 : 0,
              rotate: exitDir === "right" ? 16 : exitDir === "left" ? -16 : 0,
              opacity: 0,
              transition: { duration: 0.28, ease: [0.22, 1, 0.36, 1] },
            }}
            transition={{ type: "spring", stiffness: 460, damping: 40 }}
            role="button"
            tabIndex={0}
            aria-label={`${top.experience.name}. ${top.headline}. ${
              top.experience.priceYen === 0 ? "Free" : `¥${top.experience.priceYen}`
            }. Press Enter for details, arrow right to save, arrow left to pass, arrow up to add to itinerary.`}
            onClick={() => openDetail(top.experience.id)}
            onKeyDown={(e) => {
              if (e.key === " ") {
                e.preventDefault();
                openDetail(top.experience.id);
              }
            }}
          >
            <DeckCard scored={top} />

            {/* Direction wash */}
            <motion.div
              className="pointer-events-none absolute inset-0 rounded-[28px] bg-accent"
              style={{ opacity: saveWash }}
              aria-hidden
            />
            <motion.div
              className="pointer-events-none absolute inset-0 rounded-[28px] bg-slate-500"
              style={{ opacity: passWash }}
              aria-hidden
            />

            {/* Stamps */}
            <motion.span
              style={{ opacity: saveOpacity }}
              aria-hidden
              className="pointer-events-none absolute left-5 top-20 -rotate-[14deg] rounded-lg border-[3px] border-accent px-3 py-1.5 text-[22px] font-black tracking-wider text-accent"
            >
              SAVE
            </motion.span>
            <motion.span
              style={{ opacity: passOpacity }}
              aria-hidden
              className="pointer-events-none absolute right-5 top-20 rotate-[14deg] rounded-lg border-[3px] border-white/80 px-3 py-1.5 text-[22px] font-black tracking-wider text-white/80"
            >
              PASS
            </motion.span>
          </motion.div>
        </AnimatePresence>
      </div>

      {/* Action row */}
      <div className="flex items-center justify-center gap-4 px-5 pb-3 pt-1">
        <IconButton diameter={56} tone="outline" label="Pass" onClick={() => act("left")}>
          <X size={24} strokeWidth={2.4} />
        </IconButton>
        <IconButton diameter={56} tone="accent" label="Save" onClick={() => act("right")}>
          <Bookmark size={22} />
        </IconButton>
        <IconButton diameter={64} tone="ink" label="Add to itinerary" onClick={() => act("up")}>
          <CalendarPlus size={26} />
        </IconButton>
        <IconButton
          diameter={48}
          tone="outline"
          label="Share"
          className="text-ink-faint"
          onClick={async () => {
            const r = await shareExperience(top.experience);
            if (r === "copied") toast({ message: "Link copied to clipboard" });
          }}
        >
          <Share2 size={18} />
        </IconButton>
      </div>

      <p className="hidden pb-2 text-center text-[11px] text-ink-faint lg:block">
        ← pass · → save · ↑ itinerary · Enter details · Z undo
      </p>
    </div>
  );
}

function DeckSkeleton() {
  return (
    <div className="relative flex-1 px-3 pb-2 pt-[68px]">
      {[2, 1, 0].map((i) => (
        <div
          key={i}
          className="absolute inset-x-3 top-[68px] bottom-2"
          style={{ transform: `scale(${1 - i * 0.04}) translateY(${i * 8}px)`, zIndex: 3 - i }}
        >
          <div className="h-full w-full overflow-hidden rounded-[28px] bg-night">
            {i === 0 && (
              <div className="flex h-full flex-col justify-end gap-3 p-5">
                <Skeleton className="h-6 w-40 rounded-full" />
                <Skeleton className="h-8 w-full" />
                <Skeleton className="h-8 w-3/5" />
                <Skeleton className="h-4 w-2/5" />
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
