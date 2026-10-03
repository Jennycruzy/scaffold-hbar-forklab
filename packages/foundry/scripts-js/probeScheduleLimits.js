#!/usr/bin/env node

const rpcUrl =
  process.env.HEDERA_TESTNET_RPC_URL ?? "https://testnet.hashio.io/api";
const hss = "0x000000000000000000000000000000000000016b";
const selector = "dfb4a999"; // hasScheduleCapacity(uint256,uint256)
const deltas = [0n, 1n, 5_356_800n, 5_356_801n];
const gasLimits = [100_000n, 1_000_000n, 15_000_000n];

let requestId = 1;

async function rpc(method, params) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: requestId++, method, params }),
  });
  const body = await response.json();
  if (!response.ok || body.error) {
    throw new Error(`${method}: ${JSON.stringify(body.error ?? body)}`);
  }
  return body.result;
}

function word(value) {
  return value.toString(16).padStart(64, "0");
}

const block = await rpc("eth_getBlockByNumber", ["latest", false]);
const blockNumber = block.number;
const now = BigInt(block.timestamp);
const results = [];

for (const delta of deltas) {
  for (const gasLimit of gasLimits) {
    const expiry = now + delta;
    const data = `0x${selector}${word(expiry)}${word(gasLimit)}`;
    const encoded = await rpc("eth_call", [{ to: hss, data }, blockNumber]);
    results.push({
      delta: Number(delta),
      expiry: expiry.toString(),
      gasLimit: gasLimit.toString(),
      hasCapacity: BigInt(encoded) !== 0n,
    });
  }
}

console.log(
  JSON.stringify(
    {
      rpcUrl,
      blockNumber: BigInt(blockNumber).toString(),
      now: now.toString(),
      results,
    },
    null,
    2
  )
);
