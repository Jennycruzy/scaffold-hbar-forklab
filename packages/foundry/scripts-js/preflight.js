import { spawnSync } from "node:child_process";

const EXPECTED_FORGE = "1.5.0";
const MINIMUM_NODE = [20, 18, 3];
const RPCS = {
  mainnet: {
    name: "mainnet",
    url: process.env.HEDERA_MAINNET_RPC_URL || "https://mainnet.hashio.io/api",
    chainId: "0x127",
  },
  testnet: {
    name: "testnet",
    url: process.env.HEDERA_TESTNET_RPC_URL || "https://testnet.hashio.io/api",
    chainId: "0x128",
  },
};

function commandVersion(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error || result.status !== 0) return null;
  return `${result.stdout || ""}${result.stderr || ""}`.trim();
}

function hasCommand(command) {
  const result = spawnSync("bash", ["-lc", `command -v ${command}`], {
    encoding: "utf8",
  });
  return result.status === 0 && result.stdout.trim().length > 0;
}

function checkRpc(network) {
  const payload = JSON.stringify({
    jsonrpc: "2.0",
    method: "eth_chainId",
    params: [],
    id: 1,
  });
  const result = spawnSync(
    "curl",
    [
      "-sS",
      "--fail",
      "--max-time",
      "20",
      "-H",
      "content-type: application/json",
      "--data",
      payload,
      network.url,
    ],
    { encoding: "utf8" }
  );
  if (result.error || result.status !== 0) {
    return `RPC did not answer at ${network.url}: ${(
      result.stderr || "curl failed"
    ).trim()}`;
  }
  try {
    const response = JSON.parse(result.stdout);
    if (response.result !== network.chainId) {
      return `RPC chain id was ${response.result || "missing"}; expected ${
        network.chainId
      } for ${network.name}.`;
    }
  } catch {
    return `RPC returned non-JSON data: ${result.stdout.trim()}`;
  }
  return null;
}

const networkIndex = process.argv.indexOf("--network");
const requestedNetwork =
  networkIndex >= 0 ? process.argv[networkIndex + 1] || "mainnet" : "mainnet";
const expectsFfiFlag = process.argv.includes("--expect-ffi");
const network = RPCS[requestedNetwork];
const failures = [];
const warnings = [];

const nodeVersion = process.versions.node.split(".").map(Number);
const nodeIsSupported = MINIMUM_NODE.every(
  (part, index) =>
    nodeVersion[index] === part ||
    (nodeVersion[index] > part &&
      nodeVersion.slice(0, index).every((value, prior) => value === MINIMUM_NODE[prior])) ||
    nodeVersion.slice(0, index).some((value, prior) => value > MINIMUM_NODE[prior])
);
if (!nodeIsSupported) {
  failures.push(`node must be >=20.18.3; found ${process.versions.node}.`);
}

if (!network)
  failures.push(
    `Unknown network '${requestedNetwork}'. Use mainnet or testnet.`
  );

const forgeVersion = commandVersion("forge", ["--version"]);
const forgeMatch = forgeVersion?.match(/Version:\s*([0-9]+\.[0-9]+\.[0-9]+)/);
if (!forgeMatch || forgeMatch[1] !== EXPECTED_FORGE) {
  failures.push(
    `forge must be ${EXPECTED_FORGE}; found ${
      forgeMatch?.[1] || "unavailable"
    }. Fix with 'foundryup -i ${EXPECTED_FORGE}'.`
  );
}

if (!hasCommand("cast"))
  failures.push("cast is not on PATH. Add the Foundry bin directory to PATH.");
if (!hasCommand("curl"))
  failures.push("curl is not on PATH. Install curl and retry.");
if (!hasCommand("bash"))
  failures.push(
    "bash is not on PATH. macOS, Linux, or WSL is required for Mirror Node reads."
  );

const forgeConfig = commandVersion("forge", ["config", "--json"]);
try {
  if (!forgeConfig || JSON.parse(forgeConfig).ffi !== true) {
    warnings.push(
      "Foundry FFI is disabled. Set `ffi = true` and run fork tests with `--ffi`; Mirror Node reads will fail otherwise."
    );
  }
} catch {
  warnings.push("Could not verify Foundry FFI configuration; fork tests require `ffi = true` and `--ffi`.");
}
if (!expectsFfiFlag) {
  warnings.push("This check cannot see a later forge command. Ensure fork tests include the `--ffi` flag.");
}
if (network && hasCommand("curl")) {
  const rpcFailure = checkRpc(network);
  if (rpcFailure) failures.push(rpcFailure);
}

console.log(
  `Forklab doctor: Foundry ${EXPECTED_FORGE}, ${
    network?.name || requestedNetwork
  } RPC.`
);
for (const warning of warnings) console.warn(`WARNING: ${warning}`);
if (failures.length > 0) {
  console.error("Environment checks failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log(
    `OK: forge ${EXPECTED_FORGE}, cast, curl, bash, and ${network.name} eth_chainId.`
  );
}
