"use client";

import { useState } from "react";
import type { NextPage } from "next";
import { type Address, type Hash, isAddress, parseEventLogs, zeroAddress } from "viem";
import { hederaTestnet } from "viem/chains";
import { useAccount, useChainId, usePublicClient, useReadContract, useSwitchChain, useWriteContract } from "wagmi";
import { ArrowPathIcon, CheckCircleIcon, ExclamationTriangleIcon, WalletIcon } from "@heroicons/react/24/outline";
import { RainbowKitCustomConnectButton } from "~~/components/scaffold-hbar";
import deployedContracts from "~~/contracts/deployedContracts";
import {
  gasReservationTinybars,
  ownerTokenAbi,
  recurringBuyAbi,
  recurringBuyFactoryAbi,
} from "~~/utils/forklab/recurringBuy";
import { hbarToTinybar, hbarToWeibar, tinybarToHbar } from "~~/utils/forklab/units";

const DEFAULT_SUPRA = "0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917" as Address;
const DEFAULT_ROUTER = "0x0000000000000000000000000000000000004b40" as Address;
// USDC Sirio Test (0.0.4385062): the USD-labelled testnet token whose WHBAR pair the live
// proof used. RecurringBuy prices tokenOut at one US dollar, so tokenOut must be USD-pegged.
const DEFAULT_TOKEN = "0x000000000000000000000000000000000042E926" as Address;
const DEFAULT_BONZO_POOL = "0xf67DBe9bD1B331cA379c44b5562EAa1CE831EbC2" as Address;
const TESTNET_CHAIN_ID = hederaTestnet.id;

// Next.js inlines NEXT_PUBLIC_* values only for literal `process.env.NAME` reads,
// so each variable is read explicitly here.
function asAddress(value: string | undefined): Address | undefined {
  return value && isAddress(value) ? value : undefined;
}

const ENV = {
  factory: asAddress(process.env.NEXT_PUBLIC_RECURRING_BUY_FACTORY_ADDRESS),
  vault: asAddress(process.env.NEXT_PUBLIC_RECURRING_BUY_ADDRESS),
  supra: asAddress(process.env.NEXT_PUBLIC_RECURRING_BUY_SUPRA),
  router: asAddress(process.env.NEXT_PUBLIC_RECURRING_BUY_ROUTER),
  tokenOut: asAddress(process.env.NEXT_PUBLIC_RECURRING_BUY_TOKEN_OUT),
  bonzoPool: asAddress(process.env.NEXT_PUBLIC_BONZO_TESTNET_POOL),
};

const testnetDeployments = deployedContracts[296] as Record<string, { address: string } | undefined> | undefined;

function toBigInt(value: unknown) {
  if (typeof value === "bigint") return value;
  if (value === undefined || value === null || value === "") return 0n;
  return BigInt(String(value));
}

function shortAddress(address?: string) {
  return address ? `${address.slice(0, 8)}…${address.slice(-6)}` : "—";
}

