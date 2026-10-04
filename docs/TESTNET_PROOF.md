# Hedera testnet proof

All values in this document come from Hedera testnet transactions or the public testnet Mirror Node. No local fork result is presented as testnet evidence.

## Current RecurringBuy deployment

- Deployed: 4 October 2026
- Contract ID: `0.0.10858982`
- EVM address: `0xf75d7f902a8ce0e8a21bbf51bd7bf66420eba9a5`
- Ethereum transaction hash: `0xabcca772a9c931768ec3d6451c61412c69fbfe145021be5f873180da2f4ecf2e`
- Hedera transaction ID: `0.0.7314364-1791128815-216901794`
- Consensus timestamp: `1791128818.745932959`
- Block: `41352354`
- Gas used: `3072180`
- Charged transaction fee: `254990940` tinybars
- [Contract on Hashscan](https://hashscan.io/testnet/contract/0.0.10858982)
- [Deployment transaction on Hashscan](https://hashscan.io/testnet/transaction/1791128818.745932959?tid=0.0.7314364-1791128815-216901794)
- [Mirror Node contract record](https://testnet.mirrornode.hedera.com/api/v1/contracts/0.0.10858982)
- [Mirror Node contract result](https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0xabcca772a9c931768ec3d6451c61412c69fbfe145021be5f873180da2f4ecf2e)

Mirror Node result fields:

```json
{
  "hash": "0xabcca772a9c931768ec3d6451c61412c69fbfe145021be5f873180da2f4ecf2e",
  "address": "0xf75d7f902a8ce0e8a21bbf51bd7bf66420eba9a5",
  "contract_id": "0.0.10858982",
  "result": "SUCCESS",
  "block_number": 41352354,
  "gas_used": 3072180,
  "timestamp": "1791128818.745932959"
}
```

The contract endpoint reports `deleted: false`. `eth_getCode` returned 13,781 bytes of runtime bytecode, and the
generated frontend ABI contains `configureBonzo`, `bonzoPool`, `sweepToBonzo`, `BonzoSweepConfigured`, and
`SweptToBonzo`.

The transaction link uses Hashscan's contract-result format: the consensus timestamp is the path and the payer transaction ID is the `tid` query parameter. The public Mirror Node responses independently verify the same deployment.

The production frontend's status endpoint uses this checked-in deployment when no environment override is set.
The schedule evidence below records that the first live run did not complete; no successful recurring execution
is claimed here.

On-chain state read on 4 October 2026 with `eth_call` through `https://testnet.hashio.io/api` after the failed run
(an earlier status snapshot in this file reported `nextSchedule` as zero and has been removed because it did not
match the chain):

```text
running            true
nextSchedule       0x0000000000000000000000000000000000A5B3C6   (schedule 0.0.10859462, already executed)
nextRunAt          1791131482
lastRunAt          0
lastScheduleStatus 22
tokenOut           0x000000000000000000000000000000000042E926
amountPerBuy       100000000
interval           60
maxDeviationBps    10000
maxPriceAge        7200
hbarBalance        377105718
owner              0x5F49ae0CFfe25d23Bf63B2Aa6B8bcFe2160e2AE2
```

### Earlier deployments

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

## Scheduled execution evidence

The corrected vault was associated with the selected token, approved for one base unit by the owner, configured for
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

Changes made in response (local and fork proofs; a new testnet run is still required):

- `RecurringBuy.executionGas` defaults to 2,500,000 and is owner-configurable while stopped.
- `execute()` schedules the next run first, then runs the purchase in a guarded self-call that keeps 50,000 gas in
  reserve; a failed purchase emits `PurchaseFailed(reason)` and the schedule chain continues.
- `ForklabHss` charges the measured 1,409,649 gas for each schedule creation (and fails the frame when it cannot be
  paid), and requires payers to hold a gas reservation at the full limit, and charges `gasUsed × 83` tinybars at execution.
- `test_testnetFailureGasLimitCannotFundRescheduleAndPurchase` reproduces the 1,500,000-gas shortfall on the
  pinned mainnet fork.

Hashscan pages were not checked from the command line because Hashscan returned HTTP 404 to scripted requests; the
Mirror Node records above are the verified source.
