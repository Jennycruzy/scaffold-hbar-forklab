import { NextResponse } from "next/server";
import { type Address, createPublicClient, http, isAddress } from "viem";
import { hederaTestnet } from "viem/chains";
import deployedContracts from "~~/contracts/deployedContracts";
import { recurringBuyAbi } from "~~/utils/forklab/recurringBuy";

const base = process.env.HEDERA_MIRROR_TESTNET_URL ?? "https://testnet.mirrornode.hedera.com";
const rpc = process.env.HEDERA_TESTNET_RPC_URL ?? "https://testnet.hashio.io/api";
const configuredAddress =
  process.env.RECURRING_BUY_ADDRESS ??
  process.env.NEXT_PUBLIC_RECURRING_BUY_ADDRESS ??
  deployedContracts[296]?.RecurringBuy?.address;

function hashscan(consensusTimestamp: string) {
  return `https://hashscan.io/testnet/transaction/${consensusTimestamp}`;
}

export async function GET() {
  if (!configuredAddress || !isAddress(configuredAddress)) {
    return NextResponse.json({
      online: false,
      configured: false,
      message: "No testnet RecurringBuy address is configured.",
    });
  }

  try {
    const client = createPublicClient({ chain: hederaTestnet, transport: http(rpc) });
    const address = configuredAddress as Address;
    const [running, nextRunAt, lastRunAt, nextSchedule, balance, lastScheduleStatus] = await Promise.all([
      client.readContract({ address, abi: recurringBuyAbi, functionName: "running" }),
      client.readContract({ address, abi: recurringBuyAbi, functionName: "nextRunAt" }),
      client.readContract({ address, abi: recurringBuyAbi, functionName: "lastRunAt" }),
      client.readContract({ address, abi: recurringBuyAbi, functionName: "nextSchedule" }),
      client.readContract({ address, abi: recurringBuyAbi, functionName: "hbarBalance" }),
      client.readContract({ address, abi: recurringBuyAbi, functionName: "lastScheduleStatus" }),
    ]);

    const mirror = await fetch(`${base}/api/v1/contracts/${address}/results?order=desc&limit=10`, {
      next: { revalidate: 15 },
    });
    const mirrorData = mirror.ok ? await mirror.json() : { results: [] };
    const runs = Array.isArray(mirrorData.results)
      ? mirrorData.results.map(
          (result: { hash?: string; timestamp?: string; consensus_timestamp?: string; result?: string }) => ({
            hash: result.hash ?? null,
            consensusTimestamp: result.timestamp ?? result.consensus_timestamp ?? null,
            result: result.result ?? null,
            hashscan: result.timestamp
              ? hashscan(result.timestamp)
              : result.consensus_timestamp
                ? hashscan(result.consensus_timestamp)
                : null,
          }),
        )
      : [];

    return NextResponse.json({
      online: true,
      configured: true,
      address,
      running,
      nextRunAt: Number(nextRunAt),
      lastRunAt: Number(lastRunAt),
      nextSchedule,
      balanceTinybars: BigInt(balance as bigint).toString(),
      lastScheduleStatus: Number(lastScheduleStatus),
      runs,
      mirrorOk: mirror.ok,
    });
  } catch (error) {
    return NextResponse.json({
      online: false,
      configured: true,
      message: "Testnet status is temporarily unavailable.",
      detail: String(error),
    });
  }
}
