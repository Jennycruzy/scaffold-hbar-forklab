# Verified network facts

This file records commands run against the pinned toolchain and live Hedera services. Values below are observations, not placeholders.

## Latest HEAD checks

After the Bonzo sweep change at commit `403c344`, the repository-side checks returned:

```text
$ node .yarn/releases/yarn-3.2.3.cjs lint
✔ No ESLint warnings or errors
All matched files use Prettier code style!

$ node .yarn/releases/yarn-3.2.3.cjs next:check-types
exit 0

$ node .yarn/releases/yarn-3.2.3.cjs next:build
✓ Compiled successfully
✓ Generating static pages (14/14)

$ node .yarn/releases/yarn-3.2.3.cjs foundry:compile
Compiler run successful!

$ node .yarn/releases/yarn-3.2.3.cjs foundry:test
17 tests passed, 0 failed, 3 skipped (20 total tests)

$ node scripts/validate-template.mjs
template.json: valid TemplateManifestSchema
```

The latest-HEAD fresh-template installer run and latest full network-fork reruns remain separate acceptance work; the earlier fresh-copy results below are retained with their original commit instead of being relabeled.

## Template manifest

The repository validator mirrors `TemplateManifestSchema` from create-scaffold-hbar `src/types.ts` and parses the checked-in manifest with Zod:

```text
$ node scripts/validate-template.mjs
template.json: valid TemplateManifestSchema
```

## Fresh-copy acceptance run

On 3 October 2026, commit `41c9ee2` was exported with `git archive HEAD` into a temporary directory. Its `packages/foundry/lib` directory was rebuilt from the URLs in `.gitmodules` at the revisions in `foundry.lock`, matching the template installer's library-resolution inputs. The temporary copy then produced:

```text
$ yarn install --immutable
➤ YN0000: Completed in 2m 42s
➤ YN0000: Done with warnings in 2m 48s

$ yarn lint
✔ No ESLint warnings or errors
All matched files use Prettier code style!

$ yarn next:check-types
# exit 0, no output

$ yarn next:build
✓ Generating static pages (14/14)
✓ Finalizing page optimization

$ yarn foundry:compile
Compiling 56 files with Solc 0.8.33
Compiler run successful!

$ yarn foundry:test
Ran 6 test suites: 15 tests passed, 0 failed, 3 skipped (18 total tests)

$ yarn foundry:test:fork
Ran 6 test suites in 138.36s: 28 tests passed, 0 failed, 1 skipped (29 total tests)

$ yarn foundry:test:testnet-fork
Ran 6 test suites in 157.96s: 17 tests passed, 0 failed, 2 skipped (19 total tests)

$ yarn manifest:validate
template.json: valid TemplateManifestSchema
```

A separate archive was used for the other declared package manager:

```text
$ npm install
added 1330 packages, and audited 1333 packages in 7m
51 vulnerabilities (27 moderate, 21 high, 3 critical)
```

Installation succeeded. The reported findings are in the resolved dependency tree and were not rewritten with `npm audit fix --force`, which could make incompatible dependency changes. Yarn also reported peer-dependency warnings. The repository requires Node `>=20.18.3`; this run used Node `20.20.2`. One transitive npm package (`ansi-styles@7.0.0`) warned that it prefers Node 22 or newer, but did not prevent installation or any Yarn build/check above.

The production build was started without a wallet or network configuration. `/`, `/vault`, `/lab`, `/debug`, `/blockexplorer`, `/api/hedera/account`, `/api/lab/fast-forward`, `/api/lab/run-due`, and `/api/recurring-buy/status` each returned HTTP 200. The status APIs returned explicit offline/unconfigured JSON instead of throwing.

### Local Anvil runner

The local launcher was run against pinned mainnet block `100579000`. The official `@hashgraph/system-contracts-forking/forwarder` supplied HTS state, and the launcher installed HSS with `anvil_setCode`:

```text
Forklab ready at http://127.0.0.1:8545: mainnet block 100579000, HTS forwarder http://127.0.0.1:295, HSS 0x000000000000000000000000000000000000016b
$ cast call 0x000000000000000000000000000000000006f89a 'symbol()(string)' --rpc-url http://127.0.0.1:8545
"USDC"
$ cast call 0x000000000000000000000000000000000000016b 'configuration()(uint256,uint256,uint256,uint256)' --rpc-url http://127.0.0.1:8545
10
15000000
5356800
0
```

An HSS schedule targeting a fork-local fixture was then advanced by the `/api/lab/fast-forward` route and executed by `/api/lab/run-due`:

```json
{"ok":true,"pending":["0x00000000000000000000000000000000f0000000"]}
{"ok":true,"seconds":3600,"rpc":"http://127.0.0.1:8545"}
{"ok":true,"executed":[{"schedule":"0x00000000000000000000000000000000f0000000","targetHash":"0xfe025cb093bae57d00ce1302d3ceae93a518a00bfa94944f4589190b134970d2","settlementHash":"0x15f3d656da47a17192320ca4a99d904441ec40e05cc0bd424678abf7e95426e6","status":"22"}],"waiting":[]}
```

The target's recorded marker was `77`, and `pending()` returned `[]` after settlement. Anvil mode deliberately leaves Foundry-only schedule-address delete forwarders disabled; direct `deleteSchedule(address)` remains available.

Tracked secret-name checks found no `.env`, keystore, or `.pem` file. Hex-string review found only the documented Supra feed identifier, a documented bytecode excerpt, and bytecode fixtures under `research/fork-repros/`; none is a private key. The banned-word check is empty across authored files and commit messages. The checked-in Yarn 3.2.3 release is generated third-party code and is excluded from the authored-file text check.

## Toolchain and networks

Command:

```text
forge --version
```

Output:

```text
forge Version: 1.5.0-v1.5.0
```

Pinned library revisions:

```text
forge-std v1.15.0       0844d7e1fc5e60d77b68e469bff60265f236c398
hedera-forking v0.1.2   1de85d382e44170f974cb6de2ff211fecbc88b37
openzeppelin v5.6.1     5fd1781b1454fd1ef8e722282f86f9293cacf256
solidity-bytes-utils    v0.8.4 / f4413cd6137b78403e3a1156bee6aceab46b46fa
```

Command:

```text
cast chain-id --rpc-url https://mainnet.hashio.io/api
cast chain-id --rpc-url https://testnet.hashio.io/api
```

Output:

```text
295
296
```

Command:

```text
node packages/foundry/scripts-js/preflight.js --network mainnet
```

Output:

```text
Forklab doctor: Foundry 1.5.0, mainnet RPC.
OK: forge 1.5.0, cast, curl, bash, and mainnet eth_chainId.
```

The current mainnet fork snapshot is block `100579000`. Its Mirror Node block timestamp, printed by the adapter during the fork proof, is `1790821038.006379925`. The testnet snapshot is `41202267`.

### Live schedule-capacity probe

`scripts-js/probeScheduleLimits.js` reads one testnet block and submits every `hasScheduleCapacity` query with that block tag. On 3 October 2026 it selected block `41300691`, timestamp `1791023114`, and returned:

| Expiry delta | 100,000 gas | 1,000,000 gas | 15,000,000 gas |
| -----------: | :---------: | :-----------: | :------------: |
|          `0` |    false    |     false     |     false      |
|          `1` |    false    |     false     |     false      |
|  `5,356,800` |    true     |     true      |      true      |
|  `5,356,801` |    true     |     true      |      true      |

The two edge pairs cannot be interpreted as an exact boundary measurement through public Hashio: the HSS capacity query evaluates against advancing consensus time even when `eth_call` carries a historical block tag. Network delay makes `now+1` expire before evaluation and brings both horizon calls back inside the limit. The script records the exact requested calls, but these results do not justify changing Forklab's inclusive `5,356,800`-second emulator boundary. A transaction-level testnet probe with a funded signer is still required to distinguish the horizon by one second.

The current Hiero `SchedulingConfig.java` declares `maxExpirationFutureSeconds = 5356800` at line 25 and `maxExecutionsPerUserTxn = 100` at line 15: https://github.com/hiero-ledger/hiero-consensus-node/blob/main/hedera-node/hedera-config/src/main/java/com/hedera/node/config/data/SchedulingConfig.java#L15-L25. That current file contains no per-second gas setting, so it does not support the earlier claim that 15,000,000 is a scheduling configuration default. The live read probe confirms that an otherwise-empty second accepts an individual 15,000,000-gas request; proving the aggregate per-second ceiling requires creating competing schedules and remains part of the funded testnet work.

Command:

```text
forge test --fork-url https://mainnet.hashio.io/api --chain-id 295 --fork-block-number 100579000 --fork-retries 3 --fork-retry-backoff 1000 --ffi --match-path test/fork/SaucerSwapMainnet.t.sol -vv
```

Output summary:

```text
Suite result: ok. 5 passed; 0 failed; 0 skipped
```

