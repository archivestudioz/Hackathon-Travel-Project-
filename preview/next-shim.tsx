"use client";

import { useSyncExternalStore } from "react";

/**
 * Hash-router stand-in for `next/navigation`, used only by the single-file
 * preview build (`npm run preview`).
 *
 * esbuild aliases `next/navigation` to this module, so every screen imports
 * `useRouter` / `usePathname` / `useSearchParams` unchanged and the preview
 * compiles from exactly the same source as the real Next app.
 */

function currentUrl(): string {
  if (typeof window === "undefined") return "/";
  const raw = window.location.hash.replace(/^#/, "");
  return raw || "/";
}

const listeners = new Set<() => void>();
let snapshot = typeof window === "undefined" ? "/" : currentUrl();

if (typeof window !== "undefined") {
  window.addEventListener("hashchange", () => {
    snapshot = currentUrl();
    listeners.forEach((l) => l());
  });
}

function subscribe(cb: () => void) {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

function getSnapshot() {
  return snapshot;
}

function getServerSnapshot() {
  return "/";
}

function useUrl(): string {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

export function navigate(url: string, replace = false) {
  const target = `#${url}`;
  if (replace) {
    window.history.replaceState(null, "", target);
    snapshot = currentUrl();
    listeners.forEach((l) => l());
  } else {
    window.location.hash = url;
  }
}

export function useRouter() {
  return {
    push: (url: string) => navigate(url),
    replace: (url: string) => navigate(url, true),
    back: () => window.history.back(),
    forward: () => window.history.forward(),
    refresh: () => {},
    prefetch: () => {},
  };
}

export function usePathname(): string {
  return useUrl().split("?")[0];
}

export function useSearchParams(): URLSearchParams {
  const url = useUrl();
  return new URLSearchParams(url.split("?")[1] ?? "");
}

export function redirect(url: string): never {
  navigate(url, true);
  throw new Error("redirect");
}
