# Verified network facts

This file records commands run against the pinned toolchain and live Hedera services. Values below are observations, not placeholders.

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

Command:

```text
forge test --fork-url https://mainnet.hashio.io/api --chain-id 295 --fork-block-number 100579000 --fork-retries 3 --fork-retry-backoff 1000 --ffi --match-path test/fork/SaucerSwapMainnet.t.sol -vv
```

Output summary:

```text
Suite result: ok. 4 passed; 0 failed; 0 skipped
```

## Hedera and SaucerSwap addresses

| Item | Address or value | Verification |
| --- | --- | --- |
| HTS system contract | `0x0000000000000000000000000000000000000167` | hedera-forking v0.1.2 source and fork setup |
| HSS emulator address | `0x000000000000000000000000000000000000016b` | HIP-1215 emulator setup |
| Mainnet SaucerSwap V1 router | `0x00000000000000000000000000000000002e7a5d` | `cast call` and fork tests |
| Mainnet WHBAR token | `0x0000000000000000000000000000000000163b5a` | Mirror Node token `0.0.1456986` |
| Mainnet WHBAR helper | `0x0000000000000000000000000000000000163b59` | Mirror Node account `0.0.1456985` |
| Mainnet USDC | `0x000000000000000000000000000000000006f89a` | Mirror Node token `0.0.456858` |
| Mainnet SAUCE | `0x00000000000000000000000000000000000b2ad5` | Mirror Node token `0.0.731861` |
| Mainnet USDC-WHBAR pair | `0xdb34c1ef944883f0e5a2fc18b6c1978b088bd31d` | `getReserves()` fork proof |

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
