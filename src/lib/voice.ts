"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Speech-to-text for the "tell us more" step and the itinerary chat.
 *
 * The demo uses the browser's built-in SpeechRecognition so it works with no
 * API keys and no network round-trip. To swap in ElevenLabs Scribe (or any
 * hosted STT), implement `transcribeBlob` below against your endpoint and
 * record with MediaRecorder instead — the hook's public shape stays the same,
 * so `VoiceInput` and the chat composer need no changes.
 *
 *   const form = new FormData();
 *   form.append("file", blob);
 *   const res = await fetch("/api/transcribe", { method: "POST", body: form });
 *   const { text } = await res.json();
 *
 * Where speech is unavailable the UI must stay usable by typing — every caller
 * checks `supported` and shows a hint rather than a dead microphone.
 */

type SpeechRecognitionLike = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  start: () => void;
  stop: () => void;
  abort: () => void;
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null;
  onerror: ((e: { error?: string }) => void) | null;
  onend: (() => void) | null;
};

type SpeechCtor = new () => SpeechRecognitionLike;

function getRecognitionCtor(): SpeechCtor | null {
  if (typeof window === "undefined") return null;
  const w = window as unknown as {
    SpeechRecognition?: SpeechCtor;
    webkitSpeechRecognition?: SpeechCtor;
  };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

export interface VoiceState {
  supported: boolean;
  listening: boolean;
  /** Live transcript for the current utterance. */
  transcript: string;
  error: string | null;
  start: () => void;
  stop: () => void;
}

export function useVoiceInput(onFinal: (text: string) => void): VoiceState {
  const [supported, setSupported] = useState(false);
  const [listening, setListening] = useState(false);
  const [transcript, setTranscript] = useState("");
  const [error, setError] = useState<string | null>(null);
  const recRef = useRef<SpeechRecognitionLike | null>(null);
  const finalRef = useRef(onFinal);
  finalRef.current = onFinal;

  useEffect(() => {
    setSupported(getRecognitionCtor() !== null);
    return () => recRef.current?.abort();
  }, []);

  const stop = useCallback(() => {
    recRef.current?.stop();
    setListening(false);
  }, []);

  const start = useCallback(() => {
    const Ctor = getRecognitionCtor();
    if (!Ctor) {
      setError("Voice unavailable — type instead");
      return;
    }
    try {
      const rec = new Ctor();
      recRef.current = rec;
      rec.lang = "en-US";
      rec.continuous = false;
      rec.interimResults = true;
      setTranscript("");
      setError(null);

      rec.onresult = (e) => {
        let text = "";
        for (let i = 0; i < e.results.length; i++) text += e.results[i][0].transcript;
        setTranscript(text);
      };
      rec.onerror = (e) => {
        setError(
          e.error === "not-allowed"
            ? "Microphone blocked — type instead"
            : "Voice unavailable — type instead",
        );
        setListening(false);
      };
      rec.onend = () => {
        setListening(false);
        setTranscript((t) => {
          if (t.trim()) finalRef.current(t.trim());
          return "";
        });
      };

      rec.start();
      setListening(true);
    } catch {
      setError("Voice unavailable — type instead");
      setListening(false);
    }
  }, []);

  return { supported, listening, transcript, error, start, stop };
}
