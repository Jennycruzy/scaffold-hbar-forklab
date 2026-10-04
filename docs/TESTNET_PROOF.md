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

```json
{
  "online": true,
  "configured": true,
  "address": "0xf75d7f902a8ce0e8a21bbf51bd7bf66420eba9a5",
  "running": true,
  "nextRunAt": 1791131482,
  "lastRunAt": 0,
  "nextSchedule": "0x0000000000000000000000000000000000000000",
  "balanceTinybars": "377105718",
  "lastScheduleStatus": 22,
  "mirrorOk": true,
  "runCount": 1
}
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

The vault had `lastRunAt == 0`, no token fill, and no replacement schedule after expiry. The public Mirror record
contains no successful contract result for the scheduled call. This is the exact live blocker: the local Forklab
execution path succeeds, while the current testnet scheduled contract call is created and reaches the expiry record
but does not complete the target call. No second execution is claimed.
