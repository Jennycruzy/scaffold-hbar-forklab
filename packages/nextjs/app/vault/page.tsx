"use client";

import { useState } from "react";
import type { NextPage } from "next";
import { type Address, type Hash, isAddress, parseEventLogs, zeroAddress } from "viem";
import { hederaTestnet } from "viem/chains";
import { useAccount, useChainId, usePublicClient, useReadContract, useSwitchChain, useWriteContract } from "wagmi";
import { ArrowPathIcon, CheckCircleIcon, ExclamationTriangleIcon, WalletIcon } from "@heroicons/react/24/outline";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-hbar";
import { recurringBuyAbi, recurringBuyFactoryAbi } from "~~/utils/forklab/recurringBuy";
import { hbarToTinybar, hbarToWeibar, tinybarToHbar } from "~~/utils/forklab/units";

const DEFAULT_SUPRA = "0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917" as Address;
const DEFAULT_ROUTER = "0x0000000000000000000000000000000000004b40" as Address;
const DEFAULT_TOKEN = "0x0000000000000000000000000000000000120f46" as Address;
const TESTNET_CHAIN_ID = hederaTestnet.id;

function envAddress(name: string): Address | undefined {
  const value = process.env[name];
  return value && isAddress(value) ? value : undefined;
}

function toBigInt(value: unknown) {
  if (typeof value === "bigint") return value;
  if (value === undefined || value === null || value === "") return 0n;
  return BigInt(String(value));
}

function shortAddress(address?: string) {
  return address ? `${address.slice(0, 8)}…${address.slice(-6)}` : "—";
}

function hashscan(hash: Hash) {
  return `https://hashscan.io/testnet/transaction/${hash}`;
}

