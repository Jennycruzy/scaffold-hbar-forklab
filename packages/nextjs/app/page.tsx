"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { HederaPortalFaucet } from "@scaffold-hbar-ui/components";
import type { NextPage } from "next";
import { BeakerIcon, ClockIcon, ExclamationTriangleIcon, WalletIcon } from "@heroicons/react/24/outline";
import { tinybarToHbar } from "~~/utils/forklab/units";

type Run = {
  transactionId: string;
  consensusTimestamp: string;
  result: string;
  feeTinybars: string;
  hashscan: string;
};

type RecurringBuyStatus = {
  online?: boolean;
  configured?: boolean;
  address?: string;
  running?: boolean;
  stalled?: boolean;
  scheduleId?: string | null;
  scheduleHashscan?: string | null;
  nextRunAt?: number;
  lastRunAt?: number;
  balanceTinybars?: string;
  lastScheduleStatus?: number;
  runs?: Run[];
  message?: string;
};

function formatTime(timestamp?: number) {
  if (!timestamp) return "—";
  return new Date(timestamp * 1_000).toLocaleString();
}

function shortAddress(address?: string) {
  return address ? `${address.slice(0, 8)}…${address.slice(-6)}` : "—";
}

const Home: NextPage = () => {
  const [status, setStatus] = useState<RecurringBuyStatus | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/recurring-buy/status", { cache: "no-store" })
      .then(response => response.json() as Promise<RecurringBuyStatus>)
      .then(value => {
        if (!cancelled) setStatus(value);
      })
      .catch(() => {
        if (!cancelled) setStatus({ online: false, message: "The testnet status endpoint is unavailable." });
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const isOffline = status?.online !== true;
  const badge = isOffline
    ? { className: "badge-warning", label: status?.configured ? "Network unavailable" : "Not configured" }
    : status?.stalled
      ? { className: "badge-error", label: "Stalled" }
      : status?.running
        ? { className: "badge-success", label: "Running" }
        : { className: "badge-ghost", label: "Stopped" };

  return (
    <div className="flex w-full flex-col items-center">
      <section className="hedera-gradient w-full px-5 py-20 text-white dark:bg-hedera-charcoal dark:bg-none">
        <div className="mx-auto max-w-5xl">
          <p className="mb-3 text-sm font-semibold uppercase tracking-[0.28em] text-white/70">Forklab · Hedera</p>
          <h1 className="mb-5 max-w-3xl text-4xl font-bold leading-tight md:text-6xl">
            Real schedule flows, pinned network state, and a vault you can run.
          </h1>
          <p className="mb-8 max-w-2xl text-lg text-white/80">
            Forklab is a testable Hedera environment for recurring HBAR-to-token purchases. It reads real Supra and
            SaucerSwap state, then makes schedule behavior observable locally and on testnet.
          </p>
          <div className="flex flex-wrap gap-3">
            <Link href="/vault" className="btn btn-neutral gap-2">
              Build a vault
            </Link>
            <Link href="/lab" className="btn btn-ghost border border-white/40 text-white hover:bg-white/10">
              Run local lab
            </Link>
          </div>
        </div>
      </section>

      <main className="w-full max-w-5xl px-5 py-10">
        <section className="mb-8 rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <div className="mb-5 flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-[0.2em] text-base-content/50">
                Testnet vault
              </p>
              <h2 className="m-0 text-2xl font-bold">RecurringBuy live status</h2>
            </div>
            <span className={`badge ${badge.className}`}>{badge.label}</span>
          </div>

          {isOffline ? (
            <div className="flex items-start gap-3 rounded-xl bg-base-200 p-4 text-sm">
              <ExclamationTriangleIcon className="mt-0.5 h-5 w-5 shrink-0 text-warning" />
              <div>
                <p className="m-0 font-medium">
                  {status?.configured
                    ? "The testnet vault could not be read right now."
                    : "No live vault is configured yet."}
                </p>
                <p className="m-0 mt-1 text-base-content/65">
                  {status?.message ?? "Set NEXT_PUBLIC_RECURRING_BUY_ADDRESS after the testnet deployment."}
                </p>
              </div>
            </div>
          ) : (
            <>
              <div className="grid gap-4 sm:grid-cols-3">
                <div className="rounded-xl bg-base-200 p-4">
                  <p className="m-0 text-xs uppercase tracking-wide text-base-content/55">Vault</p>
                  <p className="m-0 mt-1 font-mono text-sm">{shortAddress(status?.address)}</p>
                </div>
                <div className="rounded-xl bg-base-200 p-4">
                  <p className="m-0 text-xs uppercase tracking-wide text-base-content/55">Next run</p>
                  <p className="m-0 mt-1 text-sm">{formatTime(status?.nextRunAt)}</p>
                </div>
                <div className="rounded-xl bg-base-200 p-4">
                  <p className="m-0 text-xs uppercase tracking-wide text-base-content/55">Last run</p>
                  <p className="m-0 mt-1 text-sm">{formatTime(status?.lastRunAt)}</p>
                </div>
              </div>
              {status?.stalled && (
                <p className="mt-4 rounded-xl bg-error/10 p-3 text-sm">
                  The last scheduled run passed its expiry without creating the next schedule. See docs/TESTNET_PROOF.md
                  for the recorded cause; the owner must stop and restart the vault.
                </p>
              )}
              <p className="mt-4 text-sm text-base-content/65">
                Last schedule response: <span className="font-mono">{status?.lastScheduleStatus ?? "—"}</span>. Balance:{" "}
                {status?.balanceTinybars ? `${tinybarToHbar(status.balanceTinybars)} HBAR` : "—"}.{" "}
                {status?.scheduleHashscan ? (
                  <a className="link link-primary" href={status.scheduleHashscan} target="_blank" rel="noreferrer">
                    Schedule {status.scheduleId}
                  </a>
                ) : null}
              </p>
              <div className="mt-5">
                <p className="mb-2 text-sm font-semibold">Scheduled runs (Mirror Node)</p>
                {status?.runs?.length ? (
                  <div className="overflow-x-auto">
                    <table className="table table-sm">
                      <thead>
                        <tr>
                          <th>Transaction</th>
                          <th>Consensus</th>
                          <th>Result</th>
                          <th>Fee</th>
                        </tr>
                      </thead>
                      <tbody>
                        {status.runs.map(run => (
                          <tr key={run.consensusTimestamp}>
                            <td>
                              <a
                                className="link link-primary font-mono text-xs"
                                href={run.hashscan}
                                target="_blank"
                                rel="noreferrer"
                              >
                                {run.transactionId}
                              </a>
                            </td>
                            <td className="text-xs">{formatTime(Math.floor(Number(run.consensusTimestamp)))}</td>
                            <td className="font-mono text-xs">{run.result}</td>
                            <td className="text-xs">{tinybarToHbar(run.feeTinybars)} HBAR</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ) : (
                  <p className="m-0 text-sm text-base-content/60">No scheduled run has executed yet.</p>
                )}
              </div>
            </>
          )}
        </section>

        <section className="grid gap-5 md:grid-cols-3">
          <Link
            href="/vault"
            className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          >
            <WalletIcon className="mb-4 h-8 w-8 text-primary" />
            <h2 className="m-0 text-xl font-bold">Build a vault</h2>
            <p className="mt-2 text-sm text-base-content/65">
              Connect HashPack or MetaMask, create a vault, fund it in HBAR, and start or stop its schedule.
            </p>
          </Link>
          <Link
            href="/lab"
            className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          >
            <BeakerIcon className="mb-4 h-8 w-8 text-primary" />
            <h2 className="m-0 text-xl font-bold">Fast-forward locally</h2>
            <p className="mt-2 text-sm text-base-content/65">
              Start the mainnet fork, advance Anvil time, and run due schedule calls with their recorded gas limit.
            </p>
          </Link>
          <div className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
            <ClockIcon className="mb-4 h-8 w-8 text-primary" />
            <h2 className="m-0 text-xl font-bold">One-command start</h2>
            <code className="mt-3 block rounded-lg bg-base-200 p-3 text-xs">yarn fork:mainnet</code>
            <p className="mt-3 text-sm text-base-content/65">
              The local lab keeps live fork state and emulator evidence separate from the deployed testnet vault.
            </p>
          </div>
        </section>

        <section className="mt-8 rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 className="m-0 text-xl font-bold">Need testnet HBAR?</h2>
          <p className="mt-2 text-sm text-base-content/65">
            The deployed vault and your own vault require a funded testnet account.
          </p>
          <div className="mt-4">
            <HederaPortalFaucet variant="link" label="Open portal.hedera.com/faucet" showIcon={false} />
          </div>
        </section>
      </main>
    </div>
  );
};

export default Home;
