#!/usr/bin/env bash
# Checks Forklab's three main claims in about a minute:
#   1. The schedule-service emulator passes its offline test suite.
#   2. On a pinned Hedera mainnet fork, it reproduces the two failures we hit on live testnet.
#   3. The live testnet vault record (six scheduled purchases, then an empty payer) is on the Mirror Node.
#
#   git clone --recurse-submodules https://github.com/Jennycruzy/scaffold-hbar-forklab
#   cd scaffold-hbar-forklab && bash verify.sh
#
# Needs git, curl, and Foundry v1.5.0 (curl -L https://foundry.paradigm.xyz | bash && foundryup -i 1.5.0).
# No wallet, API key, or Node.js install is required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDRY="$ROOT/packages/foundry"
MAINNET_RPC="${HEDERA_MAINNET_RPC_URL:-https://mainnet.hashio.io/api}"
MIRROR="${HEDERA_MIRROR_TESTNET_URL:-https://testnet.mirrornode.hedera.com}/api/v1"
VAULT_ID="0.0.10861899"
export PATH="$HOME/.foundry/bin:$PATH"

bold() { printf '\n\033[1m%s\033[0m\n' "$1"; }
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }
FAILED=0

bold "Forklab verification"
for tool in git curl forge cast; do
  command -v "$tool" > /dev/null || { echo "  Missing $tool. Install Foundry v1.5.0: foundryup -i 1.5.0"; exit 1; }
done
FORGE_VERSION=$(forge --version | head -1)
echo "  $FORGE_VERSION"
[[ "$FORGE_VERSION" == *"1.5.0"* ]] || echo "  Note: Forklab pins Foundry v1.5.0; Hashio rejects requests from newer versions."
if [[ ! -f "$FOUNDRY/lib/forge-std/src/Test.sol" ]]; then
  echo "  Fetching Solidity libraries (git submodules)"
  git -C "$ROOT" submodule update --init --recursive --quiet
fi

cd "$FOUNDRY"
bold "1/3  Offline emulator suite (no network)"
if OUT=$(forge test --offline 2>&1); then
  pass "$(grep -E '^Ran [0-9]+ test suites' <<< "$OUT" | tail -1)"
else
  echo "$OUT" | tail -20
  fail "offline suite"
fi

bold "2/3  Live-testnet failures, reproduced on mainnet block $(sed -n 's/.*"mainnet": *\([0-9]*\).*/\1/p' scripts-js/forkBlocks.json)"
echo "  The first run fetches fork state from Hashio and takes about 45 seconds; later runs are cached."
BLOCK=$(sed -n 's/.*"mainnet": *\([0-9]*\).*/\1/p' scripts-js/forkBlocks.json)
if OUT=$(forge test --fork-url "$MAINNET_RPC" --chain-id 295 --fork-block-number "$BLOCK" --ffi \
  --fork-retries 3 --fork-retry-backoff 1000 \
  --match-test 'test_testnetFailureGasLimitCannotFundRescheduleAndPurchase|test_outOfHbarRecordsPayerFailure' 2>&1); then
  pass "1.5M gas limit cannot fund the 1,409,649-gas re-schedule plus a SaucerSwap purchase"
  pass "an empty vault gets INSUFFICIENT_PAYER_BALANCE and is charged 1,735,120 tinybars"
else
  echo "$OUT" | tail -20
  fail "fork reproductions (check network access to $MAINNET_RPC)"
fi

bold "3/3  Live testnet record for vault $VAULT_ID"
URL="$MIRROR/transactions?account.id=$VAULT_ID&transactiontype=CONTRACTCALL&order=desc&limit=25"
if JSON=$(curl -fsS --max-time 20 "$URL"); then
  # Each scheduled run is a CONTRACTCALL transaction with "scheduled":true; count results without needing jq.
  RUNS=$(grep -o '"result":"[A-Z_]*","scheduled":true' <<< "$JSON" | cut -d'"' -f4 || true)
  SUCCESSES=$(grep -c '^SUCCESS$' <<< "$RUNS" || true)
  EMPTY=$(grep -c '^INSUFFICIENT_PAYER_BALANCE$' <<< "$RUNS" || true)
  if [[ "$SUCCESSES" -ge 6 && "$EMPTY" -ge 1 ]]; then
    pass "$SUCCESSES scheduled runs SUCCESS, then $EMPTY INSUFFICIENT_PAYER_BALANCE, as the emulator predicts"
  else
    fail "expected 6 scheduled SUCCESS runs and 1 INSUFFICIENT_PAYER_BALANCE, found $SUCCESSES and $EMPTY"
  fi
  echo "  $URL"
else
  fail "Mirror Node unreachable: $URL"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  printf '\033[1;32mAll Forklab checks passed.\033[0m Next: yarn install && yarn foundry:test:fork (full suite), yarn next:dev (UI).\n'
else
  printf '\033[1;31mSome checks failed; output is above.\033[0m\n'
  exit 1
fi
