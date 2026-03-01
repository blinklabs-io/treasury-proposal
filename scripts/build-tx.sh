#!/usr/bin/env bash
set -euo pipefail

# build-tx.sh - Build a transaction to submit the treasury withdrawal governance action.
# Usage: NETWORK=preview scripts/build-tx.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Source configuration ─────────────────────────────────────────────────────

if [[ -f "${REPO_ROOT}/config.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/config.env"
    set +a
fi

# ── Network flag (query/tx commands use --testnet-magic N) ───────────────────

case "${NETWORK:-preview}" in
    mainnet) NETWORK_FLAG=(--mainnet) ;;
    preprod) NETWORK_FLAG=(--testnet-magic 1) ;;
    *)       NETWORK_FLAG=(--testnet-magic 2) ;;
esac

# ── Validate prerequisites ──────────────────────────────────────────────────

ACTION_FILE="${REPO_ROOT}/treasury-withdrawal.action"
if [[ ! -f "$ACTION_FILE" ]]; then
    echo "Error: Governance action file not found: ${ACTION_FILE}" >&2
    echo "Run 'make governance-action' first." >&2
    exit 1
fi

if [[ -z "${PAYMENT_ADDRESS:-}" ]]; then
    echo "Error: PAYMENT_ADDRESS is not set." >&2
    echo "Set it in config.env or export it." >&2
    exit 1
fi

# ── Query UTxOs ──────────────────────────────────────────────────────────────

echo "=== Build Transaction ==="
echo ""
echo "Network:  ${NETWORK_FLAG[*]}"
echo "Address:  ${PAYMENT_ADDRESS}"
echo ""
echo "Querying UTxOs..."

UTXO_OUTPUT=$(cardano-cli conway query utxo \
    "${NETWORK_FLAG[@]}" \
    --address "$PAYMENT_ADDRESS" \
    --out-file /dev/stdout)

# Parse the first UTxO with sufficient funds
TX_IN=$(echo "$UTXO_OUTPUT" | jq -r 'to_entries | .[0].key // empty')

if [[ -z "$TX_IN" ]]; then
    echo "Error: No UTxOs found at ${PAYMENT_ADDRESS}" >&2
    echo "Fund this address before building the transaction." >&2
    exit 1
fi

echo "Using UTxO: ${TX_IN}"
echo ""

# ── Check for guardrails script ──────────────────────────────────────────────

GUARDRAILS_SCRIPT="${GUARDRAILS_SCRIPT:-${REPO_ROOT}/scripts/guardrails.plutus}"
PROPOSAL_SCRIPT_FLAGS=()

if [[ -f "$GUARDRAILS_SCRIPT" ]]; then
    echo "Guardrails script: ${GUARDRAILS_SCRIPT}"
    PROPOSAL_SCRIPT_FLAGS=(
        --proposal-script-file "$GUARDRAILS_SCRIPT"
        --proposal-redeemer-value '{}'
        --tx-in-collateral "$TX_IN"
    )
else
    echo "No guardrails script found (skipping script witness)"
fi

echo ""

# ── Build transaction ────────────────────────────────────────────────────────

TX_RAW="${REPO_ROOT}/tx.raw"

cardano-cli conway transaction build \
    "${NETWORK_FLAG[@]}" \
    --tx-in "$TX_IN" \
    --change-address "$PAYMENT_ADDRESS" \
    --proposal-file "$ACTION_FILE" \
    "${PROPOSAL_SCRIPT_FLAGS[@]}" \
    --out-file "$TX_RAW"

echo "Transaction built: ${TX_RAW}"
