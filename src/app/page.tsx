"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import { ArrowRight } from "lucide-react";
import { useApp } from "@/store/AppStore";
import { demoProfile } from "@/lib/storage";
import { Button } from "@/components/ui/primitives";

export default function SplashPage() {
  const router = useRouter();
  const { hydrated, profile, completeOnboarding } = useApp();

  /* Returning travellers skip straight to the feed. */
  useEffect(() => {
    if (hydrated && profile.onboardingComplete) router.replace("/explore");
  }, [hydrated, profile.onboardingComplete, router]);

  function useDemoTrip() {
    completeOnboarding(demoProfile());
    router.push("/explore");
  }

  return (
    <div className="relative flex min-h-dvh flex-col overflow-hidden bg-[#f3ece4]">
      {/* Dawn gradient ground */}
      <div
        aria-hidden
        className="absolute inset-0"
        style={{
          background:
            "linear-gradient(170deg, #f7e9dd 0%, #f0d9cc 32%, #e4bfb6 58%, #c98f8a 82%, #a06a6b 100%)",
        }}
      />
      <div
        aria-hidden
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(520px 420px at 76% 18%, rgba(255,231,190,0.85), transparent 66%), radial-gradient(680px 520px at 12% 88%, rgba(217,79,61,0.28), transparent 62%)",
        }}
      />

      <div className="relative flex flex-1 flex-col justify-between px-7 pb-10 pt-[max(64px,env(safe-area-inset-top))]">
        <motion.div
          initial={{ opacity: 0, y: 14 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
        >
          <p className="label-xs text-ink/45">Tokyo · Kyoto · Osaka</p>
        </motion.div>

        <div className="flex flex-1 flex-col justify-center">
          <motion.h1
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.08, ease: [0.22, 1, 0.36, 1] }}
            className="font-display text-[64px] leading-[0.94] tracking-[-0.03em] text-ink"
          >
            Meguri
          </motion.h1>
          <motion.p
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.16, ease: [0.22, 1, 0.36, 1] }}
            className="mt-4 max-w-[300px] text-[17px] leading-relaxed text-ink/70"
          >
            Find what locals are actually doing this week — then turn it into a plan
            that fits your days.
          </motion.p>
        </div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.26, ease: [0.22, 1, 0.36, 1] }}
          className="flex flex-col items-center gap-3"
        >
          <Button
            size="lg"
            full
            onClick={() => router.push("/onboarding")}
            disabled={!hydrated}
            className="shadow-[0_12px_40px_-12px_rgba(20,18,16,0.6)]"
          >
            Get started
            <ArrowRight size={18} />
          </Button>
          <button
            onClick={useDemoTrip}
            disabled={!hydrated}
            className="py-2 text-[14px] font-medium text-ink/55 underline underline-offset-4 transition-colors hover:text-ink disabled:opacity-40"
          >
            I already have a trip
          </button>
        </motion.div>
      </div>
    </div>
  );
}
