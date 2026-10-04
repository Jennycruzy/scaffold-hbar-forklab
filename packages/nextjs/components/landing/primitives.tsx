"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import { CheckIcon, ClipboardDocumentIcon } from "@heroicons/react/24/outline";

export const REPO_URL = "https://github.com/Jennycruzy/scaffold-hbar-forklab";
export const repoFile = (path: string) => `${REPO_URL}/blob/main/${path}`;
export const MIRROR = "https://testnet.mirrornode.hedera.com/api/v1";

/** Fades its children up the first time they scroll into view. */
export const Reveal = ({
  children,
  className = "",
  delay = 0,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
}) => {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const node = ref.current;
    if (!node) return;
    const observer = new IntersectionObserver(
      entries => {
        if (entries.some(entry => entry.isIntersecting)) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { threshold: 0.12 },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      className={`lp-reveal ${visible ? "lp-in" : ""} ${className}`}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </div>
  );
};

export const CopyButton = ({ text, label = "Copy" }: { text: string; label?: string }) => {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      onClick={() => {
        navigator.clipboard
          ?.writeText(text)
          .then(() => {
            setCopied(true);
            setTimeout(() => setCopied(false), 1600);
          })
          .catch(() => undefined);
      }}
      className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-semibold text-white/80 transition hover:bg-white/10"
      aria-label={`${label}: ${text}`}
    >
      {copied ? (
        <CheckIcon className="h-3.5 w-3.5 text-[var(--lp-mint)]" />
      ) : (
        <ClipboardDocumentIcon className="h-3.5 w-3.5" />
      )}
      {copied ? "Copied" : label}
    </button>
  );
};

export const SectionHeading = ({
  eyebrow,
  title,
  children,
}: {
  eyebrow: string;
  title: ReactNode;
  children?: ReactNode;
}) => (
  <Reveal className="mx-auto mb-12 max-w-3xl text-center">
    <p className="lp-mono mb-3 text-xs font-semibold uppercase tracking-[0.3em] text-[var(--lp-violet)]">{eyebrow}</p>
    <h2 className="m-0 text-3xl font-bold leading-tight text-white md:text-5xl">{title}</h2>
    {children && (
      <p className="mx-auto mt-5 max-w-2xl text-base leading-relaxed text-[var(--lp-muted)] md:text-lg">{children}</p>
    )}
  </Reveal>
);
