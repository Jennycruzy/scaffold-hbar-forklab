import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const network = process.argv[2] || "mainnet";
const config = {
  mainnet: {
    url: process.env.HEDERA_MAINNET_RPC_URL || "https://mainnet.hashio.io/api",
    chainId: "0x127",
  },
  testnet: {
    url: process.env.HEDERA_TESTNET_RPC_URL || "https://testnet.hashio.io/api",
    chainId: "0x128",
  },
}[network];
if (!config) throw new Error("Use mainnet or testnet.");

const payload = JSON.stringify({
  jsonrpc: "2.0",
  method: "eth_blockNumber",
  params: [],
  id: 1,
});
const output = execFileSync(
  "curl",
  [
    "-sS",
    "--fail",
    "--max-time",
    "30",
    "-H",
    "content-type: application/json",
    "--data",
    payload,
    config.url,
  ],
  { encoding: "utf8" }
);
const response = JSON.parse(output);
if (response.result === undefined)
  throw new Error(`RPC response did not include a block number: ${output}`);
const block = Number.parseInt(response.result, 16);
if (!Number.isSafeInteger(block) || block <= 0)
  throw new Error(`Invalid block number: ${response.result}`);

const file = fileURLToPath(new URL("./forkBlocks.json", import.meta.url));
const blocks = JSON.parse(readFileSync(file, "utf8"));
blocks[network] = block;
writeFileSync(file, `${JSON.stringify(blocks, null, 2)}\n`);
console.log(
  `${network} fork block pinned to ${block} (${response.result}); chain id ${config.chainId}.`
);
