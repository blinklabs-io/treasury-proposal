#!/usr/bin/env bash
set -euo pipefail

# delegate-always-abstain.sh - Delegate treasury contract stake credential to always_abstain DRep.
# Required by Cardano Constitution Article IV, Section 5.
# Usage: NETWORK=mainnet scripts/delegate-always-abstain.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Source configuration ─────────────────────────────────────────────────────

if [[ -f "${REPO_ROOT}/config.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/config.env"
    set +a
fi

# ── Network flag ─────────────────────────────────────────────────────────────

case "${NETWORK:-preview}" in
    mainnet) NETWORK_FLAG=(--mainnet) ;;
    preprod) NETWORK_FLAG=(--testnet-magic 1) ;;
    *)       NETWORK_FLAG=(--testnet-magic 2) ;;
esac

# ── Validate prerequisites ──────────────────────────────────────────────────

TREASURY_SCRIPT="${RECEIVING_STAKE_SCRIPT_FILE:-}"
if [[ -z "$TREASURY_SCRIPT" ]]; then
    echo "Error: RECEIVING_STAKE_SCRIPT_FILE is not set in config.env." >&2
    exit 1
fi
if [[ "$TREASURY_SCRIPT" != /* ]]; then
    TREASURY_SCRIPT="${REPO_ROOT}/${TREASURY_SCRIPT}"
fi
if [[ ! -f "$TREASURY_SCRIPT" ]]; then
    echo "Error: Treasury script file not found: ${TREASURY_SCRIPT}" >&2
    exit 1
fi

if [[ -z "${PAYMENT_SKEY:-}" ]]; then
    echo "Error: PAYMENT_SKEY is not set." >&2
    exit 1
fi
PAY_SKEY="${PAYMENT_SKEY}"
if [[ "$PAY_SKEY" != /* ]]; then
    PAY_SKEY="${REPO_ROOT}/${PAY_SKEY}"
fi

if [[ -z "${PAYMENT_ADDRESS:-}" ]]; then
    echo "Error: PAYMENT_ADDRESS is not set." >&2
    exit 1
fi

echo "=== Delegate Treasury to Always Abstain ==="
echo ""
echo "Network: ${NETWORK_FLAG[*]}"
echo "Script:  ${TREASURY_SCRIPT}"
echo ""

# ── Create vote delegation certificate ──────────────────────────────────────

CERT_FILE="${REPO_ROOT}/keys/treasury-vote-deleg.cert"

cardano-cli conway stake-address vote-delegation-certificate \
    --stake-script-file "$TREASURY_SCRIPT" \
    --always-abstain \
    --out-file "$CERT_FILE"

echo "Vote delegation certificate created: ${CERT_FILE}"

# ── Query UTxOs ──────────────────────────────────────────────────────────────

echo "Querying UTxOs..."

UTXO_OUTPUT=$(cardano-cli conway query utxo \
    "${NETWORK_FLAG[@]}" \
    --address "$PAYMENT_ADDRESS" \
    --out-file /dev/stdout)

# Need enough for fees + collateral; 10 ADA is generous
REQUIRED_LOVELACE=10000000

readarray -t UTXO_ENTRIES < <(echo "$UTXO_OUTPUT" | jq -r '
    [to_entries[] | {key: .key, lovelace: .value.value.lovelace}]
    | sort_by(-.lovelace)
    | .[]
    | "\(.key) \(.lovelace)"
')

if [[ ${#UTXO_ENTRIES[@]} -eq 0 ]]; then
    echo "Error: No UTxOs found at ${PAYMENT_ADDRESS}" >&2
    exit 1
fi

TX_INS=()
TOTAL_LOVELACE=0

for entry in "${UTXO_ENTRIES[@]}"; do
    utxo=$(echo "$entry" | awk '{print $1}')
    lovelace=$(echo "$entry" | awk '{print $2}')
    TX_INS+=("$utxo")
    TOTAL_LOVELACE=$((TOTAL_LOVELACE + lovelace))
    if [[ "$TOTAL_LOVELACE" -ge "$REQUIRED_LOVELACE" ]]; then
        break
    fi
done

TOTAL_ADA=$(echo "scale=6; $TOTAL_LOVELACE / 1000000" | bc)
REQUIRED_ADA=$(echo "scale=6; $REQUIRED_LOVELACE / 1000000" | bc)

if [[ "$TOTAL_LOVELACE" -lt "$REQUIRED_LOVELACE" ]]; then
    echo "Error: Insufficient funds." >&2
    echo "  Available: ${TOTAL_ADA} ADA (${#UTXO_ENTRIES[@]} UTxOs)" >&2
    echo "  Required:  ${REQUIRED_ADA} ADA (fees + collateral)" >&2
    exit 1
fi

echo "Selected ${#TX_INS[@]} UTxO(s) totaling ${TOTAL_ADA} ADA:"
for utxo in "${TX_INS[@]}"; do
    echo "  ${utxo}"
done
echo ""

# ── Build transaction ────────────────────────────────────────────────────────

TX_IN_FLAGS=()
for utxo in "${TX_INS[@]}"; do
    TX_IN_FLAGS+=(--tx-in "$utxo")
done

TX_RAW="${REPO_ROOT}/vote-deleg.raw"

cardano-cli conway transaction build \
    "${NETWORK_FLAG[@]}" \
    "${TX_IN_FLAGS[@]}" \
    --tx-in-collateral "${TX_INS[0]}" \
    --change-address "$PAYMENT_ADDRESS" \
    --certificate-file "$CERT_FILE" \
    --certificate-script-file "$TREASURY_SCRIPT" \
    --certificate-redeemer-value '{}' \
    --out-file "$TX_RAW"

echo "Transaction built: ${TX_RAW}"

# ── Sign transaction ─────────────────────────────────────────────────────────

TX_SIGNED="${REPO_ROOT}/vote-deleg.signed"

cardano-cli conway transaction sign \
    "${NETWORK_FLAG[@]}" \
    --tx-body-file "$TX_RAW" \
    --signing-key-file "$PAY_SKEY" \
    --out-file "$TX_SIGNED"

echo "Transaction signed: ${TX_SIGNED}"

# ── Submit ───────────────────────────────────────────────────────────────────

cardano-cli conway transaction submit \
    "${NETWORK_FLAG[@]}" \
    --tx-file "$TX_SIGNED"

TX_HASH=$(cardano-cli conway transaction txid --tx-file "$TX_SIGNED")

echo ""
echo "Treasury stake credential delegated to always_abstain."
echo "Transaction hash: ${TX_HASH}"
echo ""
echo "Clean up: rm -f vote-deleg.raw vote-deleg.signed keys/treasury-vote-deleg.cert"
