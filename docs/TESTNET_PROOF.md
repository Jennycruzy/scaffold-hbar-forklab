# Hedera testnet proof

All values in this document come from Hedera testnet transactions or the public testnet Mirror Node. No local fork result is presented as testnet evidence.

## RecurringBuy deployment

- Deployed: 3 October 2026
- Contract ID: `0.0.10847446`
- EVM address: `0xed1fc023e00dab72ae2a11e7965eaa1dc42bdfa3`
- Ethereum transaction hash: `0xa542b4e076c756fa7a82574a51a118485dbd0ecf58457f14ab664ba412f213bd`
- Hedera transaction ID: `0.0.7314364-1791062325-907461327`
- Consensus timestamp: `1791062333.855506104`
- Block: `41319847`
- Gas used: `2788191`
- [Contract on Hashscan](https://hashscan.io/testnet/contract/0.0.10847446)
- [Deployment transaction on Hashscan](https://hashscan.io/testnet/transaction/1791062333.855506104?tid=0.0.7314364-1791062325-907461327)
- [Mirror Node contract record](https://testnet.mirrornode.hedera.com/api/v1/contracts/0.0.10847446)
- [Mirror Node contract result](https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0xa542b4e076c756fa7a82574a51a118485dbd0ecf58457f14ab664ba412f213bd)

Mirror Node result fields:

```json
{
  "hash": "0xa542b4e076c756fa7a82574a51a118485dbd0ecf58457f14ab664ba412f213bd",
  "address": "0xed1fc023e00dab72ae2a11e7965eaa1dc42bdfa3",
  "contract_id": "0.0.10847446",
  "result": "SUCCESS",
  "block_number": 41319847,
  "gas_used": 2788191,
  "timestamp": "1791062333.855506104"
}
```

The contract endpoint reports `deleted: false`, and `eth_getCode` returned 12,463 bytes of runtime bytecode.

The transaction link uses Hashscan's contract-result format: the consensus timestamp is the path and the payer transaction ID is the `tid` query parameter. The public Mirror Node responses independently verify the same deployment.

## Scheduled execution evidence

The vault has been deployed but has not yet been configured, funded, or started. Schedule IDs and execution transaction IDs will be added only after those transactions succeed on testnet.
