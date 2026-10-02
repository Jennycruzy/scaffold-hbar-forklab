# Fork reproductions

Standalone Foundry tests that reproduce the ways local fork testing breaks on current Hedera mainnet.
They live outside `packages/foundry` so they never run as part of the template's test suite.

Run from a scratch Foundry project with `hedera-forking` remapped, Foundry v1.5.0 and `cast` on `PATH`:

```sh
forge test --fork-url https://mainnet.hashio.io/api --chain-id 295 --ffi -vv
```

| Test | Observed on 30 Sep 2026 |
|---|---|
| `test_quote` | SaucerSwap V1 `getAmountsOut` works: 100 HBAR -> 10.519127 USDC |
| `test_usdcRead` | HTS tokens now return EIP-7702 style code `0xef0100…0167`; the emulator rejects the call until the token address is re-etched with the HIP-719 proxy |
| `test_swap` | WHBAR `deposit` calls legacy `mintToken(address,uint64,bytes[])` (`0x278e0b88`), which the emulator does not implement |
| `test_tokenSwap` | Fails with `UniswapV2: K`: pair reserves come from the fork block, emulated balances come from the Mirror Node |
| any test on Foundry 1.8.3 | Forking Hashio fails: the relay rejects the block parameter object Foundry now sends |
