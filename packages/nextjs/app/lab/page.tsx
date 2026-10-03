"use client";

import { useState } from "react";
import type { NextPage } from "next";
import { BeakerIcon, ExclamationTriangleIcon, PlayIcon } from "@heroicons/react/24/outline";

const Lab: NextPage = () => {
  const [seconds, setSeconds] = useState("3600");
  const [result, setResult] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const fastForward = async () => {
    setBusy(true);
    try {
      const response = await fetch("/api/lab/fast-forward", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ seconds: Number(seconds) }),
      });
      setResult(JSON.stringify(await response.json(), null, 2));
    } catch (error) {
      setResult(JSON.stringify({ ok: false, message: String(error) }, null, 2));
    } finally {
      setBusy(false);
    }
  };

  const runDue = async () => {
    setBusy(true);
    try {
      const response = await fetch("/api/lab/run-due", {
        method: "POST",
      });
      setResult(JSON.stringify(await response.json(), null, 2));
    } catch (error) {
      setResult(JSON.stringify({ ok: false, message: String(error) }, null, 2));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="mx-auto w-full max-w-5xl px-5 py-10">
      <div className="mb-8 flex items-start gap-4">
        <BeakerIcon className="mt-1 h-10 w-10 text-primary" />
        <div>
          <p className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-primary">Local mode</p>
          <h1 className="m-0 text-4xl font-bold">Forklab scheduler lab</h1>
          <p className="mt-3 max-w-2xl text-base-content/65">
            Run <code>yarn fork:mainnet</code> first. These controls call Anvil JSON-RPC directly; an unavailable local
            node is shown as an offline state instead of a crash.
          </p>
        </div>
      </div>

      <div className="mb-6 flex items-start gap-3 rounded-xl border border-warning/40 bg-warning/10 p-4 text-sm">
        <ExclamationTriangleIcon className="mt-0.5 h-5 w-5 shrink-0 text-warning" />
        <p className="m-0">
          The runner sends the stored payer, target, calldata, and gas limit to Anvil. It does not invent a schedule
          result if the local forwarder or emulator rejects the call.
        </p>
      </div>

      <section className="grid gap-6 lg:grid-cols-2">
        <div className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 className="m-0 text-xl font-bold">Fast-forward</h2>
          <p className="mt-2 text-sm text-base-content/60">
            Calls <code>evm_increaseTime</code> and then <code>evm_mine</code>.
          </p>
          <label className="form-control mt-5">
            <span className="label-text mb-1 text-sm font-medium">Seconds</span>
            <input
              className="input input-bordered"
              inputMode="numeric"
              value={seconds}
              onChange={event => setSeconds(event.target.value)}
            />
          </label>
          <button className="btn btn-primary mt-4 gap-2" disabled={busy} onClick={fastForward}>
            <PlayIcon className="h-4 w-4" /> Advance local time
          </button>
        </div>

        <div className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 className="m-0 text-xl font-bold">Run due calls</h2>
          <p className="mt-2 text-sm text-base-content/60">
            Discovers pending HSS records, impersonates each due payer, executes its stored call and reads the settled
            status.
          </p>
          <button className="btn btn-primary mt-4 gap-2" disabled={busy} onClick={runDue}>
            <PlayIcon className="h-4 w-4" /> Run due schedules
          </button>
        </div>
      </section>

      <section className="mt-6 rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
        <h2 className="m-0 text-xl font-bold">Runner output</h2>
        <pre className="mt-4 min-h-32 overflow-x-auto rounded-xl bg-base-200 p-4 text-xs">
          {result ?? "No local request yet."}
        </pre>
      </section>
    </main>
  );
};

export default Lab;
