"use client";

import { createRoot } from "react-dom/client";
import { AppStoreProvider } from "@/store/AppStore";
import { UIStoreProvider } from "@/store/UIStore";
import { Toaster } from "@/components/ui/Toaster";
import SplashPage from "@/app/page";
import OnboardingPage from "@/app/onboarding/page";
import TabsLayout from "@/app/(tabs)/layout";
import ExplorePage from "@/app/(tabs)/explore/page";
import SavedPage from "@/app/(tabs)/saved/page";
import ItineraryPage from "@/app/(tabs)/itinerary/page";
import ProfilePage from "@/app/(tabs)/profile/page";
import { usePathname } from "./next-shim";

/**
 * Entry point for the single-file preview build.
 *
 * Mirrors `app/layout.tsx` and the App Router's file-based routing, but
 * compiles from the same screen components so the preview cannot drift from
 * the real app. Only routing and font loading differ.
 */

const TAB_ROUTES: Record<string, () => React.JSX.Element> = {
  "/explore": ExplorePage,
  "/saved": SavedPage,
  "/itinerary": ItineraryPage,
  "/profile": ProfilePage,
};

function Routes() {
  const pathname = usePathname();

  if (pathname === "/onboarding") return <OnboardingPage />;

  const Tab = TAB_ROUTES[pathname];
  if (Tab) {
    return (
      <TabsLayout>
        <Tab />
      </TabsLayout>
    );
  }

  return <SplashPage />;
}

function App() {
  return (
    <AppStoreProvider>
      <UIStoreProvider>
        <div className="relative flex min-h-dvh justify-center bg-night">
          <div
            aria-hidden
            className="pointer-events-none fixed inset-0 hidden lg:block"
            style={{
              background:
                "radial-gradient(900px 600px at 22% 12%, rgba(217,79,61,0.16), transparent 60%), radial-gradient(760px 620px at 82% 82%, rgba(64,86,120,0.20), transparent 62%)",
            }}
          />
          <main className="relative flex min-h-dvh w-full max-w-[480px] flex-col bg-base shadow-[0_0_80px_-20px_rgba(0,0,0,0.8)]">
            <Routes />
          </main>
        </div>
        <Toaster />
      </UIStoreProvider>
    </AppStoreProvider>
  );
}

const container = document.getElementById("root");
if (container) createRoot(container).render(<App />);
