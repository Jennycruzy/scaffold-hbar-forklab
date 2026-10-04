# Hedera testnet proof

All values in this document come from Hedera testnet transactions or the public testnet Mirror Node. No local fork result is presented as testnet evidence.

## Current RecurringBuy deployment

Deployed on 4 October 2026 from commit `05ad123` with `yarn foundry:deploy --network hedera_testnet`, which deploys
both contracts and writes them to `packages/nextjs/contracts/deployedContracts.ts`.

| Contract | Contract ID | EVM address | Deploy transaction | Block | Gas used |
| --- | --- | --- | --- | --- | --- |
| `RecurringBuy` | `0.0.10861899` | `0xdad8de7d8bf7e4e50d03a2e3aa03f57dbd5c782d` | `0x237e743778372cc1c20e7b629d0a033913b6f3a45bbf9edae1979929ce833ebc` | `41360564` | `3276665` |
| `RecurringBuyFactory` | `0.0.10861902` | `0xcd390480b9beb229b1da688000f3bd82009503a6` | `0xe95ed811ad7878f105be197db4153d11c620c545833ea3e45fd405a2574dd415` | `41360568` | `3627805` |

- [RecurringBuy on Hashscan](https://hashscan.io/testnet/contract/0.0.10861899)
- [Mirror Node contract results](https://testnet.mirrornode.hedera.com/api/v1/contracts/0.0.10861899/results?order=desc)
- [Mirror Node contract logs](https://testnet.mirrornode.hedera.com/api/v1/contracts/0.0.10861899/results/logs?order=asc)

`executionGas()` reads `2500000` (the new default). Owner `0x5F49ae0CFfe25d23Bf63B2Aa6B8bcFe2160e2AE2`. The
frontend status endpoint and `/vault` use these checked-in addresses when no environment override is set.

## Successful scheduled execution (4 October 2026)

Owner transactions, all `SUCCESS`:

| Step | Transaction hash | Gas used |
| --- | --- | --- |
| Owner `associate()` on `tokenOut` | `0x85bbae2a768af79da86f0a359738b27f8055547683a897e2f8881d70f58d8e88` | `726488` |
| Owner `approve(vault, 1)` | `0x762167a14afc0e15da16039a49d93a042ccc6c7300063bf3876b6407f6c4055d` | `726996` |
| `configure(0x…42E926, 1 HBAR, 60 s, 10000 bps, 7200 s)` | `0x405c5255534af85d16d817bada0fce38f3ffb7d9745ffb9c0ae0b760cb48e458` | `138194` |
| `deposit()` 15 HBAR | `0xc496956104b1c8f06dbe1b124a9cf76081675e451e1dd8b8f937c4d3e37b78aa` | `23419` |
| `start()` (vault association + first `scheduleCall`) | `0xdc8d8d60398d2af48fd530ed63605912e11afd40fa1277cc89f4c64bbf9b86da` | `2265008` |

Two consecutive HSS-triggered runs then completed. Each scheduled transaction was paid by the vault
(`0.0.10861899`), called `execute()`, created the next schedule first, and emitted `Bought`:

| Run | Schedule ID | Executed (consensus) | Scheduled transaction | Gas used / limit | Fee (tinybars) | HBAR in | Tokens out | Next schedule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `0.0.10861986` | `1791146026.000478548` | `0.0.7314364-1791145964-792484791` nonce `53` | `1684515 / 2500000` | `138130230` | `100000000` | `31690` | `0.0.10861999` |
| 2 | `0.0.10861999` | `1791146085.038525208` | `0.0.7314364-1791145964-792484791` nonce `107` | `1667415 / 2500000` | `136728030` | `100000000` | `31677` | `0.0.10862015` |

- Run 1 contract result: `0x6046b8d16a041752073cf84095eea93bfcf767f9167030d8fed6fcd8bbf3b7e1`
- Run 2 contract result: `0xcac95a0efb96ce0fe0807b40524840a00dde1925621b9dad53a023f8b8581308`
- [Schedule 0.0.10861986](https://testnet.mirrornode.hedera.com/api/v1/schedules/0.0.10861986),
  [Schedule 0.0.10861999](https://testnet.mirrornode.hedera.com/api/v1/schedules/0.0.10861999)

Each fee equals `gas_used × 82` tinybars. The vault balance fell from 15.0 to 12.6186977 and then 10.2514174 HBAR:
one HBAR swapped per run plus the gas fee. Neither run emitted `PurchaseFailed`, and the chain kept scheduling after
run 2 (`0.0.10862015`, `0.0.10862028`). Both runs used about 1.67–1.68M gas, above the old 1,500,000 limit that caused
the failed run below. The `Bought` oracle amount is `103683` against a pool amount of about `31690`: the test token's
pool is far from Supra's HBAR price, which is why this run uses the 10000 bps deviation setting described in the
README.

## Earlier deployments

The vault from the failed first run (details under "Failed first run" below):

- Contract ID: `0.0.10858982`
- EVM address: `0xf75d7f902a8ce0e8a21bbf51bd7bf66420eba9a5`
- Ethereum transaction hash: `0xabcca772a9c931768ec3d6451c61412c69fbfe145021be5f873180da2f4ecf2e`
- Consensus timestamp: `1791128818.745932959`
- Result: `SUCCESS`

The previous Bonzo-enabled deployment remains historical evidence and is not the frontend's current address:

- Contract ID: `0.0.10849548`
- EVM address: `0x3dd43acb0c5b3aac6540b3cbed0ae5c021317350`
- Ethereum transaction hash: `0xf53f088d8b2ca22bfaeb7d69e957c6bed295b5cfebce734e2eed4deade3e19da`
- Hedera transaction ID: `0.0.7314364-1791073354-466970155`
- Consensus timestamp: `1791073361.081602104`
- Result: `SUCCESS`

The earlier pre-Bonzo deployment remains historical evidence:

- Contract ID: `0.0.10847446`
- EVM address: `0xed1fc023e00dab72ae2a11e7965eaa1dc42bdfa3`
- Ethereum transaction hash: `0xa542b4e076c756fa7a82574a51a118485dbd0ecf58457f14ab664ba412f213bd`
- Consensus timestamp: `1791062333.855506104`
- Result: `SUCCESS`

## Failed first run (vault 0.0.10858982)

That vault was associated with the selected token, approved for one base unit by the owner, configured for
one-HBAR purchases every 60 seconds, funded with 5 HBAR, and started. The owner transactions were:

- Approval: `0x202b48af35d06988c03ff245bb95d5f7ce220ae064b788735e336b2cb59dae3b`
- Configuration: `0x6f1e71552985c1a345648ec976264c65a25558fc5650a7edd65a16aa673011fc`
- Funding: `0xdf4afa67413696751ee8b7f085ba7aa772a1652fcffb462e01d9569416a5ecc1`
- Start: `0xa53f5a322982243e2535404014c99bc711c20f8e27a522b2cc20cb0166f07dae`

The first real schedule was created successfully, reached its expiry, and did not complete the target call:

- Schedule ID: `0.0.10859462`
- Schedule creation consensus timestamp: `1791131424.276651622`
- Expiry and `executed_timestamp`: `1791131482.003931040`
- Payer: `0.0.10858982`
- Scheduled transaction ID: `0.0.7314364-1791131417-479683990`
- Scheduled nonce: `53`
- Scheduled result: `CONTRACT_REVERT_EXECUTED`
- Scheduled execution fee: `122894282` tinybars
- [Mirror schedule record](https://testnet.mirrornode.hedera.com/api/v1/schedules/0.0.10859462)
- [Mirror transaction record](https://testnet.mirrornode.hedera.com/api/v1/transactions/0.0.7314364-1791131417-479683990?nonce=53)

The vault had `lastRunAt == 0`, no token fill, and no replacement schedule after expiry. No second execution is
claimed.

### Root cause of the failed run

The Mirror Node contract result for the scheduled call is
`/api/v1/contracts/0.0.10858982/results/1791131482.003931040` (hash
`0xfe31c59840eb9a19cae5b5f488cd1a18340ff8f52f213fb128f319a84758541a`): `gas_limit` 1,500,000, `gas_used`
1,480,654, `result` `CONTRACT_REVERT_EXECUTED`, empty `error_message`. Its call trace,
`/api/v1/contracts/results/0xfe31c598…541a/actions`, shows every step of the run succeeding until the vault tried to
create the next schedule:

```text
depth op          from      -> to        gas        used       result  input
0     CALL        a5b1e6    -> a5b1e6    1478936    1459590    REVERT  0x61461954 execute()
1     STATICCALL  a5b1e6    -> 28a99a    1428896       7905    OUTPUT  0x89b94ea2 Supra getSvalue
1     STATICCALL  a5b1e6    -> 42e926    1410103       2607    OUTPUT  0x313ce567 decimals
1     STATICCALL  a5b1e6    -> 004b40    1399284       8728    OUTPUT  0xd06ca61f getAmountsOut
1     CALL        a5b1e6    -> 004b40    1373886     117613    OUTPUT  0x7ff36ab5 swapExactETHForTokens
1     STATICCALL  a5b1e6    -> 42e926    1256247       2607    OUTPUT  0x70a08231 balanceOf = 0x7bca (31,690)
1     CALL        a5b1e6    -> 42e926    1248212      15284    OUTPUT  0xa9059cbb transfer(owner) = true
1     STATICCALL  a5b1e6    -> 00016b    1225164       2607    OUTPUT  0xdfb4a999 hasScheduleCapacity = true
1     CALL        a5b1e6    -> 00016b    1221011    1221011    ERROR   0x6f5bfde8 scheduleCall -> "INSUFFICIENT_GAS"
```

The error data `0x494e53554646494349454e545f474153` is ASCII `INSUFFICIENT_GAS`. The payer frame, the
`msg.sender == address(this)` guard, the Supra read, the quote, the real SaucerSwap swap, and the HTS owner
transfer all worked on testnet. The failing step was the HSS `scheduleCall` for the next run. In the `start()`
transaction (`0xa53f5a32…7dae`) the same `scheduleCall` used **1,409,649** gas and `associateToken` used
**705,424** gas, so a 1,500,000 limit cannot pay for a purchase plus a re-schedule. Because the re-schedule was the
last step, its failure reverted the whole run, including the successful swap.

The execution fee was `122,894,282` tinybars `= 83 × 1,480,654`; the Mirror Node fee schedule reports a
ContractCall gas price of 83 tinybars at that timestamp (`/api/v1/network/fees?timestamp=1791131482.003931040`).

Changes made in response, proven by the successful run above:

- `RecurringBuy.executionGas` defaults to 2,500,000 and is owner-configurable while stopped.
- `execute()` schedules the next run first, then runs the purchase in a guarded self-call that keeps 50,000 gas in
  reserve; a failed purchase emits `PurchaseFailed(reason)` and the schedule chain continues.
- `ForklabHss` charges the measured 1,409,649 gas for each schedule creation (and fails the frame when it cannot be
  paid), and requires payers to hold a gas reservation at the full limit, and charges `gasUsed × 83` tinybars at execution.
- `test_testnetFailureGasLimitCannotFundRescheduleAndPurchase` reproduces the 1,500,000-gas shortfall on the
  pinned mainnet fork.

Hashscan pages were not checked from the command line because Hashscan returned HTTP 404 to scripted requests; the
Mirror Node records above are the verified source.
