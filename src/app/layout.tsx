import type { Metadata, Viewport } from "next";
import { Inter, Instrument_Serif } from "next/font/google";
import "./globals.css";
import { AppStoreProvider } from "@/store/AppStore";
import { UIStoreProvider } from "@/store/UIStore";
import { Toaster } from "@/components/ui/Toaster";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const display = Instrument_Serif({
  subsets: ["latin"],
  weight: "400",
  variable: "--font-display",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Meguri — find what's on in Japan",
  description:
    "A mobile-first discovery app for locally hosted events, festivals and experiences across Tokyo, Kyoto and Osaka — turned into a day-by-day itinerary.",
};

export const viewport: Viewport = {
  themeColor: "#16130f",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${display.variable}`}>
      <body className="antialiased">
        <AppStoreProvider>
          <UIStoreProvider>
            {/* Desktop presentation: the app stays phone-width and centred
                against an ambient ground, so judging on a laptop still reads
                as a mobile product rather than a stretched page. */}
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
                {children}
              </main>
            </div>
            <Toaster />
          </UIStoreProvider>
        </AppStoreProvider>
      </body>
    </html>
  );
}
