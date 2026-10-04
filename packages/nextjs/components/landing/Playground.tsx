"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ArrowPathIcon, ForwardIcon, PauseIcon, PlayIcon } from "@heroicons/react/24/solid";
import { MIRROR, repoFile } from "~~/components/landing/primitives";
import {
  HSS_RULES,
  type Lane,
  type Run,
  type RunKind,
  TINYBARS_PER_HBAR,
  type VaultParams,
  forklabStep,
  formatHbar,
  minimumScheduleGas,
  mockStep,
  newLane,
  successfulRunGas,
} from "~~/utils/forklab/scheduleModel";

type TestnetRun = { consensusTimestamp: string; result: string; feeTinybars: string; hashscan: string };

const HBAR = TINYBARS_PER_HBAR;
const TESTNET_PARAMS: VaultParams = {
  gasLimit: 2_500_000,
  startingBalanceTinybars: 15 * HBAR,
  amountPerBuyTinybars: HBAR,
};

const PRESETS: { id: string; label: string; blurb: string; params: VaultParams }[] = [
  {
    id: "testnet",
    label: "Live testnet vault",
    blurb:
      "The settings vault 0.0.10861899 ran with on Hedera testnet. Compare Forklab's prediction with the real record.",
    params: TESTNET_PARAMS,
  },
  {
    id: "first",
    label: "1.5M gas limit",
    blurb:
      "Our first testnet vault's limit. It ran out of gas creating its next schedule. The vault now schedules first, so here every purchase fails but still pays gas.",
    params: { gasLimit: 1_500_000, startingBalanceTinybars: 15 * HBAR, amountPerBuyTinybars: HBAR },
  },
  {
    id: "below",
    label: "Below schedule cost",
    blurb: `Under ${minimumScheduleGas.toLocaleString()} gas the run cannot create its next schedule: it reverts and the chain stops after one run.`,
    params: { gasLimit: 1_400_000, startingBalanceTinybars: 15 * HBAR, amountPerBuyTinybars: HBAR },
  },
];

const KIND_STYLE: Record<RunKind, { chip: string; label: string; dot: string }> = {
  bought: {
    chip: "bg-[var(--lp-mint)]/15 text-[var(--lp-mint)] ring-[var(--lp-mint)]/40",
    label: "Bought",
    dot: "bg-[var(--lp-mint)]",
  },
  purchaseFailed: {
    chip: "bg-[var(--lp-amber)]/15 text-[var(--lp-amber)] ring-[var(--lp-amber)]/40",
    label: "PurchaseFailed",
    dot: "bg-[var(--lp-amber)]",
  },
  insufficientGas: {
    chip: "bg-[var(--lp-coral)]/15 text-[var(--lp-coral)] ring-[var(--lp-coral)]/40",
    label: "INSUFFICIENT_GAS",
    dot: "bg-[var(--lp-coral)]",
  },
  insufficientPayer: {
    chip: "bg-[var(--lp-coral)]/15 text-[var(--lp-coral)] ring-[var(--lp-coral)]/40",
    label: "INSUFFICIENT_PAYER_BALANCE",
    dot: "bg-[var(--lp-coral)]",
  },
  recorded: { chip: "bg-[#8259ef]/15 text-[#b9a2ff] ring-[#8259ef]/40", label: "Recorded", dot: "bg-[#b9a2ff]" },
};

const PROOF: Record<RunKind, { test: string; file: string }> = {
  bought: {
    test: "test_threeScheduledBuysUseRealSupraAndSaucerSwap",
    file: "packages/foundry/test/fork/RecurringBuyMainnet.t.sol",
  },
  purchaseFailed: {
    test: "test_testnetFailureGasLimitCannotFundRescheduleAndPurchase",
    file: "packages/foundry/test/fork/RecurringBuyMainnet.t.sol",
  },
  insufficientGas: {
    test: "test_scheduleCreationChargesMeasuredHederaGas",
    file: "packages/foundry/test/ForklabHss.t.sol",
  },
  insufficientPayer: {
    test: "test_vaultRunsTwoBuysThenRunsOutOfHbar",
    file: "packages/foundry/test/fork/RecurringBuyMainnet.t.sol",
  },
  recorded: { test: "", file: "" },
};

