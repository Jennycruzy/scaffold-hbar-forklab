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

The first command is offline and uses chain id `31337`. The fork commands use the pinned blocks in `scripts-js/forkBlocks.json`, real Hashio state, FFI, and the timestamp-bounded Mirror Node adapter. `foundry:test:fork` runs the main mainnet pin and then the Bonzo sweep suite on the pre-pause `bonzoMainnet` pin (`test:fork:bonzo`). `foundry:test:testnet-fork` runs the WHBAR/SAUCE swap and a RecurringBuy deviation skip on the testnet pin.

`fork:pin` and `fork:pin:testnet` walk back from the latest block and pin only a block whose Mirror Node balance snapshot equals a reference SaucerSwap pair's reserves.

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

This deploys `RecurringBuy` and `RecurringBuyFactory` and updates `packages/nextjs/contracts/deployedContracts.ts`.

To run the vault, use `KEYSTORE_NAME=<keystore> yarn foundry:testnet:start` (`scripts-js/startTestnetVault.sh`). It
sends the owner's direct HRC-719 `associate()` and a one-unit approval, configures the vault, sets the execution gas
limit (2,500,000 by default), funds it with 15 HBAR by default, starts the first schedule, and watches two runs. Association must be direct because HRC-719 checks
`msg.sender`; the allowance is the queryable owner proof. The full command is in the repository README.
