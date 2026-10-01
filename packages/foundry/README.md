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
node .yarn/releases/yarn-3.2.3.cjs foundry:chain
```

This starts plain Anvil on chain id `31337`. The HSS emulator can be installed at `0x16b` by a test or local runner with `Forklab.setUp()`.

## Deploy

Testnet deployment requires a funded Hedera account in a Foundry keystore. Never commit that keystore. The deployment script accepts the existing Foundry account selection and uses the network-specific Hashio endpoint.
