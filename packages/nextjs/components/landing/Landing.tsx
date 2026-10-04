"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import {
  ArrowRightIcon,
  BeakerIcon,
  BugAntIcon,
  ClockIcon,
  CommandLineIcon,
  CubeTransparentIcon,
  SignalIcon,
  WalletIcon,
} from "@heroicons/react/24/outline";
import { Playground } from "~~/components/landing/Playground";
import { Terminal } from "~~/components/landing/Terminal";
import { CopyButton, MIRROR, REPO_URL, Reveal, SectionHeading, repoFile } from "~~/components/landing/primitives";

const VERIFY_COMMAND =
  "git clone --recurse-submodules https://github.com/Jennycruzy/scaffold-hbar-forklab && cd scaffold-hbar-forklab && bash verify.sh";
const CREATE_COMMAND = "npm create scaffold-hbar@latest my-forklab -- --template jennycruzy/scaffold-hbar-forklab";

/* ------------------------------------------------------------------ */

const Nav = () => (
  <header className="sticky top-0 z-40 border-b border-white/5 bg-[#07090f]/70 backdrop-blur-xl">
    <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3 md:px-6">
      <Link href="/" className="flex items-center gap-2.5">
        <Image src="/Hedera-Icon-White.svg" alt="Hedera" width={28} height={28} />
        <span className="text-lg font-bold tracking-tight text-white">Forklab</span>
        <span className="lp-mono hidden rounded-md bg-white/5 px-1.5 py-0.5 text-[10px] text-[var(--lp-muted)] sm:inline">
          0x16b
        </span>
      </Link>
      <nav className="hidden items-center gap-7 text-sm text-[var(--lp-muted)] md:flex">
        <a className="transition hover:text-white" href="#playground">
          Playground
        </a>
        <a className="transition hover:text-white" href="#why">
          Why Forklab
        </a>
        <a className="transition hover:text-white" href="#how">
          How it works
        </a>
        <a className="transition hover:text-white" href="#verify">
          Verify
        </a>
        <Link className="transition hover:text-white" href="/testnet">
          App
        </Link>
      </nav>
      <a href={REPO_URL} target="_blank" rel="noreferrer" className="lp-btn lp-btn-ghost !px-4 !py-2 text-sm">
        <svg viewBox="0 0 16 16" className="h-4 w-4 fill-current" aria-hidden>
          <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
        </svg>
        GitHub
      </a>
    </div>
  </header>
);

/** Schedules orbiting the 0x16b system contract: the emulator at the centre of a pinned fork. */
const OrbitArt = () => (
  <svg viewBox="0 0 400 400" className="h-full w-full" aria-hidden>
    <defs>
      <radialGradient id="core" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="#b9a2ff" />
        <stop offset="60%" stopColor="#8259ef" />
        <stop offset="100%" stopColor="#3b1fa8" />
      </radialGradient>
    </defs>
    <circle cx="200" cy="200" r="168" fill="none" stroke="rgba(255,255,255,0.06)" strokeDasharray="2 8" />
    <circle cx="200" cy="200" r="118" fill="none" stroke="rgba(255,255,255,0.08)" />
    <g className="lp-orbit">
      {[0, 72, 144, 216, 288].map((angle, i) => {
        const r = 168;
        const x = 200 + r * Math.cos((angle * Math.PI) / 180);
        const y = 200 + r * Math.sin((angle * Math.PI) / 180);
        const color = i === 4 ? "#ff8863" : "#34eeb6";
        return (
          <g key={angle}>
            <circle cx={x} cy={y} r="14" fill="#0d111b" stroke={color} strokeWidth="2" />
            <circle cx={x} cy={y} r="4" fill={color} />
          </g>
        );
      })}
    </g>
    <g className="lp-orbit-reverse">
      {[30, 150, 270].map(angle => {
        const r = 118;
        const x = 200 + r * Math.cos((angle * Math.PI) / 180);
        const y = 200 + r * Math.sin((angle * Math.PI) / 180);
        return (
          <rect
            key={angle}
            x={x - 9}
            y={y - 9}
            width="18"
            height="18"
            rx="5"
            fill="#0d111b"
            stroke="#2d84eb"
            strokeWidth="2"
          />
        );
      })}
    </g>
    <circle className="lp-pulse-ring" cx="200" cy="200" r="52" fill="none" stroke="#8259ef" strokeWidth="2" />
    <circle cx="200" cy="200" r="52" fill="url(#core)" />
    <text
      x="200"
      y="207"
      textAnchor="middle"
      fontFamily="JetBrains Mono, monospace"
      fontSize="20"
      fontWeight="600"
      fill="white"
    >
      0x16b
    </text>
  </svg>
);

