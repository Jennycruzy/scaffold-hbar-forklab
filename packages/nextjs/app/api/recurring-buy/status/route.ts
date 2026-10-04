import { NextResponse } from "next/server";
import { type Address, createPublicClient, http, isAddress } from "viem";
import { hederaTestnet } from "viem/chains";
import deployedContracts from "~~/contracts/deployedContracts";
import { recurringBuyAbi } from "~~/utils/forklab/recurringBuy";

export const dynamic = "force-dynamic";

const base = (process.env.HEDERA_MIRROR_TESTNET_URL ?? "https://testnet.mirrornode.hedera.com").replace(/\/+$/, "");
const rpc = process.env.HEDERA_TESTNET_RPC_URL ?? "https://testnet.hashio.io/api";
const configuredAddress =
  process.env.RECURRING_BUY_ADDRESS ??
  process.env.NEXT_PUBLIC_RECURRING_BUY_ADDRESS ??
  deployedContracts[296]?.RecurringBuy?.address;

/** A run is reported as stalled when its expiry passed this long ago without a new schedule. */
const STALL_GRACE_SECONDS = 120;

type MirrorTransaction = {
  consensus_timestamp: string;
  name: string;
  result: string;
  scheduled: boolean;
  transaction_id: string;
  charged_tx_fee: number;
};

function hashscanTransaction(consensusTimestamp: string) {
  return `https://hashscan.io/testnet/transaction/${consensusTimestamp}`;
}

function longZeroToEntityId(address: string) {
  return `0.0.${BigInt(address).toString()}`;
}

async function mirrorJson<T>(path: string): Promise<T | null> {
  try {
    const response = await fetch(`${base}/api/v1/${path}`, { cache: "no-store" });
    return response.ok ? ((await response.json()) as T) : null;
  } catch {
    return null;
  }
}

export async function GET() {
  if (!configuredAddress || !isAddress(configuredAddress)) {
    return NextResponse.json({
      online: false,
      configured: false,
      message: "No testnet RecurringBuy address is configured.",
    });
  }

  const address = configuredAddress as Address;
  try {
    const client = createPublicClient({ chain: hederaTestnet, transport: http(rpc) });
    const read = <T>(functionName: "running" | "nextRunAt" | "lastRunAt" | "nextSchedule" | "hbarBalance") =>
      client.readContract({ address, abi: recurringBuyAbi, functionName }) as Promise<T>;
    const [running, nextRunAt, lastRunAt, nextSchedule, balance, lastScheduleStatus] = await Promise.all([
      read<boolean>("running"),
      read<bigint>("nextRunAt"),
      read<bigint>("lastRunAt"),
      read<Address>("nextSchedule"),
      read<bigint>("hbarBalance"),
      client.readContract({ address, abi: recurringBuyAbi, functionName: "lastScheduleStatus" }),
    ]);

    // Scheduled runs are paid by the vault, so they appear among the vault account's
    // transactions with `scheduled: true`. The contract-results list does not include them.
    const contract = await mirrorJson<{ contract_id?: string }>(`contracts/${address}`);
    const transactions = contract?.contract_id
      ? await mirrorJson<{ transactions?: MirrorTransaction[] }>(
          `transactions?account.id=${contract.contract_id}&order=desc&limit=50`,
        )
      : null;
    const runs = (transactions?.transactions ?? [])
      .filter(transaction => transaction.scheduled)
      .slice(0, 10)
      .map(transaction => ({
        transactionId: transaction.transaction_id,
        consensusTimestamp: transaction.consensus_timestamp,
        result: transaction.result,
        feeTinybars: String(transaction.charged_tx_fee),
        hashscan: hashscanTransaction(transaction.consensus_timestamp),
      }));

    const now = Math.floor(Date.now() / 1_000);
    const next = Number(nextRunAt);
    const stalled = running && next > 0 && now > next + STALL_GRACE_SECONDS;
    const scheduleId = nextSchedule && BigInt(nextSchedule) !== 0n ? longZeroToEntityId(nextSchedule) : null;

    return NextResponse.json({
      online: true,
      configured: true,
      address,
      contractId: contract?.contract_id ?? null,
      running,
      stalled,
      nextRunAt: next,
      lastRunAt: Number(lastRunAt),
      nextSchedule,
      scheduleId,
      scheduleHashscan: scheduleId ? `https://hashscan.io/testnet/schedule/${scheduleId}` : null,
      balanceTinybars: balance.toString(),
      lastScheduleStatus: Number(lastScheduleStatus),
      runs,
      mirrorOk: transactions !== null,
    });
  } catch (error) {
    return NextResponse.json({
      online: false,
      configured: true,
      address,
      message: "Testnet status is temporarily unavailable.",
      detail: String(error),
    });
  }
}
