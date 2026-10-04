# Forklab Foundry package

This package contains the Foundry contracts, scripts, and tests for Forklab.

## Setup

From the repository root:

```bash
git submodule update --init --recursive
node .yarn/releases/yarn-3.2.3.cjs install
node .yarn/releases/yarn-3.2.3.cjs foundry:doctor
```

The pinned libraries are restored from `foundry.lock`. Do not edit files below `lib/`.

## Tests

```bash
node .yarn/releases/yarn-3.2.3.cjs foundry:test
node .yarn/releases/yarn-3.2.3.cjs foundry:test:fork
node .yarn/releases/yarn-3.2.3.cjs foundry:test:testnet-fork
```

The first command is offline and uses chain id `31337`. The fork commands use the pinned block in `scripts-js/forkBlocks.json`, real Hashio state, FFI, and the timestamp-bounded Mirror Node adapter.

## Local chain

```bash
node .yarn/releases/yarn-3.2.3.cjs fork:mainnet
```

This compiles the emulator, starts Hedera's HTS JSON-RPC forwarder, forks pinned mainnet state into Anvil on chain id `295`, and installs HSS at `0x16b`. Start the Next.js app separately and use `/lab` to advance time and execute due schedules. `foundry:chain` remains available when a plain chain-id `31337` Anvil instance is needed.

## Deploy

Testnet deployment requires a funded Hedera account in a Foundry keystore. Never commit that keystore. The deployment script accepts the existing Foundry account selection and uses the network-specific Hashio endpoint.

From the repository root, deploy the verified network defaults with:

```bash
node .yarn/releases/yarn-3.2.3.cjs foundry:deploy \
  --network hedera_testnet --keystore forklab-testnet
```

After selecting and measuring a real testnet pair, set `RECURRING_BUY_VAULT` and `RECURRING_BUY_TOKEN_OUT`, then
run `script/ConfigureAndStartRecurringBuy.s.sol`. It associates the signing account, configures the vault, leaves
Bonzo disabled unless separately configured, funds the vault in weibars, and starts the first schedule. The full
command and current proof-only token are documented in the repository README.
