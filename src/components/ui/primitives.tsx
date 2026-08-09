"use client";

import { forwardRef } from "react";
import { Bookmark, Check, Share2, Sparkles } from "lucide-react";
import { cn } from "@/lib/cn";
import { formatCount, formatYen } from "@/lib/format";

/* ------------------------------------------------------------------ */
/* Button                                                              */
/* ------------------------------------------------------------------ */

type ButtonVariant = "primary" | "secondary" | "ghost" | "accent" | "danger";
type ButtonSize = "sm" | "md" | "lg";

const BUTTON_VARIANTS: Record<ButtonVariant, string> = {
  primary: "bg-ink text-white hover:bg-ink/90 active:bg-ink/80",
  secondary: "bg-white text-ink border border-line hover:bg-sand active:bg-sand",
  ghost: "bg-transparent text-ink-soft hover:bg-sand active:bg-sand",
  accent: "bg-accent text-white hover:bg-accent-deep active:bg-accent-deep",
  danger: "bg-transparent text-accent border border-accent/40 hover:bg-accent-soft",
};

const BUTTON_SIZES: Record<ButtonSize, string> = {
  sm: "h-9 px-3.5 text-[13px]",
  md: "h-11 px-5 text-[15px]",
  lg: "h-14 px-6 text-[16px]",
};

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  full?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = "primary", size = "md", full, className, children, ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-full font-semibold",
        "transition-all duration-150 ease-[cubic-bezier(0.22,1,0.36,1)]",
        "active:scale-[0.97] disabled:pointer-events-none disabled:opacity-40",
        BUTTON_VARIANTS[variant],
        BUTTON_SIZES[size],
        full && "w-full",
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  );
});

/* ------------------------------------------------------------------ */
/* Circular icon button (deck actions, floating controls)              */
/* ------------------------------------------------------------------ */

interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /** Diameter in px — the deck uses 48/56/64 to rank the actions. */
  diameter?: number;
  tone?: "outline" | "accent" | "ink" | "glass" | "ghost";
  label: string;
}

const TONES: Record<NonNullable<IconButtonProps["tone"]>, string> = {
  outline: "bg-white text-ink-soft border border-line shadow-sm hover:text-ink",
  accent: "bg-accent text-white shadow-[0_6px_20px_-6px_rgba(217,79,61,0.7)]",
  ink: "bg-ink text-white shadow-[0_8px_24px_-8px_rgba(20,18,16,0.8)]",
  glass: "glass text-white",
  ghost: "bg-transparent text-white/70 hover:text-white",
};

