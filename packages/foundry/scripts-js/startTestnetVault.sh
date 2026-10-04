#!/usr/bin/env bash
# Starts a RecurringBuy vault on Hedera testnet and watches its first scheduled runs.
#
#   KEYSTORE_NAME=<foundry keystore> VAULT=0x... yarn foundry:testnet:start
#
# VAULT defaults to the RecurringBuy address from the last `yarn foundry:deploy` broadcast.
# Steps already done (association, approval, configuration, funding, start) are skipped,
# so a re-run continues where an earlier run stopped.
#
# Everything is sent with `cast send`, not `forge script`: Forge simulates a script locally
# before broadcasting, and that simulation has no Hedera system contracts, so `start()`
# (HTS association plus an HSS `scheduleCall`) reverts there even though it succeeds on
# the network.
set -euo pipefail

RPC="${HEDERA_TESTNET_RPC_URL:-https://testnet.hashio.io/api}"
MIRROR="${HEDERA_MIRROR_TESTNET_URL:-https://testnet.mirrornode.hedera.com}/api/v1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN_OUT="${RECURRING_BUY_TOKEN_OUT:-0x000000000000000000000000000000000042E926}"
AMOUNT_TINYBARS="${RECURRING_BUY_AMOUNT_TINYBARS:-100000000}"
INTERVAL_SECONDS="${RECURRING_BUY_INTERVAL_SECONDS:-60}"
DEVIATION_BPS="${RECURRING_BUY_DEVIATION_BPS:-10000}"
MAX_PRICE_AGE="${RECURRING_BUY_MAX_PRICE_AGE:-7200}"
EXECUTION_GAS="${RECURRING_BUY_EXECUTION_GAS:-2500000}"
FUND_WEIBARS="${RECURRING_BUY_FUND_WEIBARS:-15000000000000000000}"
WATCH_RUNS="${WATCH_RUNS:-2}"
: "${KEYSTORE_NAME:?set KEYSTORE_NAME to a Foundry keystore (yarn foundry:account:import creates one)}"