const sameParams = (a: VaultParams, b: VaultParams) =>
  a.gasLimit === b.gasLimit &&
  a.startingBalanceTinybars === b.startingBalanceTinybars &&
  a.amountPerBuyTinybars === b.amountPerBuyTinybars;

const RunChip = ({ kind, index, href }: { kind: RunKind; index: number; href?: string }) => {
  const style = KIND_STYLE[kind];
  const content = (
    <span
      className={`lp-chip-in lp-mono inline-flex h-9 min-w-9 items-center justify-center rounded-lg px-2 text-[11px] font-semibold ring-1 ${style.chip}`}
      title={`Run ${index}: ${style.label}`}
    >
      {kind === "bought" ? "✓" : kind === "recorded" ? "✓" : kind === "purchaseFailed" ? "!" : "✕"}
      <span className="ml-1 opacity-70">{index}</span>
    </span>
  );
  return href ? (
    <a href={href} target="_blank" rel="noreferrer" className="transition hover:scale-110">
      {content}
    </a>
  ) : (
    content
  );
};

const LaneCard = ({
  title,
  subtitle,
  accent,
  lane,
  startTinybars,
  footer,
  status,
}: {
  title: string;
  subtitle: string;
  accent: string;
  lane: Lane;
  startTinybars: number;
  footer?: React.ReactNode;
  status: { label: string; tone: string };
}) => {
  const bought = lane.runs.filter(run => run.kind === "bought").length;
  const fees = lane.runs.reduce((sum, run) => sum + run.feeTinybars, 0);
  const pct = Math.max(0, Math.min(100, (lane.balanceTinybars / Math.max(startTinybars, 1)) * 100));
  const recent = [...lane.runs].reverse().slice(0, 4);

  return (
    <div className="lp-panel flex min-w-0 flex-col p-5">
      <div className="mb-4 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className={`h-2.5 w-2.5 rounded-full ${accent}`} />
            <h3 className="m-0 text-base font-bold text-white">{title}</h3>
          </div>
          <p className="m-0 mt-1 text-xs text-[var(--lp-muted)]">{subtitle}</p>
        </div>
        <span
          className={`lp-mono shrink-0 rounded-full px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wider ${status.tone}`}
        >
          {status.label}
        </span>
      </div>

      <div className="mb-1 flex items-baseline justify-between">
        <span className="text-xs text-[var(--lp-muted)]">Payer balance</span>
        <span className="lp-mono text-sm text-white">{formatHbar(lane.balanceTinybars)} ℏ</span>
      </div>
      <div className="mb-4 h-2 overflow-hidden rounded-full bg-white/5">
        <div
          className="h-full rounded-full bg-gradient-to-r from-[#8259ef] to-[#2d84eb] transition-[width] duration-700 ease-out"
          style={{ width: `${pct}%` }}
        />
      </div>

      <div className="mb-4 grid grid-cols-3 gap-2 text-center">
        {[
          ["Runs", lane.runs.length.toString()],
          ["Purchases", bought.toString()],
          ["Fees", `${formatHbar(fees, 2)} ℏ`],
        ].map(([label, value]) => (
          <div key={label} className="rounded-xl bg-white/[0.03] px-2 py-2">
            <div className="lp-mono text-sm font-semibold text-white">{value}</div>
            <div className="text-[10px] uppercase tracking-wider text-[var(--lp-muted)]">{label}</div>
          </div>
        ))}
      </div>

      <div className="mb-4 flex min-h-[2.5rem] flex-wrap gap-1.5">
        {lane.runs.length === 0 ? (
          <span className="text-xs text-[var(--lp-muted)]">Press Warp to run the first schedule.</span>
        ) : (
          lane.runs.map(run => <RunChip key={run.index} kind={run.kind} index={run.index} />)
        )}
      </div>

      <div className="lp-mono flex-1 space-y-2 rounded-xl bg-black/30 p-3 text-[11px] leading-relaxed">
        {recent.length === 0 && <div className="text-[var(--lp-muted)]">waiting for warp…</div>}
        {recent.map(run => (
          <div key={run.index} className="lp-log-in flex gap-2">
            <span className={`mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full ${KIND_STYLE[run.kind].dot}`} />
            <span className="text-[var(--lp-muted)]">
              <span className="text-white/80">t+{run.at}s</span> {run.detail}
            </span>
          </div>
        ))}
      </div>
      {footer && <div className="mt-3 text-[11px] text-[var(--lp-muted)]">{footer}</div>}
    </div>
  );
};

