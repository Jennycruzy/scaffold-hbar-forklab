#!/usr/bin/env bash
# Checks three schedule-service and token edge cases on Hedera testnet, so the emulator's
# answers can be compared with the network's.
#
#   KEYSTORE_NAME=<foundry keystore> yarn foundry:testnet:probe
#
# 1. Unauthorized delete: probe B deletes a schedule created by probe A.
# 2. Unsigned payer: probe A schedules a call whose payer (the owner) never signs; it reaches expiry.
# 3. Unassociated approve: probe A, which is not associated with TOKEN, calls TOKEN.approve.
#
# Cost: two small deployments, 2 HBAR funding probe A (left in the contract), and gas.
set -euo pipefail

RPC="${HEDERA_TESTNET_RPC_URL:-https://testnet.hashio.io/api}"
MIRROR="${HEDERA_MIRROR_TESTNET_URL:-https://testnet.mirrornode.hedera.com}/api/v1"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN="${PROBE_TOKEN:-0x000000000000000000000000000000000042E926}"
FUND_WEIBARS="${PROBE_FUND_WEIBARS:-2000000000000000000}"
SCHEDULED_GAS=100000
DELAY_SECONDS=90
: "${KEYSTORE_NAME:?set KEYSTORE_NAME to a Foundry keystore (yarn foundry:account:import creates one)}"

read -rsp "Keystore password for $KEYSTORE_NAME: " KEYSTORE_PASSWORD
echo
PASSWORD_DIR=$(mktemp -d)
trap 'rm -rf "$PASSWORD_DIR"' EXIT
chmod 700 "$PASSWORD_DIR"
printf '%s' "$KEYSTORE_PASSWORD" > "$PASSWORD_DIR/pw"
unset KEYSTORE_PASSWORD
SIGN=(--account "$KEYSTORE_NAME" --password-file "$PASSWORD_DIR/pw")
OWNER=$(cast wallet address "${SIGN[@]}") || { echo "Wrong keystore password for $KEYSTORE_NAME"; exit 1; }
echo "Owner: $OWNER ($(cast balance --rpc-url "$RPC" "$OWNER" --ether) HBAR)"

# Hashio can report a stale nonce straight after a transaction, so wait for it to move.
# next_nonce runs inside command substitutions, so the last nonce lives in a file, not a variable.
echo -1 > "$PASSWORD_DIR/nonce"
next_nonce() {
  local nonce last
  last=$(cat "$PASSWORD_DIR/nonce")
  for _ in $(seq 1 30); do
    nonce=$(cast nonce --rpc-url "$RPC" "$OWNER")
    [[ "$nonce" -gt "$last" ]] && break
    sleep 2
  done
  [[ "$nonce" -gt "$last" ]] || { echo "Nonce stuck at $nonce" >&2; return 1; }
  echo "$nonce" > "$PASSWORD_DIR/nonce"
  echo "$nonce"
}
send() { cast send --rpc-url "$RPC" "${SIGN[@]}" --legacy --nonce "$(next_nonce)" "$@" --json | jq -r .transactionHash; }
deploy() {
  (cd "$HERE" && forge create contracts/probes/HssProbe.sol:HssProbe --broadcast --rpc-url "$RPC" "${SIGN[@]}" \
    --legacy --nonce "$(next_nonce)" --json) | jq -r .deployedTo
}
call() { cast call --rpc-url "$RPC" "$@" | cut -d' ' -f1; }
entity_id() { echo "0.0.$((16#${1:2}))"; }
now() { cast block --rpc-url "$RPC" latest --field timestamp; }

echo "Deploying probes"
A=$(deploy)
B=$(deploy)
echo "Probe A: $A ($(entity_id "$A"))"
echo "Probe B: $B ($(entity_id "$B"))"
send "$A" --value "$FUND_WEIBARS" > /dev/null

echo
echo "1. Unauthorized delete"
tx=$(send "$A" 'scheduleSelf(uint256,uint256)' $(( $(now) + DELAY_SECONDS )) "$SCHEDULED_GAS" --gas-limit 2000000)
S1=$(call "$A" 'lastSchedule()(address)')
echo "   A.scheduleSelf: code $(call "$A" 'lastCreateCode()(int64)'), schedule $S1 ($(entity_id "$S1")), tx $tx"
tx=$(send "$B" 'deleteOther(address)' "$S1" --gas-limit 1000000)
echo "   B.deleteOther:  code $(call "$B" 'lastDeleteCode()(int64)') (emulator: 157 UNAUTHORIZED), tx $tx"

echo
echo "2. Unsigned payer schedule"
tx=$(send "$A" 'scheduleWithPayer(address,uint256,uint256)' "$OWNER" $(( $(now) + DELAY_SECONDS )) "$SCHEDULED_GAS" \
  --gas-limit 2000000)
S2=$(call "$A" 'lastSchedule()(address)')
echo "   A.scheduleWithPayer: code $(call "$A" 'lastCreateCode()(int64)'), schedule $S2 ($(entity_id "$S2")), tx $tx"

echo
echo "3. Approve from an unassociated contract"
echo "   A associated with token: $(call --from "$A" "$TOKEN" 'isAssociated()(bool)')"
tx=$(send "$A" 'approveToken(address,address,uint256)' "$TOKEN" "$OWNER" 1 --gas-limit 1000000) || tx="reverted"
echo "   A.approveToken: success $(call "$A" 'lastApproveSuccess()(bool)'), return $(call "$A" 'lastApproveReturn()(bytes)'), tx $tx"
echo "   allowance(A, owner) afterwards: $(call "$TOKEN" 'allowance(address,address)(uint256)' "$A" "$OWNER")"

echo
echo "Waiting $((DELAY_SECONDS + 30)) s for both schedules to reach expiry"
sleep $((DELAY_SECONDS + 30))
echo "   pings on A: $(call "$A" 'pings()(uint256)') (1 means the undeleted self-schedule ran and the unsigned one did not)"
for s in "$S1" "$S2"; do
  id=$(entity_id "$s")
  echo "   $id: $(curl -fsS "$MIRROR/schedules/$id" | jq -c '{deleted, executed_timestamp, expiration_time, signatures: (.signatures | length)}')"
done
echo
echo "Mirror Node: $MIRROR/contracts/$A/results?order=desc and $MIRROR/contracts/$B/results?order=desc"
