"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Bookmark, CalendarDays, Compass, User } from "lucide-react";
import { useApp } from "@/store/AppStore";
import { cn } from "@/lib/cn";

const TABS = [
  { href: "/saved", label: "Saved", Icon: Bookmark },
  { href: "/explore", label: "Explore", Icon: Compass },
  { href: "/itinerary", label: "Itinerary", Icon: CalendarDays },
  { href: "/profile", label: "Profile", Icon: User },
] as const;

export function BottomNav() {
  const pathname = usePathname();
  const { state } = useApp();

  const counts: Record<string, number> = {
    "/saved": state.saved.filter(
      (s) => !state.itinerary.some((e) => e.experienceId === s.experienceId),
    ).length,
    "/itinerary": state.itinerary.length,
  };

  return (
    <nav
      aria-label="Primary"
      className="sticky bottom-0 z-40 border-t border-line/70 glass-light pb-[max(6px,env(safe-area-inset-bottom))]"
    >
      <ul className="flex items-stretch">
        {TABS.map(({ href, label, Icon }) => {
          const active = pathname === href;
          const count = counts[href] ?? 0;
          return (
            <li key={href} className="flex-1">
              <Link
                href={href}
                aria-current={active ? "page" : undefined}
                className="relative flex flex-col items-center gap-1 py-2.5"
              >
                <span
                  className={cn(
                    "absolute top-1 h-1 w-1 rounded-full bg-accent transition-opacity duration-200",
                    active ? "opacity-100" : "opacity-0",
                  )}
                />
                <span className="relative">
                  <Icon
                    size={22}
                    strokeWidth={active ? 2.4 : 1.8}
                    className={cn(
                      "transition-colors duration-200",
                      active ? "text-ink" : "text-ink-faint",
                    )}
                    fill={active ? "currentColor" : "none"}
                    fillOpacity={active ? 0.12 : 0}
                  />
                  {count > 0 && (
                    <span className="absolute -right-2.5 -top-1 min-w-[16px] rounded-full bg-accent px-1 text-center text-[10px] font-bold leading-4 text-white">
                      {count}
                    </span>
                  )}
                </span>
                <span
                  className={cn(
                    "text-[11px] font-semibold transition-colors duration-200",
                    active ? "text-ink" : "text-ink-faint",
                  )}
                >
                  {label}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
