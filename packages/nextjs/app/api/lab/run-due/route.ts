import { NextResponse } from "next/server";
import { localRpcCall } from "~~/lib/lab/rpc";

type DueSchedule = { payer: `0x${string}`; to: `0x${string}`; data: `0x${string}`; gas: string };

export async function GET() {
  return NextResponse.json({
    ok: false,
    offline: true,
    message: "POST due schedule records to run them on a local fork.",
  });
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { schedules?: DueSchedule[] };
    const schedules = Array.isArray(body.schedules) ? body.schedules : [];
    const transactions = [];
    for (const schedule of schedules) {
      await localRpcCall("anvil_impersonateAccount", [schedule.payer]);
      const hash = await localRpcCall<string>("eth_sendTransaction", [
        {
          from: schedule.payer,
          to: schedule.to,
          data: schedule.data,
          gas: `0x${BigInt(schedule.gas).toString(16)}`,
        },
      ]);
      transactions.push({ ...schedule, hash });
    }
    return NextResponse.json({ ok: true, executed: transactions });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      offline: true,
      message: "The local Anvil runner is unavailable.",
      detail: String(error),
    });
  }
}
