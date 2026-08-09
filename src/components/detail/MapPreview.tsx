"use client";

import { MapPin, Navigation } from "lucide-react";
import type { Experience } from "@/lib/types";
import { cn } from "@/lib/cn";

/**
 * Location preview.
 *
 * With no maps key configured this renders a labelled schematic rather than a
 * grey box — the pin, the neighbourhood and the directions action all still
 * work. Set NEXT_PUBLIC_MAPS_EMBED_KEY and this swaps to a real embed.
 */
export function MapPreview({
  experience,
  className,
  height = 168,
}: {
  experience: Experience;
  className?: string;
  height?: number;
}) {
  const key = process.env.NEXT_PUBLIC_MAPS_EMBED_KEY;
  const directionsUrl = `https://www.google.com/maps/dir/?api=1&destination=${experience.lat},${experience.lng}`;

  if (key) {
    return (
      <iframe
        title={`Map of ${experience.venue}`}
        className={cn("w-full rounded-[18px] border border-line", className)}
        style={{ height }}
        loading="lazy"
        src={`https://www.google.com/maps/embed/v1/place?key=${key}&q=${experience.lat},${experience.lng}`}
      />
    );
  }

  return (
    <div
      className={cn("relative overflow-hidden rounded-[18px] border border-line bg-sand", className)}
      style={{ height }}
    >
      {/* Schematic street grid */}
      <svg className="absolute inset-0 h-full w-full" aria-hidden viewBox="0 0 300 170" preserveAspectRatio="none">
        <rect width="300" height="170" fill="#f2ede5" />
        <g stroke="#e0d8cb" strokeWidth="8">
          <line x1="0" y1="46" x2="300" y2="46" />
          <line x1="0" y1="118" x2="300" y2="118" />
          <line x1="72" y1="0" x2="72" y2="170" />
          <line x1="196" y1="0" x2="196" y2="170" />
        </g>
        <g stroke="#e7e1d8" strokeWidth="3">
          <line x1="0" y1="82" x2="300" y2="82" />
          <line x1="134" y1="0" x2="134" y2="170" />
          <line x1="252" y1="0" x2="252" y2="170" />
        </g>
        <rect x="200" y="122" width="96" height="44" fill="#e4ece2" />
      </svg>

      <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-full">
        <span className="pulse-ring absolute inset-0 rounded-full bg-accent/40" aria-hidden />
        <MapPin size={30} className="relative fill-accent text-white" strokeWidth={1.6} />
      </div>

      <p className="absolute left-3 top-3 rounded-full bg-white/85 px-2 py-1 text-[10px] font-semibold text-ink-soft">
        Map preview
      </p>

      <a
        href={directionsUrl}
        target="_blank"
        rel="noreferrer"
        className="absolute bottom-3 right-3 inline-flex items-center gap-1.5 rounded-full bg-ink px-3 py-2 text-[12px] font-semibold text-white"
      >
        <Navigation size={13} />
        Get directions
      </a>
    </div>
  );
}
