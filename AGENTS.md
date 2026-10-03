# Agent instructions

Forklab is a Foundry-only Scaffold-HBAR template. Keep work reproducible against real Hedera state and leave command output in the relevant evidence document.

## Rules

- Do not fake external systems. Implemented SaucerSwap, Supra, HTS, Mirror Node, HSS, and Bonzo sweep tests use real fork or network state. Bonzo's pinned USDC reserve currently returns `Error("64")`; keep that exact blocker in the proof until a successful live deposit is available.
- Call `Forklab.setUp()` before using HTS or HSS in a fork test.
- Pin the fork block. Record the block, chain id, RPC command, and result in `docs/VERIFIED.md`.
- Use named tinybar constants. One HBAR is `100_000_000` EVM units.
- `deal` may fund a test account before an action, but never edit a pool, oracle, or lending reserve to hide a failure.
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
- `packages/foundry/test/`: offline emulator and protocol tests.
- `packages/foundry/test/fork/`: real mainnet fork tests. Testnet fork coverage is required but is not implemented yet.
- `packages/foundry/scripts-js/`: preflight, block pinning, and live-data helpers.
- `packages/nextjs/app/`: frontend routes.
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

| Failure | Likely cause | Response |
| --- | --- | --- |
| Hashio returns HTTP 400 for a fork | Unsupported Foundry request shape | Use Foundry `v1.5.0` and run the doctor script. |
| HTS call returns empty data | `cast`, `curl`, or FFI is unavailable | Run the doctor script and inspect its first failed check. |
| Token balance differs from a pair reserve | Snapshot timestamps differ | Inspect every Mirror Node URL and the pinned block timestamp. |
| SaucerSwap HBAR swap fails in `mintToken` | Legacy uint64 selector | Extend `ForklabHts` only after a real trace proves the selector. |
| Schedule target sees the wrong sender | Executor did not prank the payer | Assert `msg.sender` in a target fixture and inspect the schedule payer. |
| Schedule stops after a successful run | Payer lacks HBAR for a value or fee | Inspect the schedule status and payer balance. |

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
