#!/usr/bin/env bash
set -euo pipefail

# build-treasury-reward-withdrawal.sh - Build the ledger withdrawal transaction
# that moves funds from the treasury contract stake rewards into a treasury
# script UTxO.
#
# Usage:
#   NETWORK=mainnet PAYMENT_ADDRESS=addr... scripts/build-treasury-reward-withdrawal.sh
#
# Required:
#   PAYMENT_ADDRESS              fee/change address
#   CARDANO_NODE_SOCKET_PATH     node socket, unless already exported
#
# Optional:
#   WITHDRAW_AMOUNT              lovelace to withdraw; defaults to 6,900,000 ADA
#   FEE_TX_IN                    explicit fee input tx-in; otherwise selected from PAYMENT_ADDRESS
#   COLLATERAL_TX_IN             explicit collateral tx-in; otherwise first fee input
#   PAYMENT_SKEY                 signing key; if set, also writes tx.withdraw.signed
#   OUT_FILE                     tx body output path; default tx.withdraw.raw
#   SIGNED_OUT_FILE              signed tx output path; default tx.withdraw.signed
#   METADATA_JSON_FILE           optional metadata JSON file to attach

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "${REPO_ROOT}/config.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/config.env"
    set +a
fi

case "${NETWORK:-mainnet}" in
    mainnet) NETWORK_FLAG=(--mainnet) ;;
    preprod) NETWORK_FLAG=(--testnet-magic 1) ;;
    preview) NETWORK_FLAG=(--testnet-magic 2) ;;
    *) echo "Unsupported NETWORK=${NETWORK:-}. Use mainnet, preprod, or preview." >&2; exit 1 ;;
esac

require() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "Error: ${name} is required." >&2
        exit 1
    fi
}

require PAYMENT_ADDRESS
require CARDANO_NODE_SOCKET_PATH

command -v cardano-cli >/dev/null 2>&1 || {
    echo "Error: cardano-cli not found in PATH." >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || {
    echo "Error: jq not found in PATH." >&2
    exit 1
}

INSTANCE_ID="${INSTANCE_ID:-d161c89f1123fac8043df44aeec0ca36b2a76e84df47592fe92980ac}"
METADATA_FILE="${INSTANCE_METADATA_FILE:-${REPO_ROOT}/metadata/offchain-metadata.json}"

TREASURY_SCRIPT_REF="${TREASURY_SCRIPT_REF:-c133b8687c8550a8e7224421e45a7a67bc0941c85b8138f0f9e9498cce8fca08#0}"
REGISTRY_TX_IN="${REGISTRY_TX_IN:-576feff7b2f634ce2320be715f661a23944ed1157844121fbc5515c4feda155e#0}"
WITHDRAW_AMOUNT="${WITHDRAW_AMOUNT:-6900000000000}"

WORK_DIR="${WORK_DIR:-${REPO_ROOT}/tmp/treasury-withdrawal}"
mkdir -p "$WORK_DIR"

TREASURY_SCRIPT_FILE="${WORK_DIR}/treasury.plutus"

jq -r --arg instance "$INSTANCE_ID" '
  .[$instance].scripts.treasuryScript.script
  | {type:"PlutusScriptV3", description:"", cborHex:.}
' "$METADATA_FILE" > "$TREASURY_SCRIPT_FILE"

TREASURY_SCRIPT_ADDRESS="$(
    cardano-cli address build \
        --payment-script-file "$TREASURY_SCRIPT_FILE" \
        --stake-script-file "$TREASURY_SCRIPT_FILE" \
        "${NETWORK_FLAG[@]}"
)"

TREASURY_STAKE_ADDRESS="$(
    cardano-cli conway stake-address build \
        --stake-script-file "$TREASURY_SCRIPT_FILE" \
        "${NETWORK_FLAG[@]}"
)"

TX_INS=()
SELECTED_UTXOS=()
if [[ -n "${FEE_TX_IN:-}" ]]; then
    TX_INS+=("$FEE_TX_IN")