export function IconButton({
  diameter = 56,
  tone = "outline",
  label,
  className,
  children,
  ...rest
}: IconButtonProps) {
  return (
    <button
      aria-label={label}
      title={label}
      style={{ width: diameter, height: diameter }}
      className={cn(
        "inline-flex shrink-0 items-center justify-center rounded-full",
        "transition-all duration-150 ease-[cubic-bezier(0.22,1,0.36,1)]",
        "active:scale-90 disabled:pointer-events-none disabled:opacity-40",
        TONES[tone],
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* Chip                                                                */
/* ------------------------------------------------------------------ */

interface ChipProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  selected?: boolean;
  size?: "sm" | "md";
  as?: "button" | "span";
}

export function Chip({
  selected,
  size = "md",
  as = "button",
  className,
  children,
  ...rest
}: ChipProps) {
  const classes = cn(
    "inline-flex items-center gap-1.5 rounded-full border font-medium whitespace-nowrap",
    "transition-all duration-150 ease-[cubic-bezier(0.22,1,0.36,1)]",
    size === "sm" ? "h-7 px-2.5 text-[12px]" : "h-9 px-3.5 text-[14px]",
    selected
      ? "border-ink bg-ink text-white scale-[1.04]"
      : "border-line bg-white text-ink-soft hover:border-ink/30",
    as === "button" && "active:scale-95",
    className,
  );
  if (as === "span") {
    return <span className={classes}>{children}</span>;
  }
  return (
    <button type="button" aria-pressed={selected} className={classes} {...rest}>
      {children}
    </button>
  );
}

/** Translucent tag chip used over imagery. */
export function OverlayTag({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center rounded-full border border-white/25 bg-white/15 px-2.5 py-1 text-[11px] font-medium text-white/90 backdrop-blur-sm">
      {children}
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Match chip — the "why am I seeing this" element                     */
/* ------------------------------------------------------------------ */

export function MatchChip({
  reason,
  tone = "light",
  className,
}: {
  reason: string;
  tone?: "light" | "dark";
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex max-w-full items-center gap-1.5 rounded-full px-2.5 py-1.5",
        "text-[12px] font-semibold leading-tight",
        tone === "dark"
          ? "border border-white/25 bg-accent/85 text-white backdrop-blur-sm"
          : "bg-accent-soft text-accent-deep",
        className,
      )}
    >
      <Sparkles size={13} className="shrink-0" aria-hidden />
      <span className="truncate">{reason}</span>
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Price                                                               */
/* ------------------------------------------------------------------ */

export function PricePill({
  yen,
  tone = "dark",
  className,
}: {
  yen: number;
  tone?: "light" | "dark";
  className?: string;
}) {
  const free = yen === 0;
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-1 text-[13px] font-bold tabular-nums",
        free
          ? tone === "dark"
            ? "bg-success/90 text-white"
            : "bg-success-soft text-success"
          : tone === "dark"
            ? "bg-white/92 text-ink"
            : "bg-sand text-ink",
        className,
      )}
    >
      {formatYen(yen)}
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Social proof — saves and shares only. No likes, no comments.        */
/* ------------------------------------------------------------------ */

export function SocialProof({
  saves,
  shares,
  tone = "dark",
  className,
}: {
  saves: number;
  shares: number;
  tone?: "light" | "dark";
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex items-center gap-3.5 text-[12px] font-medium tabular-nums",
        tone === "dark" ? "text-white/75" : "text-ink-faint",
        className,
      )}
    >
      <span className="inline-flex items-center gap-1.5">
        <Bookmark size={13} aria-hidden />
        {formatCount(saves)}
        <span className="sr-only">saves</span>
      </span>
      <span className="inline-flex items-center gap-1.5">
        <Share2 size={13} aria-hidden />
        {formatCount(shares)}
        <span className="sr-only">shares</span>
      </span>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Segmented control                                                   */
/* ------------------------------------------------------------------ */

export function Segmented<T extends string>({
  options,
  value,
  onChange,
  className,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
  className?: string;
}) {
  return (
    <div
      role="tablist"
      className={cn("inline-flex rounded-full border border-line bg-sand p-1", className)}
    >
      {options.map((o) => (
        <button
          key={o.value}
          role="tab"
          aria-selected={value === o.value}
          onClick={() => onChange(o.value)}
          className={cn(
            "rounded-full px-4 py-1.5 text-[13px] font-semibold transition-all duration-200",
            value === o.value ? "bg-white text-ink shadow-sm" : "text-ink-soft hover:text-ink",
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Toggle                                                              */
/* ------------------------------------------------------------------ */

export function Toggle({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  label: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex w-full items-center justify-between gap-4 text-left"
    >
      <span className="text-[15px] font-medium text-ink">{label}</span>
      <span
        className={cn(
          "relative h-7 w-12 shrink-0 rounded-full transition-colors duration-200",
          checked ? "bg-accent" : "bg-line",
        )}
      >
        <span
          className={cn(
            "absolute top-1 h-5 w-5 rounded-full bg-white shadow transition-all duration-200 ease-[cubic-bezier(0.22,1,0.36,1)]",
            checked ? "left-6" : "left-1",
          )}
        />
      </span>
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* Skeleton                                                            */
/* ------------------------------------------------------------------ */

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("skeleton rounded-md bg-white/5", className)} />;
}

/* ------------------------------------------------------------------ */
/* Empty state — always ships a real action                            */
/* ------------------------------------------------------------------ */

export function EmptyState({
  icon,
  title,
  body,
  action,
  secondaryAction,
  tone = "light",
}: {
  icon: React.ReactNode;
  title: string;
  body: string;
  action?: { label: string; onClick: () => void };
  secondaryAction?: { label: string; onClick: () => void };
  tone?: "light" | "dark";
}) {
  return (
    <div className="flex flex-col items-center justify-center px-8 py-16 text-center">
      <div
        className={cn(
          "mb-5 flex h-16 w-16 items-center justify-center rounded-full",
          tone === "dark" ? "bg-white/10 text-white/70" : "bg-sand text-ink-faint",
        )}
      >
        {icon}
      </div>
      <h2
        className={cn(
          "font-display text-[24px] leading-tight tracking-tight",
          tone === "dark" ? "text-white" : "text-ink",
        )}
      >
        {title}
      </h2>
      <p
        className={cn(
          "mt-2 max-w-[280px] text-[14px] leading-relaxed",
          tone === "dark" ? "text-white/60" : "text-ink-soft",
        )}
      >
        {body}
      </p>
      {(action || secondaryAction) && (
        <div className="mt-6 flex flex-col items-center gap-2">
          {action && (
            <Button onClick={action.onClick} variant={tone === "dark" ? "accent" : "primary"}>
              {action.label}
            </Button>
          )}
          {secondaryAction && (
            <Button
              variant="ghost"
              onClick={secondaryAction.onClick}
              className={tone === "dark" ? "text-white/70" : undefined}
            >
              {secondaryAction.label}
            </Button>
          )}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Section header                                                      */
/* ------------------------------------------------------------------ */

export function SectionHeader({
  title,
  caption,
  action,
}: {
  title: string;
  caption?: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="mb-3 flex items-end justify-between gap-4 px-5">
      <div>
        <h2 className="font-display text-[22px] leading-tight tracking-tight text-ink">{title}</h2>
        {caption && <p className="mt-0.5 text-[13px] text-ink-soft">{caption}</p>}
      </div>
      {action}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Verified tick                                                       */
/* ------------------------------------------------------------------ */

export function VerifiedTick({ className }: { className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex h-3.5 w-3.5 items-center justify-center rounded-full bg-accent text-white",
        className,
      )}
      title="Verified host"
    >
      <Check size={9} strokeWidth={4} aria-hidden />
      <span className="sr-only">Verified host</span>
    </span>
  );
}