const Hero = () => (
  <section className="relative isolate overflow-hidden px-4 pb-20 pt-16 md:px-6 md:pb-28 md:pt-24">
    <div className="lp-grid -z-10" />
    <div className="lp-glow -z-10 left-[-10%] top-[-10%] h-[420px] w-[420px] bg-[#8259ef]" />
    <div
      className="lp-glow -z-10 right-[-8%] top-[20%] h-[360px] w-[360px] bg-[#0031ff]"
      style={{ animationDelay: "-6s" }}
    />

    <div className="mx-auto grid max-w-6xl items-center gap-14 lg:grid-cols-[1.05fr_1fr]">
      <div>
        <Reveal>
          <a
            href="#verify"
            className="mb-7 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-3 py-1.5 text-xs text-white/80 transition hover:bg-white/10"
          >
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[var(--lp-mint)] opacity-75" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-[var(--lp-mint)]" />
            </span>
            Verified on Hedera testnet · check it in about a minute
            <ArrowRightIcon className="h-3 w-3" />
          </a>
        </Reveal>
        <Reveal delay={80}>
          <h1 className="m-0 text-[2.6rem] font-bold leading-[1.05] tracking-tight text-white md:text-6xl lg:text-[4.1rem]">
            Hedera&apos;s Schedule Service, <span className="lp-gradient-text">emulated on real Hedera state.</span>
          </h1>
        </Reveal>
        <Reveal delay={160}>
          <p className="mt-6 max-w-xl text-lg leading-relaxed text-[var(--lp-muted)]">
            Forklab is a Scaffold-HBAR template that installs a HIP-1215 emulator at{" "}
            <span className="lp-mono text-white">0x16b</span> on a pinned mainnet fork.{" "}
            <span className="lp-mono text-white">Forklab.warp(60)</span> runs each due schedule as its payer, with its
            gas limit, Hedera&apos;s fees, and expiry order, against the real SaucerSwap, Supra, and HTS. No mocks.
          </p>
        </Reveal>
        <Reveal delay={240} className="mt-9 flex flex-wrap gap-3">
          <a href="#playground" className="lp-btn lp-btn-primary">
            <CubeTransparentIcon className="h-5 w-5" /> Try the emulator
          </a>
          <a href="#verify" className="lp-btn lp-btn-ghost">
            <CommandLineIcon className="h-5 w-5" /> Verify in a minute
          </a>
        </Reveal>
      </div>

      <Reveal delay={200} className="relative">
        <div className="pointer-events-none absolute -right-10 -top-16 hidden h-[420px] w-[420px] opacity-70 lg:block">
          <OrbitArt />
        </div>
        <div className="relative">
          <Terminal />
        </div>
      </Reveal>
    </div>
  </section>
);

const STATS = [
  { value: "32", unit: "tests · 1.7 s", label: "Offline emulator suite, no network" },
  { value: "1,409,649", unit: "gas", label: "Charged per schedule creation, measured on testnet" },
  { value: "6 / 6", unit: "runs", label: "Scheduled testnet purchases, then the predicted empty-payer stop" },
  { value: "0", unit: "mocks", label: "SaucerSwap, Supra, HTS, and Bonzo are real fork state" },
];

const Stats = () => (
  <section className="border-y border-white/5 bg-white/[0.015] px-4 py-10 md:px-6">
    <div className="mx-auto grid max-w-6xl gap-6 sm:grid-cols-2 lg:grid-cols-4">
      {STATS.map((stat, i) => (
        <Reveal key={stat.label} delay={i * 80}>
          <div className="flex items-baseline gap-2">
            <span className="text-3xl font-bold text-white md:text-4xl">{stat.value}</span>
            <span className="lp-mono text-xs text-[var(--lp-violet)]">{stat.unit}</span>
          </div>
          <p className="m-0 mt-1 text-sm text-[var(--lp-muted)]">{stat.label}</p>
        </Reveal>
      ))}
    </div>
  </section>
);

/* ------------------------------------------------------------------ */

