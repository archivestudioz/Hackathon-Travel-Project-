"use client";

import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react";

/**
 * Overlay and toast coordination.
 *
 * Detail and schedule surfaces are rendered as sheets above the tab shell
 * rather than as routes, so the swipe deck keeps its position and the demo
 * never shows a navigation spinner.
 */

export interface ScheduleTarget {
  experienceId: string;
  /** Set when editing an existing itinerary entry rather than adding one. */
  entryId?: string;
}

export interface Toast {
  id: number;
  message: string;
  actionLabel?: string;
  onAction?: () => void;
  tone?: "default" | "success" | "warning";
}

interface UIStoreValue {
  detailId: string | null;
  openDetail: (id: string) => void;
  closeDetail: () => void;

  scheduleTarget: ScheduleTarget | null;
  openSchedule: (target: ScheduleTarget) => void;
  closeSchedule: () => void;

  chatOpen: boolean;
  setChatOpen: (open: boolean) => void;

  filtersOpen: boolean;
  setFiltersOpen: (open: boolean) => void;

  toasts: Toast[];
  toast: (t: Omit<Toast, "id">) => void;
  dismissToast: (id: number) => void;
}

const UIStoreContext = createContext<UIStoreValue | null>(null);

export function UIStoreProvider({ children }: { children: React.ReactNode }) {
  const [detailId, setDetailId] = useState<string | null>(null);
  const [scheduleTarget, setScheduleTarget] = useState<ScheduleTarget | null>(null);
  const [chatOpen, setChatOpen] = useState(false);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  const dismissToast = useCallback((id: number) => {
    setToasts((t) => t.filter((x) => x.id !== id));
  }, []);

  const toast = useCallback(
    (t: Omit<Toast, "id">) => {
      toastId.current += 1;
      const id = toastId.current;
      setToasts((prev) => [...prev.slice(-2), { ...t, id }]);
      window.setTimeout(() => dismissToast(id), 4200);
    },
    [dismissToast],
  );

  const value = useMemo<UIStoreValue>(
    () => ({
      detailId,
      openDetail: setDetailId,
      closeDetail: () => setDetailId(null),
      scheduleTarget,
      openSchedule: setScheduleTarget,
      closeSchedule: () => setScheduleTarget(null),
      chatOpen,
      setChatOpen,
      filtersOpen,
      setFiltersOpen,
      toasts,
      toast,
      dismissToast,
    }),
    [detailId, scheduleTarget, chatOpen, filtersOpen, toasts, toast, dismissToast],
  );

  return <UIStoreContext.Provider value={value}>{children}</UIStoreContext.Provider>;
}

export function useUI(): UIStoreValue {
  const ctx = useContext(UIStoreContext);
  if (!ctx) throw new Error("useUI must be used inside UIStoreProvider");
  return ctx;
}
