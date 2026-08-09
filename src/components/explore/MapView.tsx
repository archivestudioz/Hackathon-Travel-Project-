"use client";

import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import type { ScoredExperience } from "@/lib/types";
import { ListRow } from "@/components/explore/ExperienceCards";
import { EmptyState } from "@/components/ui/primitives";
import { MapPin } from "lucide-react";
import { cn } from "@/lib/cn";

/**
 * Schematic map.
 *
 * Without a maps key this plots real coordinates onto a normalised schematic
 * rather than showing a grey box: pins are positioned by actual lat/lng, are
 * tappable, and the bottom card pages horizontally between them. Set
 * NEXT_PUBLIC_MAPS_EMBED_KEY to swap in a real tile layer.
 */
export function MapView({ items }: { items: ScoredExperience[] }) {
  const [activeIndex, setActiveIndex] = useState(0);

  const pins = useMemo(() => {
    if (items.length === 0) return [];
    const lats = items.map((s) => s.experience.lat);
    const lngs = items.map((s) => s.experience.lng);
    const minLat = Math.min(...lats);
    const maxLat = Math.max(...lats);
    const minLng = Math.min(...lngs);
    const maxLng = Math.max(...lngs);
    const spanLat = Math.max(maxLat - minLat, 0.01);
    const spanLng = Math.max(maxLng - minLng, 0.01);
    return items.map((s, i) => ({
      scored: s,
      index: i,
      /* 8–92% keeps pins clear of the edges. */
      left: 8 + ((s.experience.lng - minLng) / spanLng) * 84,
      top: 92 - ((s.experience.lat - minLat) / spanLat) * 84,
    }));
  }, [items]);

  if (items.length === 0) {
    return (
      <EmptyState
        icon={<MapPin size={24} />}
        title="Nothing to map"
        body="No experiences match your filters, so there's nothing to plot yet."
      />
    );
  }

  const active = items[Math.min(activeIndex, items.length - 1)];

  return (
    <div className="relative flex-1 overflow-hidden">
      {/* Schematic ground */}
      <div className="absolute inset-0 bg-sand">
        <svg className="h-full w-full" aria-hidden preserveAspectRatio="none" viewBox="0 0 100 100">
          <rect width="100" height="100" fill="#f2ede5" />
          <g stroke="#e4ddd0" strokeWidth="2.4">
            <line x1="0" y1="26" x2="100" y2="24" />
            <line x1="0" y1="58" x2="100" y2="61" />
            <line x1="22" y1="0" x2="19" y2="100" />
            <line x1="63" y1="0" x2="67" y2="100" />
          </g>
          <g stroke="#eae4d8" strokeWidth="1.2">
            <line x1="0" y1="42" x2="100" y2="43" />
            <line x1="0" y1="78" x2="100" y2="80" />
            <line x1="42" y1="0" x2="44" y2="100" />
            <line x1="84" y1="0" x2="86" y2="100" />
          </g>
          {/* Park + water blocks for orientation */}
          <rect x="68" y="62" width="26" height="22" fill="#e2ebe0" />
          <path d="M0 88 Q30 82 58 92 L58 100 L0 100 Z" fill="#dfe7ee" />
        </svg>
      </div>

      <p className="absolute left-4 top-4 z-10 rounded-full bg-white/90 px-2.5 py-1 text-[10.5px] font-semibold text-ink-soft">
        Map preview · {items.length} places
      </p>

      {/* Pins */}
      {pins.map((p) => {
        const isActive = p.index === activeIndex;
        return (
          <button
            key={p.scored.experience.id}
            onClick={() => setActiveIndex(p.index)}
            aria-label={p.scored.experience.name}
            aria-pressed={isActive}
            style={{ left: `${p.left}%`, top: `${p.top}%` }}
            className="absolute z-10 -translate-x-1/2 -translate-y-1/2"
          >
            <motion.span
              animate={{ scale: isActive ? 1.15 : 1 }}
              transition={{ type: "spring", stiffness: 400, damping: 26 }}
              className={cn(
                "relative flex h-11 w-11 items-center justify-center rounded-full border-2 shadow-md",
                isActive ? "border-accent bg-white" : "border-white bg-white/90",
              )}
            >
              {/* Circular media slot — a placeholder mark until real media exists. */}
              <span className="relative h-8 w-8 overflow-hidden rounded-full bg-[#26231f]">
                <svg viewBox="0 0 100 100" className="h-full w-full" aria-hidden>
                  <line x1="0" y1="0" x2="100" y2="100" stroke="#4a443d" strokeWidth="6" />
                  <line x1="100" y1="0" x2="0" y2="100" stroke="#4a443d" strokeWidth="6" />
                </svg>
              </span>
              {isActive && (
                <span className="pulse-ring absolute inset-0 rounded-full border-2 border-accent" aria-hidden />
              )}
            </motion.span>
          </button>
        );
      })}

      {/* Paged bottom card */}
      <div className="absolute inset-x-0 bottom-0 z-20 p-3">
        <motion.div
          key={active.experience.id}
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ type: "spring", stiffness: 420, damping: 34 }}
          drag="x"
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.3}
          onDragEnd={(_, info) => {
            if (info.offset.x < -60) setActiveIndex((i) => Math.min(i + 1, items.length - 1));
            if (info.offset.x > 60) setActiveIndex((i) => Math.max(i - 1, 0));
          }}
          className="cursor-grab active:cursor-grabbing"
        >
          <ListRow scored={active} className="shadow-lg" />
        </motion.div>
        <div className="mt-2 flex items-center justify-center gap-2">
          <button
            onClick={() => setActiveIndex((i) => Math.max(i - 1, 0))}
            disabled={activeIndex === 0}
            className="rounded-full bg-white/90 px-3 py-1 text-[12px] font-semibold text-ink disabled:opacity-40"
          >
            Previous
          </button>
          <span className="text-[11px] font-medium text-ink-soft">
            {activeIndex + 1} of {items.length}
          </span>
          <button
            onClick={() => setActiveIndex((i) => Math.min(i + 1, items.length - 1))}
            disabled={activeIndex === items.length - 1}
            className="rounded-full bg-white/90 px-3 py-1 text-[12px] font-semibold text-ink disabled:opacity-40"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  );
}
