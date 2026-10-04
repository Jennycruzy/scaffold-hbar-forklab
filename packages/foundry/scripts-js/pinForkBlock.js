import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

// Mirror Node token balances filtered by timestamp come from periodic balance
// snapshots, not from every transaction. A block is only a usable fork pin when
// the snapshot at its timestamp postdates the reference pair's last swap;
// otherwise the pair's EVM reserves and the emulated HTS balances disagree and
// swaps revert with `UniswapV2: K`. This script walks back from the latest block
// until the reference SaucerSwap V1 pair is consistent, then pins that block.

const network = process.argv[2] || "mainnet";
const config = {
  mainnet: {
    rpc: process.env.HEDERA_MAINNET_RPC_URL || "https://mainnet.hashio.io/api",
    mirror: (
      process.env.HEDERA_MIRROR_MAINNET_URL ||
      "https://mainnet-public.mirrornode.hedera.com"
    ).replace(/\/+$/, ""),
    // USDC/WHBAR, used by the mainnet swap and RecurringBuy suites.
    pair: "0xdB34c1Ef944883f0e5A2fC18B6C1978B088bD31d",
  },
  testnet: {
    rpc: process.env.HEDERA_TESTNET_RPC_URL || "https://testnet.hashio.io/api",
    mirror: (
      process.env.HEDERA_MIRROR_TESTNET_URL ||
      "https://testnet.mirrornode.hedera.com"
    ).replace(/\/+$/, ""),
    // WHBAR/SAUCE, used by the testnet-fork suite.
    pair: "0xfE7CC3cEb7b1128bfC3889184E2d5561BF74bfb3",
  },
}[network];
if (!config) throw new Error("Use mainnet or testnet.");

const STEP = 50;
const MAX_ATTEMPTS = 60;

async function rpc(method, params) {
  const response = await fetch(config.rpc, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const body = await response.json();
  if (!response.ok || body.error)
    throw new Error(`${method}: ${JSON.stringify(body.error ?? body)}`);
  return body.result;
}

async function mirror(path) {
  const response = await fetch(`${config.mirror}/api/v1/${path}`);
  if (!response.ok)
    throw new Error(`Mirror Node ${path}: HTTP ${response.status}`);
  return response.json();
}

function word(hex, index) {
  return BigInt(`0x${hex.slice(2 + index * 64, 2 + (index + 1) * 64)}`);
}

function tokenId(address) {
  return `0.0.${BigInt(address)}`;
}

async function call(data, block) {
  return rpc("eth_call", [
    { to: config.pair, data },
    `0x${block.toString(16)}`,
  ]);
}

const pairAccount = (await mirror(`accounts/${config.pair}?transactions=false`))
  .account;
const latest = Number.parseInt(await rpc("eth_blockNumber", []), 16);
const token0 = `0x${(await call("0x0dfe1681", latest)).slice(-40)}`;
const token1 = `0x${(await call("0xd21220a7", latest)).slice(-40)}`;

for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
  const block = latest - attempt * STEP;
  const reserves = await call("0x0902f1ac", block);
  const timestamp = (await mirror(`blocks/${block}`)).timestamp.to;
  const balances = await Promise.all(
    [token0, token1].map(async (token) => {
      const json = await mirror(
        `tokens/${tokenId(
          token
        )}/balances?account.id=${pairAccount}&timestamp=lte:${timestamp}`
      );
      return BigInt(json.balances[0]?.balance ?? -1);
    })
  );
  if (balances[0] === word(reserves, 0) && balances[1] === word(reserves, 1)) {
    const file = fileURLToPath(new URL("./forkBlocks.json", import.meta.url));
    const blocks = JSON.parse(readFileSync(file, "utf8"));
    blocks[network] = block;
    writeFileSync(file, `${JSON.stringify(blocks, null, 2)}\n`);
    console.log(
      `${network} fork block pinned to ${block} (timestamp ${timestamp}); ` +
        `pair ${config.pair} reserves match the Mirror Node balance snapshot.`
    );
    console.log(
      "Fork tests that assert pinned quotes or balances must be re-checked after a new pin."
    );
    process.exit(0);
  }
}

console.error(
  `No block within ${
    STEP * MAX_ATTEMPTS
  } blocks of ${latest} had a Mirror Node snapshot consistent with ${
    config.pair
  }.`
);
process.exit(1);