else
    UTXO_JSON="$(cardano-cli conway query utxo "${NETWORK_FLAG[@]}" --address "$PAYMENT_ADDRESS" --output-json)"
    mapfile -t SELECTED_UTXOS < <(
        jq -r '
          [to_entries[] | select(.value.value.lovelace > 5000000) | {txin:.key, lovelace:.value.value.lovelace}]
          | sort_by(-.lovelace)
          | .[:2][]
          | .txin
        ' <<<"$UTXO_JSON"
    )
    if [[ -n "${SELECTED_UTXOS[0]:-}" ]]; then
        TX_INS+=("${SELECTED_UTXOS[0]}")
    fi
fi

if [[ ${#TX_INS[@]} -eq 0 ]]; then
    echo "Error: no usable fee UTxO found for ${PAYMENT_ADDRESS}." >&2
    echo "Set FEE_TX_IN=<txid#index> to choose one explicitly." >&2
    exit 1
fi

if [[ -z "${COLLATERAL_TX_IN:-}" ]]; then
    COLLATERAL_TX_IN="${SELECTED_UTXOS[1]:-${TX_INS[0]}}"
fi
OUT_FILE="${OUT_FILE:-${REPO_ROOT}/tx.withdraw.raw}"
SIGNED_OUT_FILE="${SIGNED_OUT_FILE:-${REPO_ROOT}/tx.withdraw.signed}"

TX_IN_FLAGS=()
for txin in "${TX_INS[@]}"; do
    TX_IN_FLAGS+=(--tx-in "$txin")
done

METADATA_FLAGS=()
if [[ -n "${METADATA_JSON_FILE:-}" ]]; then
    METADATA_FLAGS=(--metadata-json-file "$METADATA_JSON_FILE")
fi

echo "Network:              ${NETWORK_FLAG[*]}"
echo "Fee/change address:   ${PAYMENT_ADDRESS}"
echo "Fee input:            ${TX_INS[*]}"
echo "Collateral input:     ${COLLATERAL_TX_IN}"
echo "Treasury stake addr:  ${TREASURY_STAKE_ADDRESS}"
echo "Treasury script addr: ${TREASURY_SCRIPT_ADDRESS}"
echo "Treasury ref script:  ${TREASURY_SCRIPT_REF}"
echo "Registry reference:   ${REGISTRY_TX_IN}"
echo "Withdraw amount:      ${WITHDRAW_AMOUNT}"
echo

cardano-cli conway transaction build \
    "${NETWORK_FLAG[@]}" \
    "${TX_IN_FLAGS[@]}" \
    --tx-in-collateral "$COLLATERAL_TX_IN" \
    --read-only-tx-in-reference "$REGISTRY_TX_IN" \
    --withdrawal "${TREASURY_STAKE_ADDRESS}+${WITHDRAW_AMOUNT}" \
    --withdrawal-tx-in-reference "$TREASURY_SCRIPT_REF" \
    --withdrawal-plutus-script-v3 \
    --withdrawal-reference-tx-in-redeemer-value '{}' \
    --tx-out "${TREASURY_SCRIPT_ADDRESS}+${WITHDRAW_AMOUNT}" \
    --tx-out-inline-datum-value '{}' \
    --change-address "$PAYMENT_ADDRESS" \
    "${METADATA_FLAGS[@]}" \
    --out-file "$OUT_FILE"

echo "Built transaction body: ${OUT_FILE}"

if [[ -n "${PAYMENT_SKEY:-}" ]]; then
    cardano-cli conway transaction sign \
        "${NETWORK_FLAG[@]}" \
        --tx-body-file "$OUT_FILE" \
        --signing-key-file "$PAYMENT_SKEY" \
        --out-file "$SIGNED_OUT_FILE"
    echo "Signed transaction: ${SIGNED_OUT_FILE}"
fi