const INCIDENTS = [
  {
    tag: "Incident 1",
    title: "The run that ran out of gas",
    story:
      "Our first testnet vault ran with a 1,500,000 gas limit. The Supra read, the SaucerSwap swap, and the token transfer all worked; then creating the next schedule needed 1,409,649 gas. INSUFFICIENT_GAS reverted the whole run, swap included, and no next run existed.",
    rows: [
      {
        who: "Typical mock",
        verdict: "passes",
        tone: "text-[#b9a2ff]",
        note: "never runs the call, so gas is never spent",
      },
      {
        who: "Forklab",
        verdict: "fails the same way",
        tone: "text-[var(--lp-mint)]",
        note: "test_testnetFailureGasLimitCannotFundRescheduleAndPurchase",
        href: repoFile("packages/foundry/test/fork/RecurringBuyMainnet.t.sol"),
      },
      {
        who: "Hedera testnet",
        verdict: "INSUFFICIENT_GAS",
        tone: "text-[var(--lp-coral)]",
        note: "contract result 1791131482.003931040",
        href: `${MIRROR}/contracts/0.0.10858982/results/1791131482.003931040`,
      },
    ],
    fix: "Fix it drove: the vault now schedules its next run first and guards the purchase, and the emulator charges the measured gas.",
  },
  {
    tag: "Incident 2",
    title: "The vault that ran dry",
    story:
      "Vault 0.0.10861899 bought six times at one HBAR a minute. At the seventh schedule it could not cover the gas reservation. The call never ran, and Hedera still charged it 1,735,120 tinybars.",
    rows: [
      { who: "Typical mock", verdict: "passes", tone: "text-[#b9a2ff]", note: "has no payer balance to run out of" },
      {
        who: "Forklab",
        verdict: "predicts it",
        tone: "text-[var(--lp-mint)]",
        note: "test_vaultRunsTwoBuysThenRunsOutOfHbar",
        href: repoFile("packages/foundry/test/fork/RecurringBuyMainnet.t.sol"),
      },
      {
        who: "Hedera testnet",
        verdict: "INSUFFICIENT_PAYER_BALANCE",
        tone: "text-[var(--lp-coral)]",
        note: "schedule 0.0.10862057",
        href: `${MIRROR}/schedules/0.0.10862057`,
      },
    ],
    fix: "Fix it drove: the emulator reserves gas at the full limit and charges the measured failed-payer fee.",
  },
];

