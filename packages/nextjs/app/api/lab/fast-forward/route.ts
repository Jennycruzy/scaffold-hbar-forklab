import { NextResponse } from "next/server";
import { localRpcCall, localRpcUrl } from "~~/lib/lab/rpc";

export async function GET() {
  return NextResponse.json({ ok: false, offline: true, message: "POST seconds to fast-forward a running local fork." });
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { seconds?: number };
    const seconds = Math.floor(Number(body.seconds ?? 0));
    if (!Number.isFinite(seconds) || seconds <= 0 || seconds > 31_536_000) {
      return NextResponse.json({ ok: false, message: "seconds must be between 1 and 31,536,000" });
    }
    await localRpcCall("evm_increaseTime", [seconds]);
    await localRpcCall("evm_mine");
    return NextResponse.json({ ok: true, seconds, rpc: localRpcUrl });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      offline: true,
      message: "Start `yarn fork:mainnet` first.",
      detail: String(error),
    });
  }
}
