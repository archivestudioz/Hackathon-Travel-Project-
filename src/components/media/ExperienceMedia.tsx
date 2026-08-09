"use client";

import { useState } from "react";
import type { MediaAsset } from "@/lib/types";
import { cn } from "@/lib/cn";

/**
 * The single place any experience visual is rendered.
 *
 * The demo ships no imagery: every slot draws a marked placeholder so the
 * layout, typography and contrast can be judged without art. Point a
 * `MediaAsset` at a real file or an official embed URL and only this component
 * changes behaviour — no screen touches the media pipeline directly.
 *
 * We never scrape or rehost third-party video. Instagram and TikTok render
 * through their official embed endpoints, and fall back to the placeholder
 * when no URL is configured or the embed fails to load.
 */

interface Props {
  asset?: MediaAsset;
  /** "hero" shows the caption line; "thumb" is the bare mark. */
  variant?: "hero" | "thumb";
  className?: string;
  /** Optional label override, e.g. "Vertical video". */
  label?: string;
}

function PlaceholderMark({
  variant,
  label,
  alt,
}: {
  variant: "hero" | "thumb";
  label?: string;
  alt?: string;
}) {
  return (
    <div className="absolute inset-0 bg-[#26231f]">
      {/* Corner-to-corner cross marking where the image belongs. */}
      <svg
        className="absolute inset-0 h-full w-full"
        preserveAspectRatio="none"
        viewBox="0 0 100 100"
        aria-hidden="true"
      >
        <rect x="0.5" y="0.5" width="99" height="99" fill="none" stroke="#4a443d" strokeWidth="0.6" />
        <line x1="0" y1="0" x2="100" y2="100" stroke="#4a443d" strokeWidth="0.6" />
        <line x1="100" y1="0" x2="0" y2="100" stroke="#4a443d" strokeWidth="0.6" />
      </svg>

      {variant === "hero" && (
        <div className="absolute inset-0 flex items-center justify-center px-6">
          <div className="rounded-md border border-[#5a534b] bg-[#26231f] px-3 py-2 text-center">
            <p className="label-xs text-[#8b8279]">{label ?? "Image"}</p>
            {alt && (
              <p className="mt-1 max-w-[220px] text-[11px] leading-tight text-[#6f675f]">{alt}</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export function ExperienceMedia({ asset, variant = "hero", className, label }: Props) {
  const [failed, setFailed] = useState(false);

  const showPlaceholder =
    !asset || failed || asset.provider === "placeholder" || !asset.url;

  return (
    <div className={cn("relative h-full w-full overflow-hidden bg-[#26231f]", className)}>
      {showPlaceholder ? (
        <PlaceholderMark variant={variant} label={label} alt={asset?.alt} />
      ) : asset.provider === "video" ? (
        <video
          className="h-full w-full object-cover"
          src={asset.url}
          poster={asset.poster}
          autoPlay
          muted
          loop
          playsInline
          /* A broken video never shows a broken player — it becomes the mark. */
          onError={() => setFailed(true)}
        />
      ) : asset.provider === "photo" ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          className="h-full w-full object-cover"
          src={asset.url}
          alt={asset.alt}
          onError={() => setFailed(true)}
        />
      ) : (
        <iframe
          className="h-full w-full"
          src={asset.url}
          title={asset.alt}
          loading="lazy"
          allow="encrypted-media; picture-in-picture"
          onError={() => setFailed(true)}
        />
      )}

      {asset?.attribution && !showPlaceholder && (
        <p className="absolute bottom-2 right-2 rounded bg-black/50 px-1.5 py-0.5 text-[10px] text-white/80">
          {asset.attribution}
        </p>
      )}
    </div>
  );
}