const Incidents = () => (
  <section id="why" className="scroll-mt-20 px-4 py-24 md:px-6">
    <SectionHeading
      eyebrow="Why Forklab"
      title={<>A mock asks &ldquo;was it scheduled?&rdquo; Forklab asks &ldquo;will it run?&rdquo;</>}
    >
      Live testnet showed us two failures. A recording mock passes both. Forklab reproduces both on a mainnet fork, and
      each outcome below links to its test and its testnet record.
    </SectionHeading>
    <div className="mx-auto grid max-w-6xl gap-6 lg:grid-cols-2">
      {INCIDENTS.map((incident, i) => (
        <Reveal key={incident.title} delay={i * 120}>
          <article className="lp-panel flex h-full flex-col p-6 md:p-8">
            <p className="lp-mono m-0 text-[11px] font-semibold uppercase tracking-[0.25em] text-[var(--lp-coral)]">
              {incident.tag}
            </p>
            <h3 className="m-0 mt-2 text-2xl font-bold text-white">{incident.title}</h3>
            <p className="mt-3 text-sm leading-relaxed text-[var(--lp-muted)]">{incident.story}</p>
            <div className="mt-4 divide-y divide-white/5 overflow-hidden rounded-xl border border-white/5">
              {incident.rows.map(row => (
                <div
                  key={row.who}
                  className="grid grid-cols-[7.5rem_1fr] items-center gap-3 bg-black/20 px-4 py-3 text-sm"
                >
                  <span className="text-white/80">{row.who}</span>
                  <span className="min-w-0">
                    <span className={`font-semibold ${row.tone}`}>{row.verdict}</span>
                    <span className="lp-mono block truncate text-[11px] text-[var(--lp-muted)]">
                      {row.href ? (
                        <a href={row.href} target="_blank" rel="noreferrer" className="hover:text-white">
                          {row.note} ↗
                        </a>
                      ) : (
                        row.note
                      )}
                    </span>
                  </span>
                </div>
              ))}
            </div>
            <p className="m-0 mt-5 text-xs leading-relaxed text-white/60">{incident.fix}</p>
          </article>
        </Reveal>
      ))}
    </div>

    <Reveal className="mx-auto mt-10 max-w-6xl">
      <div className="lp-panel overflow-x-auto">
        <table className="w-full min-w-[640px] text-left text-sm">
          <thead>
            <tr className="border-b border-white/5 text-[11px] uppercase tracking-wider text-[var(--lp-muted)]">
              <th className="px-5 py-3 font-semibold">What the test sees</th>
              <th className="px-5 py-3 font-semibold">Typical 0x16b mock</th>
              <th className="px-5 py-3 font-semibold text-[var(--lp-mint)]">Forklab</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {[
              [
                "The scheduled call",
                "Recorded; the test calls the target by hand",
                "Executed at expiry by Forklab.warp, as the payer",
              ],
              ["Gas limit, schedule-creation cost", "Ignored", "Enforced, 1,409,649 gas per creation"],
              ["Payer balance and fees", "Ignored", "Reserved and charged; INSUFFICIENT_PAYER_BALANCE when short"],
              [
                "Expiry order, capacity, delete, signatures",
                "A flag set by hand, if at all",
                "Modelled with Hedera's response codes",
              ],
              ["msg.sender inside the run", "The test contract", "The schedule's payer"],
              ["SaucerSwap, Supra, HTS, Bonzo", "Usually mocked too", "Real contracts and balances at a pinned block"],
            ].map(([what, mock, forklab]) => (
              <tr key={what}>
                <td className="px-5 py-3 text-white/90">{what}</td>
                <td className="px-5 py-3 text-[var(--lp-muted)]">{mock}</td>
                <td className="px-5 py-3 text-white">{forklab}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Reveal>
  </section>
);

/* ------------------------------------------------------------------ */

const TEST_CODE = `function test_scheduledCallRuns() external {
    Forklab.setUp();                 // HSS at 0x16b, HTS at 0x167
    Counter counter = new Counter();
    vm.deal(address(this), 100_000_000); // payer needs HBAR for gas

    (int64 code, address id) = IHederaScheduleService(address(0x16b))
        .scheduleCall(address(counter), block.timestamp + 60,
                      100_000, 0, abi.encodeCall(Counter.increment, ()));

    assertEq(code, 22);              // SUCCESS
    assertEq(Forklab.warp(60), 1);   // one schedule executed
    assertEq(counter.value(), 1);
}`;

const STEPS = [
  {
    icon: ClockIcon,
    title: "Pin real Hedera",
    body: "fork:pin picks a mainnet block whose Mirror Node balance snapshot matches a SaucerSwap pair, so pools, the Supra feed, and token balances agree.",
  },
  {
    icon: CubeTransparentIcon,
    title: "Install the system contracts",
    body: "Forklab.setUp() puts ForklabHss at 0x16b and ForklabHts at 0x167. Association and allowances come from the Mirror Node at the pinned time.",
  },
  {
    icon: ArrowRightIcon,
    title: "Warp and execute",
    body: "Forklab.warp(seconds) runs every due schedule in expiry order, as its payer, with its gas limit and value, then charges Hedera's fees.",
  },
];

const HowItWorks = () => {
  const [tab, setTab] = useState<"test" | "out">("test");
  return (
    <section id="how" className="scroll-mt-20 border-t border-white/5 px-4 py-24 md:px-6">
      <SectionHeading eyebrow="How it works" title="Three calls between you and a real scheduled run">
        Write an ordinary Foundry test. The only new pieces are the system-contract address and a time warp.
      </SectionHeading>
      <div className="mx-auto grid max-w-6xl gap-8 lg:grid-cols-[1fr_1.15fr]">
        <div className="space-y-4">
          {STEPS.map((step, i) => (
            <Reveal key={step.title} delay={i * 100}>
              <div className="lp-panel flex gap-4 p-5">
                <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-[#8259ef] to-[#2d6bff]">
                  <step.icon className="h-5 w-5 text-white" />
                </div>
                <div>
                  <p className="lp-mono m-0 text-[11px] text-[var(--lp-muted)]">0{i + 1}</p>
                  <h3 className="m-0 text-lg font-bold text-white">{step.title}</h3>
                  <p className="m-0 mt-1 text-sm leading-relaxed text-[var(--lp-muted)]">{step.body}</p>
                </div>
              </div>
            </Reveal>
          ))}
        </div>
        <Reveal delay={150}>
          <div className="lp-panel overflow-hidden">
            <div className="flex items-center gap-1 border-b border-white/5 px-3 py-2">
              {(
                [
                  ["test", "FirstScheduledCall.t.sol"],
                  ["out", "forge test"],
                ] as const
              ).map(([id, label]) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => setTab(id)}
                  className={`lp-mono rounded-lg px-3 py-1.5 text-xs transition ${
                    tab === id ? "bg-white/10 text-white" : "text-[var(--lp-muted)] hover:text-white"
                  }`}
                >
                  {label}
                </button>
              ))}
              <a
                href={repoFile("packages/foundry/test/FirstScheduledCall.t.sol")}
                target="_blank"
                rel="noreferrer"
                className="ml-auto text-xs text-[var(--lp-muted)] hover:text-white"
              >
                View on GitHub ↗
              </a>
            </div>
            <pre className="lp-mono m-0 overflow-x-auto bg-transparent p-5 text-[12.5px] leading-relaxed text-white/90">
              {tab === "test" ? (
                TEST_CODE
              ) : (
                <>
                  <span className="text-[var(--lp-muted)]">
                    $ forge test --offline --match-test test_scheduledCallRuns
                  </span>
                  {"\n"}Ran 1 test for test/FirstScheduledCall.t.sol:FirstScheduledCallTest{"\n"}
                  <span className="text-[var(--lp-mint)]">[PASS]</span> test_scheduledCallRuns() (gas: 6749987){"\n"}
                  Suite result: <span className="text-[var(--lp-mint)]">ok</span>. 1 passed; 0 failed; 0 skipped
                </>
              )}
            </pre>
          </div>
        </Reveal>
      </div>
    </section>
  );
};

/* ------------------------------------------------------------------ */

const Verify = () => (
  <section
    id="verify"
    className="relative isolate scroll-mt-20 overflow-hidden border-t border-white/5 px-4 py-24 md:px-6"
  >
    <div className="lp-glow -z-10 left-1/2 top-10 h-[300px] w-[600px] -translate-x-1/2 bg-[#8259ef] opacity-25" />
    <SectionHeading eyebrow="For judges" title="Verify every claim in about a minute">
      Nothing here asks you to trust a screenshot. Each card is either a link to the public Mirror Node or a command you
      can run.
    </SectionHeading>
    <div className="mx-auto grid max-w-6xl gap-5 lg:grid-cols-3">
      <Reveal>
        <div className="lp-panel flex h-full flex-col p-6">
          <p className="lp-mono m-0 text-[11px] font-semibold uppercase tracking-[0.25em] text-[var(--lp-mint)]">
            0 seconds · no install
          </p>
          <h3 className="m-0 mt-2 text-xl font-bold text-white">Read the testnet record</h3>
          <p className="mt-2 flex-1 text-sm leading-relaxed text-[var(--lp-muted)]">
            Vault 0.0.10861899&apos;s scheduled transactions: six SUCCESS, then INSUFFICIENT_PAYER_BALANCE. Every one
            has &quot;scheduled&quot;: true.
          </p>
          <div className="mt-4 flex flex-wrap gap-2">
            <a
              className="lp-btn lp-btn-ghost !py-2 text-sm"
              href={`${MIRROR}/transactions?account.id=0.0.10861899&transactiontype=CONTRACTCALL&order=desc&limit=25`}
              target="_blank"
              rel="noreferrer"
            >
              Mirror Node ↗
            </a>
            <Link className="lp-btn lp-btn-ghost !py-2 text-sm" href="/testnet">
              Live status page
            </Link>
          </div>
        </div>
      </Reveal>
      <Reveal delay={100}>
        <div className="lp-panel flex h-full flex-col p-6 ring-1 ring-[#8259ef]/40">
          <p className="lp-mono m-0 text-[11px] font-semibold uppercase tracking-[0.25em] text-[var(--lp-violet)]">
            ~60 seconds · Foundry v1.5.0
          </p>
          <h3 className="m-0 mt-2 text-xl font-bold text-white">Run verify.sh</h3>
          <p className="mt-2 text-sm leading-relaxed text-[var(--lp-muted)]">
            Offline suite, both incidents reproduced on a mainnet fork, and the testnet record. No wallet, API key, or
            yarn install.
          </p>
          <div className="lp-mono mt-3 flex-1 break-all rounded-xl bg-black/40 p-3 text-[11.5px] leading-relaxed text-white/90">
            {VERIFY_COMMAND}
          </div>
          <div className="mt-4 flex items-center justify-between gap-2">
            <span className="text-[11px] text-[var(--lp-muted)]">Fresh clone: 16 s · first fork run: ~45 s</span>
            <CopyButton text={VERIFY_COMMAND} />
          </div>
        </div>
      </Reveal>
      <Reveal delay={200}>
        <div className="lp-panel flex h-full flex-col p-6">
          <p className="lp-mono m-0 text-[11px] font-semibold uppercase tracking-[0.25em] text-[var(--lp-azure)]">
            A few minutes · Node 20
          </p>
          <h3 className="m-0 mt-2 text-xl font-bold text-white">Start your own project</h3>
          <p className="mt-2 text-sm leading-relaxed text-[var(--lp-muted)]">
            The official Scaffold-HBAR CLI creates a project from this template, with the full fork suite and this UI.
          </p>
          <div className="lp-mono mt-3 flex-1 break-all rounded-xl bg-black/40 p-3 text-[11.5px] leading-relaxed text-white/90">
            {CREATE_COMMAND}
          </div>
          <div className="mt-4 flex items-center justify-end">
            <CopyButton text={CREATE_COMMAND} />
          </div>
        </div>
      </Reveal>
    </div>
  </section>
);

const ROUTES = [
  {
    href: "/testnet",
    icon: SignalIcon,
    title: "Testnet",
    body: "The deployed vault, its schedule, and every scheduled run, live from Hashio and the Mirror Node.",
  },
  {
    href: "/vault",
    icon: WalletIcon,
    title: "Vault",
    body: "Connect a wallet, create your own RecurringBuy from the factory, fund it, and start it.",
  },
  {
    href: "/lab",
    icon: BeakerIcon,
    title: "Lab",
    body: "With yarn fork:mainnet running locally, fast-forward the fork and execute due schedules from the browser.",
  },
  {
    href: "/debug",
    icon: BugAntIcon,
    title: "Debug",
    body: "Scaffold-HBAR's contract console: read and write every function of the deployed contracts.",
  },
];

const Explore = () => (
  <section className="border-t border-white/5 px-4 py-24 md:px-6">
    <SectionHeading eyebrow="Inside the app" title="Go from emulator to a live vault" />
    <div className="mx-auto grid max-w-6xl gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {ROUTES.map((route, i) => (
        <Reveal key={route.href} delay={i * 80}>
          <Link
            href={route.href}
            className="lp-panel group flex h-full flex-col p-5 transition hover:-translate-y-1 hover:border-white/20"
          >
            <route.icon className="h-6 w-6 text-[var(--lp-violet)]" />
            <h3 className="m-0 mt-4 flex items-center gap-2 text-lg font-bold text-white">
              {route.title}
              <ArrowRightIcon className="h-4 w-4 opacity-0 transition group-hover:translate-x-1 group-hover:opacity-100" />
            </h3>
            <p className="m-0 mt-1 text-sm leading-relaxed text-[var(--lp-muted)]">{route.body}</p>
          </Link>
        </Reveal>
      ))}
    </div>
  </section>
);

