"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useUI } from "@/store/UIStore";
import { cn } from "@/lib/cn";

/** Confirmations for actions that move something between screens. */
export function Toaster() {
  const { toasts, dismissToast } = useUI();

  return (
    <div
      className="pointer-events-none fixed inset-x-0 bottom-[86px] z-[60] flex flex-col items-center gap-2 px-4"
      role="status"
      aria-live="polite"
    >
      <AnimatePresence initial={false}>
        {toasts.map((t) => (
          <motion.div
            key={t.id}
            layout
            initial={{ opacity: 0, y: 18, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, scale: 0.96 }}
            transition={{ type: "spring", stiffness: 420, damping: 34 }}
            className={cn(
              "pointer-events-auto flex w-full max-w-[380px] items-center gap-3 rounded-full px-4 py-3 shadow-lg",
              t.tone === "warning" ? "bg-warning text-white" : "bg-ink text-white",
            )}
          >
            <p className="flex-1 text-[13.5px] font-medium leading-tight">{t.message}</p>
            {t.actionLabel && (
              <button
                className="shrink-0 text-[13.5px] font-bold text-white underline underline-offset-2"
                onClick={() => {
                  t.onAction?.();
                  dismissToast(t.id);
                }}
              >
                {t.actionLabel}
              </button>
            )}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}