const Vault: NextPage = () => {
  const { address: accountAddress } = useAccount();
  const chainId = useChainId();
  const { switchChainAsync } = useSwitchChain();
  const publicClient = usePublicClient({ chainId: TESTNET_CHAIN_ID });
  const { writeContractAsync, isPending } = useWriteContract();

  const factoryAddress = ENV.factory ?? asAddress(testnetDeployments?.RecurringBuyFactory?.address);
  // A vault is owner-only, so the page starts empty unless a vault is configured explicitly.
  const [vaultInput, setVaultInput] = useState<string>(ENV.vault ?? "");
  const vaultAddress = asAddress(vaultInput);
  const setVaultAddress = (address: Address) => setVaultInput(address);
  const [supra, setSupra] = useState(String(ENV.supra ?? DEFAULT_SUPRA));
  const [router, setRouter] = useState(String(ENV.router ?? DEFAULT_ROUTER));
  const [tokenOut, setTokenOut] = useState(String(ENV.tokenOut ?? DEFAULT_TOKEN));
  const [amountHbar, setAmountHbar] = useState("1");
  const [fundHbar, setFundHbar] = useState("2");
  const [withdrawHbar, setWithdrawHbar] = useState("0.1");
  const [interval, setInterval] = useState("3600");
  const [deviation, setDeviation] = useState("500");
  const [priceAge, setPriceAge] = useState("7200");
  const [bonzoPool, setBonzoPool] = useState(String(ENV.bonzoPool ?? DEFAULT_BONZO_POOL));
  const [sweepToBonzo, setSweepToBonzo] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [lastHash, setLastHash] = useState<Hash | null>(null);
  const [lastHashscan, setLastHashscan] = useState<string | null>(null);

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

  const { data: owner } = useReadContract({
    address: vaultAddress ?? zeroAddress,
    abi: recurringBuyAbi,
    functionName: "owner",
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: readEnabled },
  });
  const { data: executionGas } = useReadContract({
    address: vaultAddress ?? zeroAddress,
    abi: recurringBuyAbi,
    functionName: "executionGas",
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: readEnabled },
  });
  const { data: ownerAllowance, refetch: refetchAllowance } = useReadContract({
    address: isAddress(tokenOut) ? (tokenOut as Address) : zeroAddress,
    abi: ownerTokenAbi,
    functionName: "allowance",
    args: [accountAddress ?? zeroAddress, vaultAddress ?? zeroAddress],
    chainId: TESTNET_CHAIN_ID,
    query: { enabled: Boolean(accountAddress && vaultAddress && isAddress(tokenOut)) },
  });

  const refreshVault = async () => {
    await Promise.all([
      refetchRunning(),
      refetchNextRunAt(),
      refetchBalance(),
      refetchNextSchedule(),
      refetchLastStatus(),
      refetchAllowance(),
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
    try {
      const response = await fetch(`/api/hedera/transaction?hash=${encodeURIComponent(hash)}`, { cache: "no-store" });
      if (response.ok) {
        const data = (await response.json()) as { hashscan?: string | null };
        setLastHashscan(data.hashscan ?? null);
      }
    } catch {
      setLastHashscan(null);
    }
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
      if (sweepToBonzo) {
        if (!isAddress(bonzoPool)) throw new Error("Bonzo pool must be a valid EVM address.");
        const bonzoHash = await writeContractAsync({
          address: vaultAddress,
          abi: recurringBuyAbi,
          functionName: "configureBonzo",
          args: [bonzoPool as Address, true],
        });
        await waitForReceipt(bonzoHash);
      } else {
        const bonzoHash = await writeContractAsync({
          address: vaultAddress,
          abi: recurringBuyAbi,
          functionName: "configureBonzo",
          args: [zeroAddress, false],
        });
        await waitForReceipt(bonzoHash);
      }
      setMessage("Vault configured.");
      await refreshVault();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const associateToken = async () => {
    try {
      await requireWalletOnTestnet();
      if (!isAddress(tokenOut)) throw new Error("Token-out must be a valid EVM address.");
      const hash = await writeContractAsync({
        address: tokenOut as Address,
        abi: ownerTokenAbi,
        functionName: "associate",
      });
      await waitForReceipt(hash);
      setMessage("Your account is associated with the token (HRC-719 associate).");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    }
  };

  const approveVault = async () => {
    try {
      await requireWalletOnTestnet();
      if (!vaultAddress) throw new Error("Create or enter a vault address first.");
      if (!isAddress(tokenOut)) throw new Error("Token-out must be a valid EVM address.");
      const hash = await writeContractAsync({
        address: tokenOut as Address,
        abi: ownerTokenAbi,
        functionName: "approve",
        args: [vaultAddress, 1n],
      });
      await waitForReceipt(hash);
      setMessage("Approved the vault for one base unit; start() checks this owner proof.");
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
  const runGas = toBigInt(executionGas);
  const gasReservation = runGas ? tinybarToHbar(gasReservationTinybars(runGas)) : null;
  const isOwner = Boolean(owner && accountAddress && String(owner).toLowerCase() === accountAddress.toLowerCase());
  const hasOwnerProof = toBigInt(ownerAllowance) > 0n;
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
          message.includes("associated") ||
          message.includes("Approved") ||
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
          Only the vault owner can configure, fund, start, stop, or withdraw. Enter your vault address or create one
          above.
        </p>
        <label className="form-control mt-5">
          <span className="label-text mb-1 text-sm font-medium">Vault address</span>
          <input
            className="input input-bordered font-mono text-xs"
            placeholder="0x…"
            value={vaultInput}
            onChange={event => setVaultInput(event.target.value.trim())}
          />
        </label>
        {vaultAddress && owner && !isOwner && (
          <p className="mt-2 text-sm text-warning">
            The connected wallet is not this vault&apos;s owner ({shortAddress(String(owner))}); owner actions will
            revert.
          </p>
        )}
        <p className="mt-4 rounded-xl bg-base-200 p-3 text-xs text-base-content/70">
          Supra&apos;s feed is HBAR/USD, so the vault values one token unit at one US dollar. Use a USD-pegged token.
          The default USDC Sirio Test pool on testnet is far from that price, so runs will skip for deviation unless the
          limit is raised; a very wide limit also removes slippage protection.
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
        <div className="mt-5 rounded-xl border border-base-300 bg-base-200 p-4">
          <label className="label cursor-pointer justify-start gap-3 p-0">
            <input
              type="checkbox"
              className="toggle toggle-primary"
              checked={sweepToBonzo}
              onChange={event => setSweepToBonzo(event.target.checked)}
            />
            <span className="label-text font-medium">Sweep bought tokens into Bonzo Lend for the owner</span>
          </label>
          {sweepToBonzo && (
            <>
              <label className="form-control mt-4">
                <span className="label-text mb-1 text-sm font-medium">Bonzo LendingPool</span>
                <input
                  className="input input-bordered font-mono text-xs"
                  value={bonzoPool}
                  onChange={event => setBonzoPool(event.target.value)}
                />
              </label>
              <p className="mt-3 text-xs text-warning">
                The pinned Bonzo USDC reserve currently rejects deposits with error code 64. Leave this off unless you
                have verified an open reserve on the selected network.
              </p>
            </>
          )}
        </div>
      </section>

      <section className="mb-6 grid gap-6 lg:grid-cols-[1fr_0.9fr]">
        <div className="rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm">
          <h2 className="m-0 text-xl font-bold">3. Prepare, fund, and operate</h2>
          <p className="mt-2 text-sm text-base-content/60">
            Before start(), associate your account with the token and approve the vault for one base unit. HRC-719
            association can only be checked by the account itself, so the vault reads this approval instead.
          </p>
          <div className="mt-3 flex flex-wrap gap-3">
            <button className="btn btn-outline btn-sm" disabled={isPending} onClick={associateToken}>
              Associate token
            </button>
            <button className="btn btn-outline btn-sm" disabled={isPending || !vaultAddress} onClick={approveVault}>
              Approve vault (1 unit)
            </button>
            <span className="self-center text-xs text-base-content/60">
              Owner proof: {accountAddress && vaultAddress ? (hasOwnerProof ? "present" : "missing") : "—"}
            </span>
          </div>
          {gasReservation && (
            <p className="mt-3 text-xs text-base-content/60">
              Each run must hold a gas reservation of {gasReservation} HBAR ({runGas.toString()} gas at the observed
              83-tinybar testnet price) plus the purchase amount. Hedera charges the gas actually used and refunds the
              rest.
            </p>
          )}
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
            <button
              className="btn btn-success"
              disabled={isPending || !vaultAddress || isRunning || !hasOwnerProof}
              onClick={startVault}
            >
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
          {lastHashscan ? (
            <a className="link link-primary mt-6 block text-sm" href={lastHashscan} target="_blank" rel="noreferrer">
              View latest transaction on Hashscan
            </a>
          ) : lastHash ? (
            <p className="mt-6 break-all text-xs text-base-content/60">Latest EVM transaction: {lastHash}</p>
          ) : null}
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