const Footer = () => (
  <footer className="border-t border-white/5 px-4 py-10 md:px-6">
    <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-[var(--lp-muted)] md:flex-row">
      <div className="flex items-center gap-3">
        <Image src="/Hedera-Wordmark-Lockup-White.svg" alt="Hedera" width={110} height={28} />
        <span>· a Scaffold-HBAR template</span>
      </div>
      <div className="flex gap-6">
        <a className="hover:text-white" href={repoFile("README.md")} target="_blank" rel="noreferrer">
          README
        </a>
        <a className="hover:text-white" href={repoFile("docs/TESTNET_PROOF.md")} target="_blank" rel="noreferrer">
          Testnet proof
        </a>
        <a className="hover:text-white" href={repoFile("docs/VERIFIED.md")} target="_blank" rel="noreferrer">
          Verification log
        </a>
        <a className="hover:text-white" href={REPO_URL} target="_blank" rel="noreferrer">
          GitHub
        </a>
      </div>
    </div>
  </footer>
);

export const Landing = () => (
  <div className="landing">
    <Nav />
    <Hero />
    <Stats />
    <section id="playground" className="scroll-mt-20 px-4 py-24 md:px-6">
      <SectionHeading eyebrow="Interactive emulator" title="Warp the clock. Watch the mock stay green.">
        One vault, three views. Pick a scenario and press warp: the mock records every schedule, Forklab runs it with
        Hedera&apos;s gas and fee rules, and the testnet lane replays what Hedera actually did.
      </SectionHeading>
      <Reveal className="mx-auto max-w-6xl">
        <Playground />
      </Reveal>
    </section>
    <Incidents />
    <HowItWorks />
    <Verify />
    <Explore />
    <Footer />
  </div>
);
