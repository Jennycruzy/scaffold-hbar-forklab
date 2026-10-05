# Agent instructions

Forklab is a Foundry-only Scaffold-HBAR template. Keep work reproducible against real Hedera state and leave command output in the relevant evidence document.

## Rules

- Do not fake external systems. SaucerSwap, Supra, HTS, Mirror Node, HSS, and Bonzo sweep tests use real fork or network state. Bonzo's mainnet pool is paused at the main pin (`Error("64")`, `LP_IS_PAUSED`); the successful sweep proof runs on the pre-pause `bonzoMainnet` pin.
- Call `Forklab.setUp()` before using HTS or HSS in a fork test.
- Pin the fork block with `fork:pin`, which only accepts blocks whose Mirror Node balance snapshot matches a reference pair. Record the block, chain id, RPC command, and result in `docs/VERIFIED.md`.
- Fund every HSS payer for gas: the emulator reserves `gasLimit × 83` tinybars and charges schedule creation 1,409,649 gas, as measured on testnet. A payer that cannot cover the reservation is still charged 1,735,120 tinybars, as testnet did.
- Use named tinybar constants. One HBAR is `100_000_000` EVM units.
- `deal` may fund a test account before an action, but never edit a pool, oracle, or lending reserve to hide a failure.
- Associate an account with a token (`Forklab.associateLocalAccount` on a fork) before it calls `approve`; tokens passed to `Forklab.useTokens` reject an unassociated approve, as Hedera does.
- Do not use `vm.mockCall` for an external contract.
- Do not skip a failing fork assertion. Fix it or record the exact blocker.
- Do not change pinned library or tool versions without reproducing the reason in `docs/VERIFIED.md`.
- Never commit keys, environment files, or keystores.
- Do not edit files under `packages/foundry/lib/`; they are recreated from the lockfile.

## File map

- `packages/foundry/contracts/forklab/Forklab.sol`: user-facing test library.
- `packages/foundry/contracts/forklab/ForklabHss.sol`: schedule service emulator at `0x16b`.
- `packages/foundry/contracts/forklab/ForklabHts.sol`: HTS compatibility layer at `0x167`.
- `packages/foundry/contracts/forklab/ForklabMirrorNode.sol`: timestamp-bounded Mirror Node adapter.
- `packages/foundry/contracts/forklab/IHederaScheduleService.sol`: HIP-1215 ABI.
- `packages/foundry/contracts/ISupraSValueFeed.sol`: Supra push-oracle read interface.
- `packages/foundry/contracts/RecurringBuy.sol` and `RecurringBuyFactory.sol`: the example vault and its per-wallet factory.
- `packages/foundry/test/ForklabHss.t.sol`: offline emulator tests. `test/FirstScheduledCall.t.sol` is the README sample.
- `packages/foundry/test/compat/`: the payments-scheduler port that executes through Forklab.
- `packages/foundry/test/fork/`: mainnet and testnet fork tests. `BonzoSweepMainnet.t.sol` runs only on the `bonzoMainnet` pin.
- `packages/foundry/script/Deploy.s.sol`: deploys RecurringBuy and RecurringBuyFactory. `DeployRecurringBuy.s.sol` deploys the vault alone.
- `packages/foundry/scripts-js/startTestnetVault.sh` (`yarn foundry:testnet:start`): owner association and approval, configuration, gas limit, funding, `start()`, and a watch of the first live runs. It uses `cast send` because `forge script` simulates locally without Hedera system contracts and reverts on `start()`.
- `verify.sh`: the one-minute judge check (offline suite, two fork reproductions, the testnet Mirror Node record).
- `packages/foundry/scripts-js/`: preflight, snapshot-checked block pinning, the schedule-limit probe, and the `/lab` Anvil launcher.
- `packages/nextjs/app/`: `/` (standalone landing page with the emulator playground; its rules live in `utils/forklab/scheduleModel.ts` and must match `ForklabHss.sol`), `/testnet` (testnet vault status and scheduled runs), `/vault` (create and operate a vault), `/lab` (Anvil fast-forward and runner), plus the template's `/debug` and `/blockexplorer`.
- `docs/`: evidence and user documentation.

## Recipes

### Add a token

1. Verify the token address with `cast code` and the Mirror Node.
2. Add the address to the test constants and call `Forklab.useTokens`.
3. Read the token balance from the fork and compare it with the timestamp-bounded Mirror Node response.
4. Record the commands and outputs in `docs/VERIFIED.md`.

### Test a scheduled contract

1. Deploy a full contract in the test itself.
2. Schedule through `IHederaScheduleService(0x16b)`.
3. Assert the response code and schedule ID.
4. Advance time with `Forklab.warp` or `Forklab.warpTo`.
5. Assert the target event, sender, value, gas behavior, and resulting schedule status.

### Add an HTS selector

1. Reproduce the selector from a real transaction trace.
2. Confirm the corresponding method and response semantics in the pinned hedera-forking source.
3. Add the smallest compatibility method to `ForklabHts` while retaining authorization and key checks.
4. Add a real fork proof and an offline unit test for the translation.

## Common failures

| Failure                                   | Likely cause                          | Response                                                                |
| ----------------------------------------- | ------------------------------------- | ----------------------------------------------------------------------- |
| Hashio returns HTTP 400 for a fork        | Unsupported Foundry request shape     | Use Foundry `v1.5.0` and run the doctor script.                         |
| HTS call returns empty data               | `cast`, `curl`, or FFI is unavailable | Run the doctor script and inspect its first failed check.               |
| Token balance differs from a pair reserve | Mirror transfers after the snapshot were not applied | Inspect URLs with `FORKLAB_MIRROR_LOG_URLS=true`; `fetchBalance` adds transfers up to the fork timestamp. |
| Scheduled run fails with no target event  | Gas limit below the 1.41M re-schedule  | Raise the gas limit and inspect the schedule's return data.             |
| SaucerSwap HBAR swap fails in `mintToken` | Legacy uint64 selector                | Extend `ForklabHts` only after a real trace proves the selector.        |
| Schedule target sees the wrong sender     | Executor did not prank the payer      | Assert `msg.sender` in a target fixture and inspect the schedule payer. |
| Schedule stops after a successful run     | Payer lacks HBAR for a value or fee   | Inspect the schedule status and payer balance.                          |

## Checks

Run these from the repository root after each coherent change:

```bash
node .yarn/releases/yarn-3.2.3.cjs lint
node .yarn/releases/yarn-3.2.3.cjs next:check-types
node .yarn/releases/yarn-3.2.3.cjs next:build
node .yarn/releases/yarn-3.2.3.cjs foundry:compile
node .yarn/releases/yarn-3.2.3.cjs foundry:test
```

Network checks need `foundry:doctor` first. Every claim in a handoff must include the command and its final output.