if [[ -z "${VAULT:-}" ]]; then
  BROADCAST="$HERE/broadcast/Deploy.s.sol/296/run-latest.json"
  [[ -f "$BROADCAST" ]] || { echo "Set VAULT, or deploy first with: yarn foundry:deploy --network hedera_testnet"; exit 1; }
  VAULT=$(node -e '
    const r = require(process.argv[1]);
    const t = r.transactions.find(t => t.contractName === "RecurringBuy" && t.transactionType === "CREATE");
    if (!t) process.exit(1);
    console.log(t.contractAddress);
  ' "$BROADCAST")
fi

# Ask for the keystore password once. Foundry reads it from a file (`--password-file`);
# exporting ETH_PASSWORD globally would also break read-only `cast call`.
read -rsp "Keystore password for $KEYSTORE_NAME: " KEYSTORE_PASSWORD
echo
PASSWORD_DIR=$(mktemp -d)
trap 'rm -rf "$PASSWORD_DIR"' EXIT
chmod 700 "$PASSWORD_DIR"
printf '%s' "$KEYSTORE_PASSWORD" > "$PASSWORD_DIR/pw"
unset KEYSTORE_PASSWORD
SIGN=(--account "$KEYSTORE_NAME" --password-file "$PASSWORD_DIR/pw")
OWNER=$(cast wallet address "${SIGN[@]}") || { echo "Wrong keystore password for $KEYSTORE_NAME"; exit 1; }

read_vault() { cast call --rpc-url "$RPC" "$VAULT" "$@" | cut -d' ' -f1; }
lower() { tr 'A-F' 'a-f' <<< "$1"; }

[[ "$(lower "$(read_vault 'owner()(address)')")" == "$(lower "$OWNER")" ]] \
  || { echo "$OWNER does not own vault $VAULT"; exit 1; }
echo "Owner: $OWNER ($(cast balance --rpc-url "$RPC" "$OWNER" --ether) HBAR)"
echo "Vault: $VAULT"

# Hashio can report a stale nonce straight after a transaction ("Nonce too low"), so each
# send waits until the account nonce has moved past the previous one and passes it explicitly.
LAST_NONCE=-1
send() {
  local nonce
  for _ in $(seq 1 30); do
    nonce=$(cast nonce --rpc-url "$RPC" "$OWNER")
    [[ "$nonce" -gt "$LAST_NONCE" ]] && break
    sleep 2
  done
  cast send --rpc-url "$RPC" "${SIGN[@]}" --legacy --nonce "$nonce" "$@" > /dev/null
  LAST_NONCE=$nonce
}

# 1. The owner associates with tokenOut and approves the vault for one base unit. Both must
#    come from the owner account: HRC-719 `isAssociated()` checks msg.sender.
if [[ "$(cast call --rpc-url "$RPC" --from "$OWNER" "$TOKEN_OUT" 'isAssociated()(bool)')" != "true" ]]; then
  echo "Associating the owner with $TOKEN_OUT"
  send "$TOKEN_OUT" 'associate()'
fi
if [[ "$(cast call --rpc-url "$RPC" "$TOKEN_OUT" 'allowance(address,address)(uint256)' "$OWNER" "$VAULT" | cut -d' ' -f1)" == "0" ]]; then
  echo "Approving the vault for one base unit"
  send "$TOKEN_OUT" 'approve(address,uint256)' "$VAULT" 1
fi

# 2. Configure, set the gas limit, fund, and start.
if [[ "$(lower "$(read_vault 'tokenOut()(address)')")" != "$(lower "$TOKEN_OUT")" ]]; then
  echo "Configuring: $AMOUNT_TINYBARS tinybars every $INTERVAL_SECONDS s"
  send "$VAULT" 'configure(address,uint256,uint256,uint256,uint256)' \
    "$TOKEN_OUT" "$AMOUNT_TINYBARS" "$INTERVAL_SECONDS" "$DEVIATION_BPS" "$MAX_PRICE_AGE"
fi
if [[ "$(read_vault 'executionGas()(uint256)')" != "$EXECUTION_GAS" ]]; then
  echo "Setting execution gas to $EXECUTION_GAS"
  send "$VAULT" 'setExecutionGas(uint256)' "$EXECUTION_GAS"
fi
if node -e 'process.exit(BigInt(process.argv[1]) < BigInt(process.argv[2]) ? 0 : 1)' \
  "$(cast balance --rpc-url "$RPC" "$VAULT")" "$FUND_WEIBARS"; then
  echo "Funding the vault with $(cast from-wei "$FUND_WEIBARS") HBAR"
  send "$VAULT" 'deposit()' --value "$FUND_WEIBARS"
fi
if [[ "$(read_vault 'running()(bool)')" != "true" ]]; then
  # start() associates the vault (~705k gas) and creates the first HSS schedule (~1.41M gas).
  echo "Starting"
  send "$VAULT" 'start()' --gas-limit 4000000
fi
[[ "$(read_vault 'running()(bool)')" == "true" ]] || { echo "start() did not leave the vault running"; exit 1; }

# 3. Watch for scheduled runs.
echo "Running. Next run at $(read_vault 'nextRunAt()(uint256)'); watching for $WATCH_RUNS runs..."
last=$(read_vault 'lastRunAt()(uint256)')
runs=0
deadline=$(( $(date +%s) + (INTERVAL_SECONDS + 60) * WATCH_RUNS + 60 ))
while [[ $runs -lt $WATCH_RUNS && $(date +%s) -lt $deadline ]]; do
  sleep 10
  now=$(read_vault 'lastRunAt()(uint256)')
  if [[ "$now" != "$last" ]]; then
    runs=$((runs + 1))
    last=$now
    echo "Run $runs at $now; vault balance $(cast balance --rpc-url "$RPC" "$VAULT" --ether) HBAR"
  fi
done

echo
echo "Scheduled runs seen: $runs"
echo "Contract results: $MIRROR/contracts/$VAULT/results?order=desc"
echo "Event logs:       $MIRROR/contracts/$VAULT/results/logs?order=desc"
echo "The vault keeps running until it is stopped or out of HBAR. To stop and recover the balance:"
echo "  cast send --rpc-url $RPC --account $KEYSTORE_NAME --legacy $VAULT 'stop()'"
echo "  cast send --rpc-url $RPC --account $KEYSTORE_NAME --legacy $VAULT 'withdraw(uint256)' <tinybars>"