## Hedera and SaucerSwap addresses

| Item                         | Address or value                                                                            | Verification                                         |
| ---------------------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| HTS system contract          | `0x0000000000000000000000000000000000000167`                                                | hedera-forking v0.1.2 source and fork setup          |
| HSS emulator address         | `0x000000000000000000000000000000000000016b`                                                | HIP-1215 emulator setup                              |
| Mainnet SaucerSwap V1 router | `0x00000000000000000000000000000000002e7a5d`                                                | `cast call` and fork tests                           |
| Mainnet WHBAR token          | `0x0000000000000000000000000000000000163b5a`                                                | Mirror Node token `0.0.1456986`                      |
| Mainnet WHBAR helper         | `0x0000000000000000000000000000000000163b59`                                                | Mirror Node account `0.0.1456985`                    |
| Mainnet USDC                 | `0x000000000000000000000000000000000006f89a`                                                | Mirror Node token `0.0.456858`                       |
| Mainnet SAUCE                | `0x00000000000000000000000000000000000b2ad5`                                                | Mirror Node token `0.0.731861`                       |
| Mainnet USDC-WHBAR pair      | `0xdb34c1ef944883f0e5a2fc18b6c1978b088bd31d`                                                | `getReserves()` fork proof                           |
| Testnet SaucerSwap V1 router | `0x0000000000000000000000000000000000004b40`                                                | factory `0x00000000000000000000000000000000000026e7` |
| Testnet WHBAR helper/token   | `0x0000000000000000000000000000000000003ad1` / `0x0000000000000000000000000000000000003ad2` | helper `token()` proof                               |
| Testnet SAUCE                | `0x0000000000000000000000000000000000120f46`                                                | token `0.0.1183558`, `symbol()` = `SAUCE`            |
| Testnet WHBAR-SAUCE pair     | `0xfe7cc3ceb7b1128bfc3889184e2d5561bf74bfb3`                                                | nonzero reserves at block `41202267`                 |

Command:

```text
cast call --rpc-url https://mainnet.hashio.io/api 0x00000000000000000000000000000000002e7a5d 'factory()(address)'
cast call --rpc-url https://mainnet.hashio.io/api 0x00000000000000000000000000000000002e7a5d 'WHBAR()(address)'
```

Output:

```text
0x0000000000000000000000000000000000103780
0x0000000000000000000000000000000000163B59
```

The router returns a wrapper helper, not the token used in swap paths. The
helper resolves the real token on both networks:

```text
$ cast call --rpc-url https://mainnet.hashio.io/api 0x0000000000000000000000000000000000163B59 'token()(address)'
0x0000000000000000000000000000000000163B5a

$ cast call --rpc-url https://testnet.hashio.io/api 0x0000000000000000000000000000000000003aD1 'token()(address)'
0x0000000000000000000000000000000000003aD2
```

The router proof uses the real factory, pair reserves, WHBAR helper, USDC token, and SAUCE token. Test-account funding uses `vm.deal` only before the swap; no pool, oracle, or reserve storage is edited.

At pinned testnet block `41202267`, the WHBAR-SAUCE pair reserves were `(7668163817922, 4220285345731)` and the router quote for one HBAR was `[100000000, 54870629]`. The testnet-fork suite executes that fill and checks the exact quote. Its RecurringBuy test then executes a scheduled run against the same real pool and Supra feed; because SAUCE is not USD-denominated, the vault correctly emits `SkippedDeviation` and reschedules instead of pretending this is a stablecoin fill.

```text
Ran 2 tests for test/fork/SaucerSwapTestnet.t.sol:SaucerSwapTestnetTest
[PASS] test_testnetHbarToSauceMatchesRouterQuote()
[PASS] test_testnetRecurringBuyRunsAndReschedules()
Suite result: ok. 2 passed; 0 failed; 0 skipped
```

### Mirror Node snapshot root cause

The original token-swap reproduction failed with `UniswapV2: K` because the pair's `getReserves()` came from fork block `100579000`, while hedera-forking's emulated HTS `balanceOf` fetched the latest Mirror Node balance. Those values described different points in time. For the USDC/WHBAR pair `0xdb34c1ef944883f0e5a2fc18b6c1978b088bd31d`, the unbounded account response reported USDC `280690610677`, while the pair reserve at the pinned block was `283737632828`.

