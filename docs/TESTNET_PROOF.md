# Hedera testnet proof

All values in this document come from Hedera testnet transactions or the public testnet Mirror Node. No local fork result is presented as testnet evidence.

## Current RecurringBuy deployment

- Deployed: 4 October 2026
- Contract ID: `0.0.10849548`
- EVM address: `0x3dd43acb0c5b3aac6540b3cbed0ae5c021317350`
- Ethereum transaction hash: `0xf53f088d8b2ca22bfaeb7d69e957c6bed295b5cfebce734e2eed4deade3e19da`
- Hedera transaction ID: `0.0.7314364-1791073354-466970155`
- Consensus timestamp: `1791073361.081602104`
- Block: `41325250`
- Gas used: `3091001`
- Charged transaction fee: `256553083` tinybars
- [Contract on Hashscan](https://hashscan.io/testnet/contract/0.0.10849548)
- [Deployment transaction on Hashscan](https://hashscan.io/testnet/transaction/1791073361.081602104?tid=0.0.7314364-1791073354-466970155)
- [Mirror Node contract record](https://testnet.mirrornode.hedera.com/api/v1/contracts/0.0.10849548)
- [Mirror Node contract result](https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0xf53f088d8b2ca22bfaeb7d69e957c6bed295b5cfebce734e2eed4deade3e19da)

Mirror Node result fields:

```json
{
  "hash": "0xf53f088d8b2ca22bfaeb7d69e957c6bed295b5cfebce734e2eed4deade3e19da",
  "address": "0x3dd43acb0c5b3aac6540b3cbed0ae5c021317350",
  "contract_id": "0.0.10849548",
  "result": "SUCCESS",
  "block_number": 41325250,
  "gas_used": 3091001,
  "timestamp": "1791073361.081602104"
}
```

The contract endpoint reports `deleted: false`. `eth_getCode` returned 13,868 bytes of runtime bytecode, and the
generated frontend ABI contains `configureBonzo`, `bonzoPool`, `sweepToBonzo`, `BonzoSweepConfigured`, and
`SweptToBonzo`.

The transaction link uses Hashscan's contract-result format: the consensus timestamp is the path and the payer transaction ID is the `tid` query parameter. The public Mirror Node responses independently verify the same deployment.

The production frontend's status endpoint used the checked-in deployment without an environment override and
returned:

```json
{
  "online": true,
  "configured": true,
  "address": "0x3dd43acb0c5b3aac6540b3cbed0ae5c021317350",
  "running": false,
  "nextRunAt": 0,
  "lastRunAt": 0,
  "nextSchedule": "0x0000000000000000000000000000000000000000",
  "balanceTinybars": "0",
  "lastScheduleStatus": 0,
  "mirrorOk": true,
  "runCount": 1
}
```

### Previous deployment

The earlier pre-Bonzo deployment remains historical evidence and is not the frontend's current address:

- Contract ID: `0.0.10847446`
- EVM address: `0xed1fc023e00dab72ae2a11e7965eaa1dc42bdfa3`
- Ethereum transaction hash: `0xa542b4e076c756fa7a82574a51a118485dbd0ecf58457f14ab664ba412f213bd`
- Consensus timestamp: `1791062333.855506104`
- Result: `SUCCESS`

## Scheduled execution evidence

The current vault has been deployed but has not yet been configured, funded, or started. Schedule IDs and execution transaction IDs will be added only after those transactions succeed on testnet.