export const Playground = () => {
  const [params, setParams] = useState<VaultParams>(TESTNET_PARAMS);
  const [lanes, setLanes] = useState(() => ({ mock: newLane(TESTNET_PARAMS), forklab: newLane(TESTNET_PARAMS) }));
  const { mock, forklab } = lanes;
  const [playing, setPlaying] = useState(false);
  const [testnetRuns, setTestnetRuns] = useState<TestnetRun[] | null>(null);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    fetch("/api/recurring-buy/status", { cache: "no-store" })
      .then(response => response.json())
      .then((value: { runs?: TestnetRun[] }) => setTestnetRuns([...(value.runs ?? [])].reverse()))
      .catch(() => setTestnetRuns([]));
  }, []);

  const reset = useCallback((next: VaultParams) => {
    setPlaying(false);
    setParams(next);
    setLanes({ mock: newLane(next), forklab: newLane(next) });
  }, []);

  const warp = useCallback(() => {
    // Both lanes advance together; the mock never stops, so the Forklab lane decides when the clock ends.
    setLanes(current =>
      current.forklab.ended
        ? current
        : { mock: mockStep(current.mock, params), forklab: forklabStep(current.forklab, params) },
    );
  }, [params]);

  useEffect(() => {
    if (!playing) return;
    timer.current = setInterval(warp, 750);
    return () => {
      if (timer.current) clearInterval(timer.current);
    };
  }, [playing, warp]);

  useEffect(() => {
    if (forklab.ended || forklab.runs.length >= 24) setPlaying(false);
  }, [forklab]);

  const isTestnetPreset = sameParams(params, TESTNET_PARAMS);
  const testnetLane: Lane = useMemo(() => {
    const runs: Run[] = (testnetRuns ?? []).slice(0, forklab.runs.length).map((run, i) => ({
      index: i + 1,
      at: (i + 1) * 60,
      kind: run.result === "SUCCESS" ? "bought" : "insufficientPayer",
      gasUsed: 0,
      feeTinybars: Number(run.feeTinybars),
      spentTinybars: run.result === "SUCCESS" ? HBAR : 0,
      balanceAfterTinybars: 0,
      chainContinues: run.result === "SUCCESS",
      detail: `${run.result}, fee ${Number(run.feeTinybars).toLocaleString()} tinybars (Mirror Node ${run.consensusTimestamp})`,
    }));
    const spent = runs.reduce((sum, run) => sum + run.feeTinybars + run.spentTinybars, 0);
    return {
      runs,
      balanceTinybars: TESTNET_PARAMS.startingBalanceTinybars - spent,
      ended: runs.some(r => !r.chainContinues),
    };
  }, [testnetRuns, forklab.runs.length]);

  const preset = PRESETS.find(p => sameParams(p.params, params));
  const lastForklab = forklab.runs.at(-1);
  const proof = lastForklab ? PROOF[lastForklab.kind] : null;
  const matches =
    isTestnetPreset &&
    testnetLane.runs.length > 0 &&
    testnetLane.runs.every((run, i) => forklab.runs[i]?.kind === run.kind);

  return (
    <div className="lp-panel overflow-hidden p-0">
      {/* Controls */}
      <div className="grid gap-6 border-b border-white/5 p-5 md:p-7 lg:grid-cols-[1.1fr_1fr]">
        <div>
          <p className="lp-mono mb-3 text-[11px] font-semibold uppercase tracking-[0.25em] text-[var(--lp-muted)]">
            Scenario
          </p>
          <div className="mb-4 flex flex-wrap gap-2">
            {PRESETS.map(p => (
              <button
                key={p.id}
                type="button"
                onClick={() => reset(p.params)}
                className={`rounded-full px-4 py-2 text-sm font-semibold transition ${
                  preset?.id === p.id
                    ? "bg-white text-[#0b0e16]"
                    : "border border-white/15 bg-white/[0.03] text-white/80 hover:bg-white/10"
                }`}
              >
                {p.label}
              </button>
            ))}
          </div>
          <p className="m-0 min-h-[3rem] text-sm leading-relaxed text-[var(--lp-muted)]">
            {preset
              ? preset.blurb
              : "Custom settings. Forklab applies the same rules; the testnet lane compares only with the live-vault settings."}
          </p>
        </div>

        <div className="space-y-4">
          {[
            {
              label: "Gas limit per run",
              value: params.gasLimit,
              min: 1_000_000,
              max: 3_000_000,
              step: 50_000,
              show: params.gasLimit.toLocaleString(),
              set: (v: number) => reset({ ...params, gasLimit: v }),
            },
            {
              label: "Vault balance",
              value: params.startingBalanceTinybars / HBAR,
              min: 1,
              max: 40,
              step: 1,
              show: `${params.startingBalanceTinybars / HBAR} ℏ`,
              set: (v: number) => reset({ ...params, startingBalanceTinybars: v * HBAR }),
            },
            {
              label: "HBAR per purchase",
              value: params.amountPerBuyTinybars / HBAR,
              min: 0.5,
              max: 5,
              step: 0.5,
              show: `${params.amountPerBuyTinybars / HBAR} ℏ`,
              set: (v: number) => reset({ ...params, amountPerBuyTinybars: v * HBAR }),
            },
          ].map(control => (
            <label key={control.label} className="block">
              <span className="mb-1 flex items-baseline justify-between text-xs text-[var(--lp-muted)]">
                {control.label}
                <span className="lp-mono text-sm text-white">{control.show}</span>
              </span>
              <input
                className="lp-range"
                type="range"
                min={control.min}
                max={control.max}
                step={control.step}
                value={control.value}
                onChange={event => control.set(Number(event.target.value))}
              />
            </label>
          ))}
        </div>
      </div>

      {/* Transport */}
      <div className="flex flex-wrap items-center gap-3 border-b border-white/5 bg-black/20 px-5 py-4 md:px-7">
        <button
          type="button"
          onClick={warp}
          disabled={forklab.ended}
          className="lp-btn lp-btn-primary disabled:opacity-40"
        >
          <ForwardIcon className="h-4 w-4" /> Forklab.warp(60)
        </button>
        <button
          type="button"
          onClick={() => setPlaying(p => !p)}
          disabled={forklab.ended}
          className="lp-btn lp-btn-ghost disabled:opacity-40"
        >
          {playing ? <PauseIcon className="h-4 w-4" /> : <PlayIcon className="h-4 w-4" />}
          {playing ? "Pause" : "Run until it stops"}
        </button>
        <button type="button" onClick={() => reset(params)} className="lp-btn lp-btn-ghost">
          <ArrowPathIcon className="h-4 w-4" /> Reset
        </button>
        <span className="lp-mono ml-auto text-xs text-[var(--lp-muted)]">
          clock t+{forklab.runs.length * 60}s · successful run ≈ {successfulRunGas.toLocaleString()} gas
        </span>
      </div>

      {/* Lanes */}
      <div className="grid gap-4 p-5 md:p-7 lg:grid-cols-3">
        <LaneCard
          title="Typical 0x16b mock"
          subtitle="Records scheduleCall; the test runs the target itself"
          accent="bg-[#b9a2ff]"
          lane={mock}
          startTinybars={params.startingBalanceTinybars}
          status={{ label: "always green", tone: "bg-[#8259ef]/15 text-[#b9a2ff]" }}
          footer="No gas limit, fee, payer balance, or expiry is checked, so this lane never fails."
        />
        <LaneCard
          title="Forklab emulator"
          subtitle="Executes as the payer with Hedera's gas and fees"
          accent="bg-[var(--lp-mint)]"
          lane={forklab}
          startTinybars={params.startingBalanceTinybars}
          status={
            forklab.ended
              ? { label: "chain ended", tone: "bg-[var(--lp-coral)]/15 text-[var(--lp-coral)]" }
              : forklab.runs.length
                ? { label: "running", tone: "bg-[var(--lp-mint)]/15 text-[var(--lp-mint)]" }
                : { label: "scheduled", tone: "bg-white/10 text-white/70" }
          }
          footer={
            proof?.test ? (
              <>
                Proven in Solidity:{" "}
                <a
                  className="text-[var(--lp-mint)] underline-offset-2 hover:underline"
                  href={repoFile(proof.file)}
                  target="_blank"
                  rel="noreferrer"
                >
                  {proof.test}
                </a>
              </>
            ) : (
              "Each outcome links to the Solidity test that asserts it."
            )
          }
        />
        <LaneCard
          title="Hedera testnet (live)"
          subtitle="Vault 0.0.10861899, read from the Mirror Node"
          accent="bg-[var(--lp-azure)]"
          lane={isTestnetPreset ? testnetLane : newLane(TESTNET_PARAMS)}
          startTinybars={TESTNET_PARAMS.startingBalanceTinybars}
          status={
            !isTestnetPreset
              ? { label: "other settings", tone: "bg-white/10 text-white/50" }
              : testnetRuns === null
                ? { label: "loading", tone: "bg-white/10 text-white/70" }
                : matches
                  ? { label: "matches Forklab", tone: "bg-[var(--lp-mint)]/15 text-[var(--lp-mint)]" }
                  : { label: "live record", tone: "bg-[var(--lp-azure)]/15 text-[var(--lp-azure)]" }
          }
          footer={
            isTestnetPreset ? (
              <a
                className="text-[var(--lp-azure)] underline-offset-2 hover:underline"
                href={`${MIRROR}/transactions?account.id=0.0.10861899&transactiontype=CONTRACTCALL&order=desc&limit=25`}
                target="_blank"
                rel="noreferrer"
              >
                Open the scheduled transactions on the Mirror Node ↗
              </a>
            ) : (
              "Testnet ran with 15 ℏ, 2,500,000 gas, and 1 ℏ per purchase. Pick “Live testnet vault” to compare."
            )
          }
        />
      </div>

      <p className="m-0 border-t border-white/5 px-5 py-4 text-[11px] leading-relaxed text-[var(--lp-muted)] md:px-7">
        The playground applies the rules of{" "}
        <a
          className="underline-offset-2 hover:underline"
          href={repoFile("packages/foundry/contracts/forklab/ForklabHss.sol")}
          target="_blank"
          rel="noreferrer"
        >
          ForklabHss.sol
        </a>{" "}
        in your browser: {HSS_RULES.scheduleCreateGas.toLocaleString()} gas per schedule creation, a gas reservation at
        the full limit, fees at {HSS_RULES.gasPriceTinybars} tinybars per gas used, and{" "}
        {HSS_RULES.insufficientPayerFeeTinybars.toLocaleString()} tinybars charged to a payer that cannot cover the
        reservation. Purchase gas is calibrated on testnet runs 1 and 2. The Solidity tests are the source of truth; run
        them with <span className="lp-mono text-white/80">bash verify.sh</span>.
      </p>
    </div>
  );
};