const Vault: NextPage = () => {
  const { address: accountAddress } = useAccount();
  const chainId = useChainId();
  const { switchChainAsync } = useSwitchChain();
  const publicClient = usePublicClient({ chainId: TESTNET_CHAIN_ID });
  const { writeContractAsync, isPending } = useWriteContract();

  const factoryAddress = envAddress("NEXT_PUBLIC_RECURRING_BUY_FACTORY_ADDRESS");
  const configuredVaultAddress = envAddress("NEXT_PUBLIC_RECURRING_BUY_ADDRESS");
  const [vaultAddress, setVaultAddress] = useState<Address | undefined>(configuredVaultAddress);
  const [supra, setSupra] = useState(String(envAddress("NEXT_PUBLIC_RECURRING_BUY_SUPRA") ?? DEFAULT_SUPRA));
  const [router, setRouter] = useState(String(envAddress("NEXT_PUBLIC_RECURRING_BUY_ROUTER") ?? DEFAULT_ROUTER));
  const [tokenOut, setTokenOut] = useState(String(envAddress("NEXT_PUBLIC_RECURRING_BUY_TOKEN_OUT") ?? DEFAULT_TOKEN));
  const [amountHbar, setAmountHbar] = useState("1");
  const [fundHbar, setFundHbar] = useState("2");
  const [withdrawHbar, setWithdrawHbar] = useState("0.1");
  const [interval, setInterval] = useState("3600");
  const [deviation, setDeviation] = useState("500");
  const [priceAge, setPriceAge] = useState("7200");
  const [message, setMessage] = useState<string | null>(null);
  const [lastHash, setLastHash] = useState<Hash | null>(null);

  const readEnabled = Boolean(vaultAddress);
  const { data: running, refetch: refetchRunning } = useReadContract({
    address: vaultAddress ?? zeroAddress,
    abi: recurringBuyAbi,
    functionName: "running",
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: readEnabled },
  });
  const { data: nextRunAt, refetch: refetchNextRunAt } = useReadContract({
    address: vaultAddress ?? zeroAddress,
    abi: recurringBuyAbi,
    functionName: "nextRunAt",
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: readEnabled },
  });
  const { data: hbarBalance, refetch: refetchBalance } = useReadContract({
    address: vaultAddress ?? zeroAddress,
    abi: recurringBuyAbi,
    functionName: "hbarBalance",
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: readEnabled },
  });
  const { data: nextSchedule, refetch: refetchNextSchedule } = useReadContract({
    address: vaultAddress ?? zeroAddress,
    abi: recurringBuyAbi,
    functionName: "nextSchedule",
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: readEnabled },
  });
  const { data: lastScheduleStatus, refetch: refetchLastStatus } = useReadContract({
    address: vaultAddress ?? zeroAddress,
    abi: recurringBuyAbi,
    functionName: "lastScheduleStatus",
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: readEnabled },
  });

  const refreshVault = async () => {
    await Promise.all([
      refetchRunning(),
      refetchNextRunAt(),
      refetchBalance(),
      refetchNextSchedule(),
      refetchLastStatus(),
    ]);
  };

  const requireWalletOnTestnet = async () => {
    if (!accountAddress) throw new Error("Connect HashPack or MetaMask first.");
    if (chainId !== TESTNET_CHAIN_ID) {
      if (!switchChainAsync) throw new Error("Switch the wallet to Hedera Testnet (chain 296).");
      await switchChainAsync({ chainId: TESTNET_CHAIN_ID });
    }
  };

  const waitForReceipt = async (hash: Hash) => {
    setLastHash(hash);
    if (publicClient) await publicClient.waitForTransactionReceipt({ hash });
  };

  const createVault = async () => {
    try {
      await requireWalletOnTestnet();
      if (!factoryAddress)
        throw new Error("No factory is configured. Set NEXT_PUBLIC_RECURRING_BUY_FACTORY_ADDRESS after deployment.");
      if (!isAddress(supra) || !isAddress(router)) throw new Error("Supra and router must be valid EVM addresses.");
      setMessage("Waiting for the vault deployment transaction…");
      const hash = await writeContractAsync({
        address: factoryAddress,
        abi: recurringBuyFactoryAbi,
        functionName: "createVault",
        args: [supra as Address, router as Address],
      });
      setMessage("Vault transaction submitted; waiting for confirmation…");
      if (publicClient) {
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        const events = parseEventLogs({ abi: recurringBuyFactoryAbi, eventName: "VaultCreated", logs: receipt.logs });
        const createdVault = (events[0]?.args as { vault?: Address } | undefined)?.vault;
        if (createdVault) setVaultAddress(createdVault);
      }
      await waitForReceipt(hash);
      setMessage("Vault created. Configure it before funding and starting it.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const configureVault = async () => {
    try {
      await requireWalletOnTestnet();
      if (!vaultAddress) throw new Error("Create or configure a vault address first.");
      if (!isAddress(tokenOut)) throw new Error("Token-out must be a valid EVM address.");
      const hash = await writeContractAsync({
        address: vaultAddress,
        abi: recurringBuyAbi,
        functionName: "configure",
        args: [tokenOut as Address, hbarToTinybar(amountHbar), BigInt(interval), BigInt(deviation), BigInt(priceAge)],
      });
      await waitForReceipt(hash);
      setMessage("Vault configured.");
      await refreshVault();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const fundVault = async () => {
    try {
      await requireWalletOnTestnet();
      if (!vaultAddress) throw new Error("Create or configure a vault address first.");
      const hash = await writeContractAsync({
        address: vaultAddress,
        abi: recurringBuyAbi,
        functionName: "deposit",
        value: hbarToWeibar(fundHbar),
      });
      await waitForReceipt(hash);
      setMessage(`Funded the vault with ${fundHbar} HBAR.`);
      await refreshVault();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const startVault = async () => {
    try {
      await requireWalletOnTestnet();
      if (!vaultAddress) throw new Error("Create or configure a vault address first.");
      const hash = await writeContractAsync({ address: vaultAddress, abi: recurringBuyAbi, functionName: "start" });
      await waitForReceipt(hash);
      setMessage("Vault started; the first schedule is now pending.");
      await refreshVault();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const stopVault = async () => {
    try {
      await requireWalletOnTestnet();
      if (!vaultAddress) throw new Error("Create or configure a vault address first.");
      const hash = await writeContractAsync({ address: vaultAddress, abi: recurringBuyAbi, functionName: "stop" });
      await waitForReceipt(hash);
      setMessage("Vault stopped and its pending schedule was deleted.");
      await refreshVault();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const withdraw = async () => {
    try {
      await requireWalletOnTestnet();
      if (!vaultAddress) throw new Error("Create or configure a vault address first.");
      const hash = await writeContractAsync({
        address: vaultAddress,
        abi: recurringBuyAbi,
        functionName: "withdraw",
        args: [hbarToTinybar(withdrawHbar)],
      });
      await waitForReceipt(hash);
      setMessage(`Withdrew ${withdrawHbar} HBAR. Withdrawals are allowed only while stopped.`);
      await refreshVault();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const balance = tinybarToHbar(toBigInt(hbarBalance));
  const nextRun = toBigInt(nextRunAt);
  const isRunning = Boolean(running);

  return (
    <main className="mx-auto w-full max-w-5xl px-5 py-10">
      <div className="mb-8 flex flex-wrap items-start justify-between gap-5">
        <div>
          <p className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-primary">Testnet control room</p>
          <h1 className="m-0 text-4xl font-bold">Create your RecurringBuy vault</h1>
          <p className="mt-3 max-w-2xl text-base-content/65">
            All HBAR fields are displayed in HBAR. Contract amounts use tinybars; transaction values use JSON-RPC weibar
            units through one shared conversion helper.
          </p>
        </div>
        <RainbowKitCustomConnectButton />
      </div>

      {message && (
        <div className="mb-6 flex items-start gap-3 rounded-xl border border-base-300 bg-base-100 p-4 text-sm shadow-sm">
          {message.includes("created") ||
          message.includes("configured") ||
          message.includes("started") ||
          message.includes("Funded") ? (
            <CheckCircleIcon className="h-5 w-5 shrink-0 text-success" />
          ) : (
            <ExclamationTriangleIcon className="h-5 w-5 shrink-0 text-warning" />
          )}
          <p className="m-0 break-words">{message}</p>
        </div>
      )}

      <section className="mb-6 rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
        <div className="mb-5 flex items-center gap-3">
          <WalletIcon className="h-7 w-7 text-primary" />
          <div>
            <h2 className="m-0 text-xl font-bold">1. Choose the verified integrations</h2>
            <p className="m-0 mt-1 text-sm text-base-content/60">
              Testnet defaults are the addresses used by the fork tests. Change them only when you have verified
              replacements.
            </p>
          </div>
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <label className="form-control">
            <span className="label-text mb-1 text-sm font-medium">Supra push feed</span>
            <input
              className="input input-bordered font-mono text-xs"
              value={supra}
              onChange={event => setSupra(event.target.value)}
            />
          </label>
          <label className="form-control">
            <span className="label-text mb-1 text-sm font-medium">SaucerSwap router</span>
            <input
              className="input input-bordered font-mono text-xs"
              value={router}
              onChange={event => setRouter(event.target.value)}
            />
          </label>
        </div>
        <button className="btn btn-primary mt-5" disabled={isPending || !factoryAddress} onClick={createVault}>
          {isPending ? <ArrowPathIcon className="h-4 w-4 animate-spin" /> : null}
          Create vault
        </button>
        {!factoryAddress && <p className="mt-3 text-sm text-warning">Factory address is not configured yet.</p>}
      </section>

      <section className="mb-6 rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
        <h2 className="m-0 text-xl font-bold">2. Configure the vault</h2>
        <p className="mt-1 text-sm text-base-content/60">
          The owner must configure before starting. The default token is the real testnet SAUCE token used in the fork
          coverage.
        </p>
        <label className="form-control mt-5">
          <span className="label-text mb-1 text-sm font-medium">Token-out address</span>
          <input
            className="input input-bordered font-mono text-xs"
            value={tokenOut}
            onChange={event => setTokenOut(event.target.value)}
          />
        </label>
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <label className="form-control">
            <span className="label-text mb-1 text-sm font-medium">HBAR per run</span>
            <input
              className="input input-bordered"
              inputMode="decimal"
              value={amountHbar}
              onChange={event => setAmountHbar(event.target.value)}
            />
          </label>
          <label className="form-control">
            <span className="label-text mb-1 text-sm font-medium">Interval (seconds)</span>
            <input
              className="input input-bordered"
              inputMode="numeric"
              value={interval}
              onChange={event => setInterval(event.target.value)}
            />
          </label>
          <label className="form-control">
            <span className="label-text mb-1 text-sm font-medium">Max deviation (bps)</span>
            <input
              className="input input-bordered"
              inputMode="numeric"
              value={deviation}
              onChange={event => setDeviation(event.target.value)}
            />
          </label>
          <label className="form-control">
            <span className="label-text mb-1 text-sm font-medium">Max price age (seconds)</span>
            <input
              className="input input-bordered"
              inputMode="numeric"
              value={priceAge}
              onChange={event => setPriceAge(event.target.value)}
            />
          </label>
        </div>
        <button className="btn btn-primary mt-5" disabled={isPending || !vaultAddress} onClick={configureVault}>
          Configure vault
        </button>
      </section>

      <section className="mb-6 grid gap-6 lg:grid-cols-[1fr_0.9fr]">
        <div className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 className="m-0 text-xl font-bold">3. Fund and operate</h2>
          <label className="form-control mt-5">
            <span className="label-text mb-1 text-sm font-medium">Deposit HBAR</span>
            <input
              className="input input-bordered"
              inputMode="decimal"
              value={fundHbar}
              onChange={event => setFundHbar(event.target.value)}
            />
          </label>
          <div className="mt-4 flex flex-wrap gap-3">
            <button className="btn btn-primary" disabled={isPending || !vaultAddress} onClick={fundVault}>
              Fund vault
            </button>
            <button className="btn btn-success" disabled={isPending || !vaultAddress || isRunning} onClick={startVault}>
              Start
            </button>
            <button className="btn btn-warning" disabled={isPending || !vaultAddress || !isRunning} onClick={stopVault}>
              Stop
            </button>
          </div>
          <div className="mt-6 border-t border-base-300 pt-5">
            <label className="form-control">
              <span className="label-text mb-1 text-sm font-medium">Withdraw HBAR while stopped</span>
              <input
                className="input input-bordered"
                inputMode="decimal"
                value={withdrawHbar}
                onChange={event => setWithdrawHbar(event.target.value)}
              />
            </label>
            <button
              className="btn btn-outline mt-3"
              disabled={isPending || !vaultAddress || isRunning}
              onClick={withdraw}
            >
              Withdraw
            </button>
          </div>
        </div>

        <div className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 className="m-0 text-xl font-bold">Vault state</h2>
          <dl className="mt-5 space-y-4 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="text-base-content/60">Address</dt>
              <dd className="m-0 font-mono">{shortAddress(vaultAddress)}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-base-content/60">Running</dt>
              <dd className="m-0">{readEnabled ? (isRunning ? "yes" : "no") : "—"}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-base-content/60">Vault balance</dt>
              <dd className="m-0">{balance} HBAR</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-base-content/60">Next run</dt>
              <dd className="m-0">{nextRun ? new Date(Number(nextRun) * 1_000).toLocaleString() : "—"}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-base-content/60">Schedule</dt>
              <dd className="m-0 max-w-[12rem] truncate font-mono text-xs">
                {nextSchedule ? String(nextSchedule) : "—"}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-base-content/60">Last response</dt>
              <dd className="m-0 font-mono">{lastScheduleStatus === undefined ? "—" : String(lastScheduleStatus)}</dd>
            </div>
          </dl>
          {lastHash && (
            <a
              className="link link-primary mt-6 block text-sm"
              href={hashscan(lastHash)}
              target="_blank"
              rel="noreferrer"
            >
              View latest transaction on Hashscan
            </a>
          )}
        </div>
      </section>

      <p className="text-sm text-base-content/55">
        The config setters are owner-only on each vault. The emulator limit setters are intentionally test-tool controls
        and are not access-controlled on a local fork.
      </p>
    </main>
  );
};

export default Vault;
