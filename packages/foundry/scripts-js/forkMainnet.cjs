// SPDX-License-Identifier: MIT

const { spawn } = require("node:child_process");
const { readFileSync } = require("node:fs");
const { resolve } = require("node:path");
const { Interface } = require("ethers/lib/utils");
const {
  jsonRPCForwarder,
} = require("@hashgraph/system-contracts-forking/forwarder");

const ROOT = resolve(__dirname, "..");
const LOCAL_RPC = process.env.FORKLAB_LOCAL_RPC_URL || "http://127.0.0.1:8545";
const REMOTE_RPC =
  process.env.HEDERA_MAINNET_RPC_URL || "https://mainnet.hashio.io/api";
const MIRROR =
  process.env.HEDERA_MIRROR_MAINNET_URL ||
  "https://mainnet-public.mirrornode.hedera.com/api/v1/";
const HSS = "0x000000000000000000000000000000000000016b";
const block = JSON.parse(
  readFileSync(resolve(__dirname, "forkBlocks.json"), "utf8")
).mainnet;

async function rpc(method, params = []) {
  const response = await fetch(LOCAL_RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
  });
  const body = await response.json();
  if (!response.ok || body.error)
    throw new Error(body.error?.message || `RPC ${response.status}`);
  return body.result;
}

async function waitForAnvil() {
  for (let attempt = 0; attempt < 80; attempt++) {
    try {
      return await rpc("eth_accounts");
    } catch {
      await new Promise((resolvePromise) => setTimeout(resolvePromise, 250));
    }
  }
  throw new Error(`Anvil did not answer at ${LOCAL_RPC}`);
}

async function main() {
  const startupKeepAlive = setInterval(() => {}, 1_000);
  const forwarder = await jsonRPCForwarder(REMOTE_RPC, MIRROR, 295);
  clearInterval(startupKeepAlive);
  const localUrl = new URL(LOCAL_RPC);
  const anvil = spawn(
    "anvil",
    [
      "--host",
      localUrl.hostname,
      "--port",
      localUrl.port || "8545",
      "--fork-url",
      forwarder.host,
      "--fork-block-number",
      String(block),
      "--chain-id",
      "295",
      "--no-storage-caching",
    ],
    { stdio: "inherit" }
  );

  const shutdown = () => {
    anvil.kill("SIGTERM");
    forwarder.terminate();
  };
  process.once("SIGINT", shutdown);
  process.once("SIGTERM", shutdown);
  anvil.once("exit", (code) => {
    forwarder.terminate();
    process.exitCode = code ?? 1;
  });

  const accounts = await waitForAnvil();
  const artifact = JSON.parse(
    readFileSync(resolve(ROOT, "out/ForklabHss.sol/ForklabHss.json"), "utf8")
  );
  await rpc("anvil_setCode", [HSS, artifact.deployedBytecode.object]);

  const config = new Interface([
    "function setMaxSchedulesPerSecond(uint256)",
    "function setMaxGasPerSecond(uint256)",
    "function setMaxExpiryFutureSeconds(uint256)",
    "function setMaxExecutionsPerRun(uint256)",
  ]);
  for (const [name, value] of [
    ["setMaxSchedulesPerSecond", 10],
    ["setMaxGasPerSecond", 15_000_000],
    ["setMaxExpiryFutureSeconds", 5_356_800],
    ["setMaxExecutionsPerRun", 100],
  ]) {
    await rpc("eth_sendTransaction", [
      {
        from: accounts[0],
        to: HSS,
        data: config.encodeFunctionData(name, [value]),
      },
    ]);
  }
  console.log(
    `Forklab ready at ${LOCAL_RPC}: mainnet block ${block}, HTS forwarder ${forwarder.host}, HSS ${HSS}`
  );
}

main().catch((error) => {
  console.error(`Forklab local fork failed: ${error.message}`);
  process.exitCode = 1;
});
