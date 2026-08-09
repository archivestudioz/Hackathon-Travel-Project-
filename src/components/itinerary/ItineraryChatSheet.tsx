"use client";

import { useRef, useState } from "react";
import { Send, Sparkles, Undo2 } from "lucide-react";
import { useApp } from "@/store/AppStore";
import { useUI } from "@/store/UIStore";
import { interpret, type AiAction } from "@/lib/ai";
import { Sheet } from "@/components/ui/Sheet";
import { Button } from "@/components/ui/primitives";
import { VoiceInput } from "@/components/onboarding/VoiceInput";
import { cn } from "@/lib/cn";

interface Message {
  id: number;
  role: "user" | "assistant";
  text: string;
  action?: AiAction;
  previewTitle?: string;
  previewDetail?: string;
  applied?: boolean;
}

const SUGGESTIONS = [
  "Make day 2 lighter",
  "Move the food crawl to Friday",
  "Add something free on Thursday",
];

export function ItineraryChatSheet() {
  const { chatOpen, setChatOpen, toast } = useUI();
  const { state, profile, ranked, updateEntry, removeEntry, addToItinerary } = useApp();
  const [messages, setMessages] = useState<Message[]>([
    {
      id: 0,
      role: "assistant",
      text: "I can move things around, thin out a busy day, or find something free to fill a gap. What needs changing?",
    },
  ]);
  const [input, setInput] = useState("");
  const counter = useRef(1);
  const scrollRef = useRef<HTMLDivElement>(null);

  function send(text: string) {
    const trimmed = text.trim();
    if (!trimmed) return;
    const result = interpret(trimmed, { itinerary: state.itinerary, profile, ranked });
    setMessages((m) => [
      ...m,
      { id: counter.current++, role: "user", text: trimmed },
      {
        id: counter.current++,
        role: "assistant",
        text: result.reply,
        action: result.action,
        previewTitle: result.previewTitle,
        previewDetail: result.previewDetail,
      },
    ]);
    setInput("");
    window.setTimeout(() => scrollRef.current?.scrollTo({ top: 99999, behavior: "smooth" }), 60);
  }

  function apply(msg: Message) {
    if (!msg.action) return;
    const a = msg.action;
    if (a.kind === "move") updateEntry(a.entryId, { date: a.date, time: a.time });
    if (a.kind === "remove") removeEntry(a.entryId);
    if (a.kind === "add") addToItinerary(a.experienceId, a.date, a.time);
    setMessages((m) => m.map((x) => (x.id === msg.id ? { ...x, applied: true } : x)));
    toast({ message: "Itinerary updated" });
  }

  return (
    <Sheet open={chatOpen} onClose={() => setChatOpen(false)} height="tall" label="Itinerary assistant">
      <div className="flex items-center gap-2 border-b border-line px-5 py-3">
        <Sparkles size={17} className="text-accent" />
        <h2 className="text-[16px] font-semibold text-ink">Edit with the assistant</h2>
      </div>

      <div ref={scrollRef} className="flex-1 space-y-3 overflow-y-auto px-5 py-4 hide-scrollbar">
        {messages.map((m) => (
          <div key={m.id} className={cn("flex", m.role === "user" ? "justify-end" : "justify-start")}>
            <div className={cn("max-w-[82%]", m.role === "user" && "items-end")}>
              <div
                className={cn(
                  "rounded-[18px] px-3.5 py-2.5 text-[14px] leading-snug",
                  m.role === "user"
                    ? "rounded-br-[6px] bg-ink text-white"
                    : "rounded-bl-[6px] border border-line bg-white text-ink",
                )}
              >
                {m.text}
              </div>

              {m.action && (
                <div className="mt-2 rounded-[16px] border border-line bg-accent-soft/60 p-3">
                  <p className="text-[13.5px] font-semibold text-ink">{m.previewTitle}</p>
                  {m.previewDetail && (
                    <p className="mt-0.5 text-[12.5px] text-ink-soft">{m.previewDetail}</p>
                  )}
                  <div className="mt-2.5 flex gap-2">
                    {m.applied ? (
                      <span className="inline-flex items-center gap-1.5 text-[12.5px] font-semibold text-success">
                        <Undo2 size={13} /> Applied
                      </span>
                    ) : (
                      <>
                        <Button size="sm" variant="accent" onClick={() => apply(m)}>
                          Apply
                        </Button>
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() =>
                            setMessages((prev) =>
                              prev.map((x) => (x.id === m.id ? { ...x, action: null } : x)),
                            )
                          }
                        >
                          Dismiss
                        </Button>
                      </>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      <div className="border-t border-line bg-base px-5 pb-[max(12px,env(safe-area-inset-bottom))] pt-3">
        <div className="-mx-5 mb-2.5 flex gap-2 overflow-x-auto hide-scrollbar px-5">
          {SUGGESTIONS.map((s) => (
            <button
              key={s}
              onClick={() => send(s)}
              className="shrink-0 rounded-full border border-line bg-white px-3 py-1.5 text-[12.5px] font-medium text-ink-soft"
            >
              {s}
            </button>
          ))}
        </div>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            send(input);
          }}
          className="flex items-center gap-2"
        >
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Move the tea ceremony to Sunday…"
            aria-label="Message the assistant"
            className="flex-1 rounded-full border border-line bg-white px-4 py-3 text-[14.5px] text-ink outline-none placeholder:text-ink-faint focus:border-accent"
          />
          <VoiceInput size={44} onTranscript={(t) => send(t)} />
          <button
            type="submit"
            aria-label="Send"
            disabled={!input.trim()}
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-ink text-white disabled:opacity-30"
          >
            <Send size={17} />
          </button>
        </form>
      </div>
    </Sheet>
  );
}
