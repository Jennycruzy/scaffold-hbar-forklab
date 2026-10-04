"use client";

import { useEffect, useState } from "react";

type Line = { text: string; tone?: "cmd" | "head" | "pass" | "dim" | "ok" };

/** Output from running verify.sh on a fresh clone; the terminal replays it line by line. */
const LINES: Line[] = [
  { text: "$ bash verify.sh", tone: "cmd" },
  { text: "1/3  Offline emulator suite (no network)", tone: "head" },
  { text: "  PASS 32 tests passed, 0 failed (1.70s)", tone: "pass" },
  { text: "2/3  Testnet failures, reproduced on mainnet block 100579000", tone: "head" },
  { text: "  PASS 1.5M gas cannot fund the 1,409,649-gas re-schedule + swap", tone: "pass" },
  { text: "  PASS empty vault → INSUFFICIENT_PAYER_BALANCE, charged 1,735,120 tinybars", tone: "pass" },
  { text: "3/3  Live testnet record for vault 0.0.10861899", tone: "head" },
  { text: "  PASS 6 scheduled runs SUCCESS, then 1 INSUFFICIENT_PAYER_BALANCE", tone: "pass" },
  { text: "All Forklab checks passed.", tone: "ok" },
];

const toneClass: Record<NonNullable<Line["tone"]>, string> = {
  cmd: "text-white",
  head: "text-[#b9a2ff]",
  pass: "text-[var(--lp-text)]",
  dim: "text-[var(--lp-muted)]",
  ok: "text-[var(--lp-mint)] font-semibold",
};

export const Terminal = () => {
  const [shown, setShown] = useState(1);

  useEffect(() => {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) {
      setShown(LINES.length);
      return;
    }
    const timer = setInterval(() => {
      setShown(count => (count >= LINES.length + 6 ? 1 : count + 1));
    }, 650);
    return () => clearInterval(timer);
  }, []);

  const visible = LINES.slice(0, Math.min(shown, LINES.length));

  return (
    <div className="lp-panel relative overflow-hidden shadow-[0_40px_120px_-40px_rgba(130,89,239,0.55)]">
      <div className="flex items-center gap-2 border-b border-white/5 px-4 py-3">
        <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
        <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
        <span className="h-3 w-3 rounded-full bg-[#28c840]" />
        <span className="lp-mono ml-3 text-xs text-[var(--lp-muted)]">scaffold-hbar-forklab — zsh</span>
      </div>
      <div className="lp-mono min-h-[300px] space-y-1.5 px-5 py-5 text-[12.5px] leading-relaxed md:text-[13px]">
        {visible.map((line, i) => (
          <div key={`${i}-${line.text}`} className={`lp-log-in ${toneClass[line.tone ?? "dim"]}`}>
            {line.tone === "pass" ? (
              <>
                <span className="text-[var(--lp-mint)]">{line.text.slice(0, 6)}</span>
                {line.text.slice(6)}
              </>
            ) : (
              line.text
            )}
          </div>
        ))}
        <div className="lp-caret text-[var(--lp-muted)]" aria-hidden />
      </div>
    </div>
  );
};
