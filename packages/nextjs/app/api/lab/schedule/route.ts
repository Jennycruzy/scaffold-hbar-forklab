import { NextResponse } from "next/server";
import { decodeEventLog, encodeFunctionData, parseAbi } from "viem";
import { localRpcCall, localRpcUrl } from "~~/lib/lab/rpc";

const HSS = "0x000000000000000000000000000000000000016b";
const hssAbi = parseAbi([
  "function scheduleCall(address to,uint256 expirySecond,uint256 gasLimit,uint64 value,bytes callData) returns (int64 responseCode,address scheduleAddress)",
  "event ScheduleCreated(address indexed schedule,address indexed payer,address indexed to,uint256 expirySecond,uint256 gasLimit,uint64 value,bytes callData)",
]);

/** One HBAR, in the tinybar units HSS uses for a scheduled call's value. */
const DEMO_VALUE_TINYBARS = 100_000_000n;
/** Enough for a plain HBAR transfer to an account; the payer reserves this limit at 83 tinybars per gas. */
const DEMO_GAS_LIMIT = 100_000n;
/** Covers the measured 1,409,649-gas schedule creation plus emulator storage writes. */
const CREATE_TX_GAS = "0x2dc6c0";

type Hex = `0x${string}`;
type Log = { address: Hex; topics: [Hex, ...Hex[]]; data: Hex };
type Receipt = { status: Hex; transactionHash: Hex; logs: Log[] };
type Block = { timestamp: Hex };

async function waitForReceipt(hash: Hex): Promise<Receipt> {
  for (let attempt = 0; attempt < 40; attempt++) {
    const receipt = await localRpcCall<Receipt | null>("eth_getTransactionReceipt", [hash]);
    if (receipt) return receipt;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for ${hash}`);
}

export async function GET() {
  return NextResponse.json({ ok: false, message: "POST delaySeconds to create a demo schedule on the local fork." });
}

/**
 * Creates a real HSS schedule on the local fork: Anvil's first unlocked account pays and
 * schedules a one-HBAR transfer to the second, so a fresh fork has something to run.
 */
export async function POST(request: Request) {
  try {
    const body = (await request.json().catch(() => ({}))) as { delaySeconds?: number };
    const delaySeconds = Math.floor(Number(body.delaySeconds ?? 60));
    if (!Number.isFinite(delaySeconds) || delaySeconds < 1 || delaySeconds > 5_356_800) {
      return NextResponse.json({ ok: false, message: "delaySeconds must be between 1 and 5,356,800" });
    }

    const [payer, recipient] = await localRpcCall<Hex[]>("eth_accounts");
    const latest = await localRpcCall<Block>("eth_getBlockByNumber", ["latest", false]);
    const expirySecond = BigInt(latest.timestamp) + BigInt(delaySeconds);
    const data = encodeFunctionData({
      abi: hssAbi,
      functionName: "scheduleCall",
      args: [recipient, expirySecond, DEMO_GAS_LIMIT, DEMO_VALUE_TINYBARS, "0x"],
    });
    const hash = await localRpcCall<Hex>("eth_sendTransaction", [{ from: payer, to: HSS, data, gas: CREATE_TX_GAS }]);
    const receipt = await waitForReceipt(hash);

    const created = receipt.logs
      .filter(log => log.address.toLowerCase() === HSS)
      .map(log => {
        try {
          return decodeEventLog({ abi: hssAbi, data: log.data, topics: log.topics });
        } catch {
          return null;
        }
      })
      .find(event => event?.eventName === "ScheduleCreated");

    if (BigInt(receipt.status) !== 1n || !created) {
      return NextResponse.json({
        ok: false,
        transactionHash: hash,
        message: "HSS did not create the schedule; inspect the transaction on the local fork.",
      });
    }
    return NextResponse.json({
      ok: true,
      rpc: localRpcUrl,
      transactionHash: hash,
      schedule: created.args.schedule,
      payer,
      to: recipient,
      expirySecond: expirySecond.toString(),
      valueTinybars: DEMO_VALUE_TINYBARS.toString(),
      gasLimit: DEMO_GAS_LIMIT.toString(),
    });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      offline: true,
      message: "Start `yarn fork:mainnet` first.",
      detail: String(error),
    });
  }
}