```text
cast call --rpc-url https://mainnet.hashio.io/api --block 100579000 \
  0xdB34c1Ef944883f0e5A2fC18B6C1978B088bD31d 'getReserves()((uint112,uint112,uint32))'
(283737632828, 272630825035359, 1790820743)

curl -sS 'https://mainnet-public.mirrornode.hedera.com/api/v1/accounts/0xdB34c1Ef944883f0e5A2fC18B6C1978B088bD31d?transactions=false'
... "token_id":"0.0.456858","balance":280690610677 ...
```

Forklab resolves the fork block once when `ForklabMirrorNode` is constructed and applies its `.timestamp.to` value (`1790821038.006379925`) to every supported HTS read. The corrected query returns the exact reserve:

```text
curl -sS 'https://mainnet-public.mirrornode.hedera.com/api/v1/tokens/0.0.456858/balances?account.id=0.0.1462797&timestamp=lte:1790821038.006379925'
{"timestamp":"1790820958.778317875","balances":[{"account":"0.0.1462797","balance":283737632828,"decimals":6}],"links":{"next":null}}
```

The adapter now retains that original fork block even after a test calls `vm.roll` or `vm.warp`, and logs URLs only when `FORKLAB_MIRROR_LOG_URLS=true`. It deliberately does not write its response mapping: HTS invokes these reads through `STATICCALL`, so a cache write causes `StateChangeDuringStaticCall`.

