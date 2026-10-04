import { NextResponse } from "next/server";
import { decodeFunctionResult, encodeFunctionData, parseAbi } from "viem";
import { localRpcCall, localRpcUrl } from "~~/lib/lab/rpc";
import { tinybarToWeibar } from "~~/utils/forklab/units";

const HSS = "0x000000000000000000000000000000000000016b";
const hssAbi = parseAbi([
  "function pending() view returns (address[] schedules)",
  "function schedule(address) view returns ((address to,address payer,uint256 expiry,uint256 gasLimit,uint64 value,bytes data,int64 status,bool success,bytes returnData,uint256 createdAt,uint256 executedAt) info)",
  "function shouldExternalRunnerCall(address) view returns (bool)",
  "function recordExternalExecution(address,bool,bytes) returns (int64)",
]);

type Hex = `0x${string}`;
type Receipt = { status: Hex; transactionHash: Hex };

async function callHss(
  functionName: "pending" | "schedule" | "shouldExternalRunnerCall",
  args: readonly unknown[] = [],
) {
  const data = encodeFunctionData({ abi: hssAbi, functionName, args } as never);
  const result = await localRpcCall<Hex>("eth_call", [{ to: HSS, data }, "latest"]);
  return decodeFunctionResult({ abi: hssAbi, functionName, data: result } as never);
}

/** Simulates the target call first so a failure's revert data can be settled in HSS. */
async function simulate(payer: Hex, to: Hex, data: Hex, gas: string, value: string): Promise<Hex> {
  const response = await fetch(localRpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: Date.now(),
      method: "eth_call",
      params: [{ from: payer, to, data, gas, value }, "latest"],
    }),
    cache: "no-store",
  });
  const body = (await response.json()) as { result?: Hex; error?: { data?: unknown } };
  if (body.result) return body.result;
  const errorData = body.error?.data;
  return typeof errorData === "string" && errorData.startsWith("0x") ? (errorData as Hex) : "0x";
}

async function waitForReceipt(hash: Hex): Promise<Receipt> {
  for (let attempt = 0; attempt < 40; attempt++) {
    const receipt = await localRpcCall<Receipt | null>("eth_getTransactionReceipt", [hash]);
    if (receipt) return receipt;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out waiting for ${hash}`);
}

export async function GET() {
  try {
    const schedules = (await callHss("pending")) as Hex[];
    return NextResponse.json({ ok: true, pending: schedules });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      offline: true,
      message: "Start `yarn fork:mainnet` first.",
      detail: String(error),
    });
  }
}

export async function POST() {
  try {
    const schedules = (await callHss("pending")) as Hex[];
    const block = await localRpcCall<{ timestamp: Hex }>("eth_getBlockByNumber", ["latest", false]);
    const now = BigInt(block.timestamp);
    const executed = [];
    const waiting = [];

    for (const scheduleAddress of schedules) {
      const info = (await callHss("schedule", [scheduleAddress])) as {
        to: Hex;
        payer: Hex;
        expiry: bigint;
        gasLimit: bigint;
        value: bigint;
        data: Hex;
        status: bigint;
      };
      const { to, payer, expiry, gasLimit, value, data } = info;
      if (expiry > now) {
        waiting.push({ schedule: scheduleAddress, expiry: expiry.toString() });
        continue;
      }

      await localRpcCall("anvil_impersonateAccount", [payer]);
      const shouldCall = (await callHss("shouldExternalRunnerCall", [scheduleAddress])) as boolean;
      let success = false;
      let targetHash: Hex | null = null;
      let returnData: Hex = "0x";
      if (shouldCall) {
        const gas = `0x${gasLimit.toString(16)}`;
        const weibars = `0x${tinybarToWeibar(value).toString(16)}`;
        returnData = await simulate(payer, to, data, gas, weibars);
        targetHash = await localRpcCall<Hex>("eth_sendTransaction", [{ from: payer, to, data, gas, value: weibars }]);
        success = BigInt((await waitForReceipt(targetHash)).status) === 1n;
      }

      const settlementData = encodeFunctionData({
        abi: hssAbi,
        functionName: "recordExternalExecution",
        args: [scheduleAddress, success, returnData],
      });
      const settlementHash = await localRpcCall<Hex>("eth_sendTransaction", [
        { from: payer, to: HSS, data: settlementData, gas: "0x7a120" },
      ]);
      await waitForReceipt(settlementHash);
      const settled = (await callHss("schedule", [scheduleAddress])) as { status: bigint };
      executed.push({
        schedule: scheduleAddress,
        targetHash,
        settlementHash,
        status: String(settled.status),
        success,
        returnData,
      });
      await localRpcCall("anvil_stopImpersonatingAccount", [payer]);
    }
    return NextResponse.json({ ok: true, executed, waiting }, { status: 200 });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      offline: true,
      message: "The local Anvil runner is unavailable.",
      detail: String(error),
    });
  }
}
