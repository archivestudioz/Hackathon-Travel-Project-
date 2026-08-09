"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useApp } from "@/store/AppStore";
import { BottomNav } from "@/components/nav/BottomNav";
import { EventDetailSheet } from "@/components/detail/EventDetailSheet";
import { ScheduleSheet } from "@/components/schedule/ScheduleSheet";
import { ItineraryChatSheet } from "@/components/itinerary/ItineraryChatSheet";

export default function TabsLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const { hydrated, profile } = useApp();

  /* Anyone landing on a tab without a profile goes back to the start. */
  useEffect(() => {
    if (hydrated && !profile.onboardingComplete) router.replace("/");
  }, [hydrated, profile.onboardingComplete, router]);

  return (
    <div className="flex min-h-dvh flex-col bg-base">
      <div className="flex flex-1 flex-col overflow-hidden">{children}</div>
      <BottomNav />

      {/* Overlays live above the shell so tab state is never lost. */}
      <EventDetailSheet />
      <ScheduleSheet />
      <ItineraryChatSheet />
    </div>
  );
}