Warm-cache acceptance run on 3 October 2026 (the audit's first run was 4m29s for the then-current 11 fork tests):

```text
$ /usr/bin/time -p forge test --fork-url https://mainnet.hashio.io/api --chain-id 295 --fork-block-number 100579000 --fork-retries 3 --fork-retry-backoff 1000 --ffi
Ran 6 test suites in 150.67s (289.96s CPU time): 31 tests passed, 0 failed, 0 skipped (31 total tests)
real 160.01
user 20.58
sys 14.75
```

### Protobuf supply-key repair

The real mainnet tokens that require Forklab's contract-key repair are WHBAR (`0.0.1456986`) and SAUCE (`0.0.731861`). Their pinned Mirror Node records contain these values:

```json
{"token_id":"0.0.1456986","symbol":"WHBAR","supply_key":{"_type":"ProtobufEncoded","key":"0a0418d9f658"}}
{"token_id":"0.0.731861","symbol":"SAUCE","supply_key":{"_type":"ProtobufEncoded","key":"0a0418fbe241"}}
```

The protobuf contract IDs decode to `0.0.1456985` (the WHBAR helper, `0x0000000000000000000000000000000000163B59`) and `0.0.1077627` (`0x000000000000000000000000000000000010717b`). The repair targets the layout declared by hedera-forking v0.1.2, revision `1de85d382e44170f974cb6de2ff211fecbc88b37`: `_tokenInfo` is at `contracts/HtsSystemContract.sol:31`. `test_protobufSupplyKeyRepairMatchesPinnedStorageLayout` reads the calculated supply-contract slot for both real tokens and fails if that dependency layout changes.

The legacy HTS wipe selectors were checked against verbose traces of both real SaucerSwap paths on the pinned mainnet fork: `wipeTokenAccount(address,address,int64)` = `0xefef57f9`, its `uint64` variant = `0x1fc4cf6c`, and `wipeTokenAccountNFT(address,address,int64[])` = `0xf7f38e26`. Neither the HBAR→USDC trace nor the USDC→WHBAR→SAUCE trace contained any of those selectors. Both tests passed (2 passed, 0 failed), so Forklab does not implement an unobserved wipe compatibility shim.

## Selectors and response codes

Command:

```text
cast sig 'scheduleCall(address,uint256,uint256,uint64,bytes)'
cast sig 'scheduleCallWithPayer(address,address,uint256,uint256,uint64,bytes)'
cast sig 'executeCallOnPayerSignature(address,address,uint256,uint256,uint64,bytes)'
cast sig 'deleteSchedule(address)'
cast sig 'deleteSchedule()'
cast sig 'hasScheduleCapacity(uint256,uint256)'
cast sig 'mintToken(address,uint64,bytes[])'
cast sig 'mintToken(address,int64,bytes[])'
cast sig 'burnToken(address,uint64,int64[])'
```

Output:

```text
0x6f5bfde8
0xe6599c18
0x105772b2
0x72d42394
0xc61dea85
0xdfb4a999
0x278e0b88
0xe0f4059a
0xacb9cff9
```

Command:

```text
curl -sS --max-time 30 https://raw.githubusercontent.com/hashgraph/hedera-protobufs/main/services/response_code.proto | rg -n -C 2 'TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT|TOKEN_NOT_ASSOCIATED_TO_ACCOUNT|SUCCESS ='
```

Output:

```text
SUCCESS = 22
TOKEN_NOT_ASSOCIATED_TO_ACCOUNT = 184
TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT = 194
```

The schedule emulator uses the specified service values: success `22`, invalid contract `16`, expiry-not-future `307`, expiry-too-far `306`, busy expiry `370`, invalid schedule `201`, already-deleted `212`, already-executed `213`, invalid signature `7`, insufficient payer balance `10`, and unauthorized delete `157`.

## Supra HBAR/USD push feed

### Oracle choice

The implementation deliberately uses Supra instead of Pyth. Pyth's upgrade guide says that every Hermes user has needed an API key since 26 August 2026, that signup includes a free trial, and that paid plans cover ongoing use:

```text
https://docs.pyth.network/price-feeds/core/upgrade/preparing
```

An unauthenticated request on 3 Oct 2026 confirms the operational consequence:

```text
curl -sS -i --max-time 30 'https://hermes.pyth.network/v2/updates/price/latest?ids[]=0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43'
```

```text
HTTP/2 401
content-type: text/plain; charset=utf-8
content-length: 12

unauthorized
```

Supra pair `432` is readable from its Hedera push-feed contracts without an API credential. Supra publishes the push feed; tests do not update it. The Pyth requirement to update the oracle with real data before a run is therefore represented here by reading the real on-chain observation at the pinned fork block.

Supra's official network list identifies the Hedera mainnet push-oracle contract as `0xD02cc7a670047b6b012556A88e275c685d25e0c9` and the testnet contract as `0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917`. Its data-pair list identifies HBAR/USD as standard pair `432`.

Supra's network table lists a one-hour push frequency for both Hedera mainnet and Hedera testnet. `RecurringBuy.DEFAULT_MAX_PRICE_AGE` is consequently two hours (`7,200` seconds), above the documented interval. `configure` still accepts an explicit stricter or looser value so tests can exercise stale observations.

```text
https://docs.supra.com/oracles/data-feeds/push-oracle/networks
https://docs.supra.com/oracles/data-feeds/data-feeds-index
```

Two live reads 4 minutes 26 seconds apart did not produce different rounds. That is consistent with the documented one-hour frequency and means the requested "different rounds a few minutes apart" assertion could not be verified in this observation window; no contrary result is claimed.

```text
2026-10-03T01:55:17Z mainnet (1790990299000, 18, 1790990299169, 101869000000000000)
2026-10-03T01:55:17Z testnet (1790989379000, 18, 1790989379167, 102105000000000000)
2026-10-03T01:59:43Z mainnet (1790990299000, 18, 1790990299169, 101869000000000000)
2026-10-03T01:59:43Z testnet (1790989379000, 18, 1790989379167, 102105000000000000)
```

Command:

```text
cast code --rpc-url https://mainnet.hashio.io/api 0xD02cc7a670047b6b012556A88e275c685d25e0c9
cast code --rpc-url https://testnet.hashio.io/api 0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917
```

Both networks returned the same non-empty proxy bytecode beginning with:

```text
0x608060405236156054577f360894a13ba1a3210667c828492db98dca3e2076cc...
```

Command:

```text
cast call --rpc-url https://mainnet.hashio.io/api 0xD02cc7a670047b6b012556A88e275c685d25e0c9 'getSvalue(uint256)((uint256,uint256,uint256,uint256))' 432
cast call --rpc-url https://testnet.hashio.io/api 0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917 'getSvalue(uint256)((uint256,uint256,uint256,uint256))' 432
```

Output on 1 Oct 2026, ordered as `(round, decimals, time, price)`:

```text
(1790864299000 [1.79e12], 18, 1790864299165 [1.79e12], 104495000000000000 [1.044e17])
(1790866000000 [1.79e12], 18, 1790866000120 [1.79e12], 104226500000000000 [1.042e17])
```

The mainnet value represents `$0.104495` per HBAR and the testnet value represents `$0.1042265`, both with 18 decimals. Supra timestamps are milliseconds and `RecurringBuy` converts them to seconds before applying `maxPriceAge`.

The same feed was verified at Forklab's pinned mainnet block:

```text
cast call --rpc-url https://mainnet.hashio.io/api --block 100579000 0xD02cc7a670047b6b012556A88e275c685d25e0c9 'getSvalue(uint256)((uint256,uint256,uint256,uint256))' 432
```

Output:

```text
(1790817499000 [1.79e12], 18, 1790817499120 [1.79e12], 104597000000000000 [1.045e17])
```

The pinned price is `$0.104597` per HBAR. Reading the push feed is an on-chain view call and requires no oracle API credential.

## Bonzo Lend sweep

The official Bonzo contract table lists these lending pools:

```text
Mainnet LendingPool: 0x236897c518996163E7b313aD21D1C9fCC7BA1afc
Testnet LendingPool: 0xf67DBe9bD1B331cA379c44b5562EAa1CE831EbC2
Mainnet USDC aToken:  0xB7687538c7f4CAD022d5e97CC778d0b46457c5DB
```

Source: https://docs.bonzo.finance/hub/developer/bonzo-lend/lend-contracts. `cast code` returned non-empty code for both pool addresses; the mainnet aUSDC contract returned `decimals() = 6`.

`RecurringBuy` includes the owner-controlled `configureBonzo(pool, enabled)` setting and calls `deposit(asset, amount, owner, 0)` after a real SaucerSwap fill when enabled. The pinned mainnet proof reaches the real pool, and the swap and HTS approval succeed, but Bonzo returns `Error(string)` with the exact message `64` before minting aUSDC:

```text
test_bonzoSweepReportsPinnedFrozenReserve()
swap output: 103761 USDC base units
approval: true
Bonzo LendingPool.deposit(USDC, 103761, owner, 0): revert Error("64")
aUSDC owner balance delta: 0
```

The Bonzo data provider reports the USDC reserve as active and frozen at this pinned state. Bonzo's current product documentation also says a deposit requires token association before confirmation. The required successful aUSDC-balance-increase proof cannot be honestly claimed while the live reserve rejects the deposit. The fork test records this exact external blocker and must be rerun as a success proof after Bonzo reopens or provides a supported reserve path.

## RecurringBuy deployment defaults

`Deploy.s.sol` and `DeployRecurringBuy.s.sol` use the verified network constants below, while allowing explicit `RECURRING_BUY_SUPRA` and `RECURRING_BUY_ROUTER` overrides:

```text
Hedera mainnet Supra:      0xD02cc7a670047b6b012556A88e275c685d25e0c9
Hedera mainnet router:     0x00000000000000000000000000000000002E7A5D
Hedera testnet Supra:      0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917
Hedera testnet router:     0x0000000000000000000000000000000000004b40
```

The Supra code/read evidence is in the preceding section. The SaucerSwap router and WHBAR helper calls were verified with:

```text
cast code --rpc-url https://testnet.hashio.io/api 0x0000000000000000000000000000000000004b40
cast call --rpc-url https://testnet.hashio.io/api 0x0000000000000000000000000000000000004b40 'WHBAR()(address)'
cast call --rpc-url https://testnet.hashio.io/api 0x0000000000000000000000000000000000003aD1 'token()(address)'
```

The earlier verified outputs are non-empty router bytecode, WHBAR helper `0x0000000000000000000000000000000000003aD1`, and WHBAR token `0x0000000000000000000000000000000000003aD2`. A token pair with current testnet liquidity still has to be selected during the live proof.

## Owner account used by the fork proof

The fork proof uses Hedera account `0.0.10898016`, whose EVM address was verified at the pinned timestamp:

```text
0xc376f5159300c1b16d2d711cc43afcaf7433b0ee
```

Command:

```text
cast call --rpc-url https://mainnet.hashio.io/api --from 0xc376f5159300c1b16d2d711cc43afcaf7433b0ee 0x000000000000000000000000000000000006f89a 'isAssociated()(bool)'
cast call --rpc-url https://mainnet.hashio.io/api 0x000000000000000000000000000000000006f89a 'balanceOf(address)(uint256)' 0xc376f5159300c1b16d2d711cc43afcaf7433b0ee
```

Output:

```text
true
10000000 [1e7]
```

The owner association check in the deployed flow is backed by the real recipient relationship. HRC-719's `isAssociated()` has no account argument, so the owner EOA must also be checked directly by the deploying client before `start()`; the vault uses a zero-value self-transfer probe to fail before scheduling when receipt is unavailable.

## Passing Forklab proofs

Command:

```text
forge test --offline
```

Output summary:

```text
12 tests passed, 0 failed, 3 skipped (15 total tests)
```

The recurring-buy fork tests use Supra pair `432` directly from the pinned Hedera state. No oracle value is hard-coded into the contract or substituted in test storage.
