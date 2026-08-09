"use client";

import { Mic, Square } from "lucide-react";
import { motion } from "framer-motion";
import { useVoiceInput } from "@/lib/voice";
import { cn } from "@/lib/cn";

/**
 * Microphone that appends dictated text to a field the traveller can still
 * edit. When speech is unavailable the control explains itself instead of
 * silently doing nothing — typing always works.
 */
export function VoiceInput({
  onTranscript,
  size = 56,
  className,
}: {
  onTranscript: (text: string) => void;
  size?: number;
  className?: string;
}) {
  const voice = useVoiceInput(onTranscript);

  return (
    <div className={cn("flex flex-col items-center gap-2", className)}>
      <button
        type="button"
        onClick={() => (voice.listening ? voice.stop() : voice.start())}
        aria-label={voice.listening ? "Stop recording" : "Dictate with your voice"}
        aria-pressed={voice.listening}
        style={{ width: size, height: size }}
        className={cn(
          "relative inline-flex shrink-0 items-center justify-center rounded-full transition-all",
          "active:scale-90",
          voice.listening ? "bg-ink text-white" : "bg-accent text-white",
        )}
      >
        {voice.listening && (
          <span className="pulse-ring absolute inset-0 rounded-full border-2 border-accent" aria-hidden />
        )}
        {voice.listening ? <Square size={18} fill="currentColor" /> : <Mic size={20} />}
      </button>

      {voice.listening && (
        <div className="flex items-end gap-[3px]" aria-hidden>
          {[0, 1, 2, 3, 4].map((i) => (
            <motion.span
              key={i}
              className="w-[3px] rounded-full bg-accent"
              animate={{ height: [6, 18, 9, 22, 7] }}
              transition={{ duration: 0.9, repeat: Infinity, delay: i * 0.08 }}
            />
          ))}
        </div>
      )}

      {(voice.error || (!voice.supported && !voice.listening)) && (
        <p className="max-w-[120px] text-center text-[11px] leading-tight text-ink-faint">
          {voice.error ?? "Voice unavailable — type instead"}
        </p>
      )}

      {voice.listening && voice.transcript && (
        <p className="max-w-[150px] text-center text-[11px] italic text-ink-soft">
          {voice.transcript}
        </p>
      )}
    </div>
  );
}
