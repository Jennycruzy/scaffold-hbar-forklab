import { NextResponse } from "next/server";

const MIRROR_BASE = process.env.HEDERA_MIRROR_TESTNET_URL ?? "https://testnet.mirrornode.hedera.com";
const EVM_HASH_RE = /^0x[0-9a-fA-F]{64}$/;

function hashscan(consensusTimestamp: string) {
  return `https://hashscan.io/testnet/transaction/${consensusTimestamp}`;
}

export async function GET(req: Request) {
  const hash = new URL(req.url).searchParams.get("hash");
  if (!hash || !EVM_HASH_RE.test(hash)) {
    return NextResponse.json({ hashscan: null, message: "Pass a valid EVM transaction hash with ?hash=0x…" });
  }

  try {
    const response = await fetch(`${MIRROR_BASE}/api/v1/contracts/results/${encodeURIComponent(hash)}`, {
      next: { revalidate: 15 },
    });
    if (!response.ok) {
      return NextResponse.json({ hash, hashscan: null, mirrorOk: false, status: response.status });
    }

    const result = (await response.json()) as { timestamp?: string; consensus_timestamp?: string };
    const consensusTimestamp = result.timestamp ?? result.consensus_timestamp ?? null;
    return NextResponse.json({
      hash,
      consensusTimestamp,
      hashscan: consensusTimestamp ? hashscan(consensusTimestamp) : null,
      mirrorOk: true,
    });
  } catch (error) {
    return NextResponse.json({ hash, hashscan: null, mirrorOk: false, detail: String(error) }, { status: 502 });
  }
}
