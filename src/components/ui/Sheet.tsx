"use client";

import { useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { cn } from "@/lib/cn";

/**
 * Bottom sheet used for detail, scheduling, filters and the AI chat.
 *
 * Sheets sit above the tab shell rather than being routes, so the swipe deck
 * keeps its position and nothing re-fetches when one closes.
 */

interface SheetProps {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
  /** "full" covers the screen (detail), "auto" hugs its content (scheduling). */
  height?: "full" | "auto" | "tall";
  label: string;
  className?: string;
}

export function Sheet({ open, onClose, children, height = "auto", label, className }: SheetProps) {
  /* Escape closes; body scroll locks while a sheet is up. */
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        onClose();
      }
    };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [open, onClose]);

  return (
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-50 flex justify-center" role="dialog" aria-modal="true" aria-label={label}>
          <motion.button
            aria-label="Close"
            className="absolute inset-0 bg-black/55 backdrop-blur-[2px]"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.18 }}
            onClick={onClose}
          />
          <motion.div
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", stiffness: 380, damping: 38, mass: 0.9 }}
            drag={height === "auto" ? "y" : false}
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.4 }}
            onDragEnd={(_, info) => {
              if (info.offset.y > 110 || info.velocity.y > 620) onClose();
            }}
            className={cn(
              "relative mt-auto flex w-full max-w-[480px] flex-col overflow-hidden bg-base",
              height === "full" && "h-full rounded-none",
              height === "tall" && "h-[86vh] rounded-t-[28px]",
              height === "auto" && "max-h-[88vh] rounded-t-[28px]",
              className,
            )}
          >
            {height === "auto" && (
              <div className="flex shrink-0 justify-center pt-3 pb-1">
                <span className="h-1 w-10 rounded-full bg-line" />
              </div>
            )}
            {children}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
}
