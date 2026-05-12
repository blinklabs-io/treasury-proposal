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
#   TX_AUTHOR_HASH               author key hash; defaults from metadata/offchain-metadata.json
#   OUTPUT_IDENTIFIER            TOM metadata identifier for output 0
#   OUTPUT_LABEL                 TOM metadata label for output 0
#   WITHDRAW_REASON              TOM metadata reason / journal justification
#   TX_COMMENT                   TOM metadata top-level comment
#   FEE_TX_IN                    explicit fee input tx-in; otherwise selected from PAYMENT_ADDRESS
#   COLLATERAL_TX_IN             explicit collateral tx-in; otherwise first fee input
#   PAYMENT_SKEY                 signing key; if set, also writes tx.withdraw.signed
#   EXTRA_SIGNING_KEYS           optional comma/space-separated additional skeys
#   REQUIRED_SIGNER_HASHES       optional comma/space-separated required key hashes
#   REQUIRED_SIGNER_KEYS         optional comma/space-separated skeys to require
#   OUT_FILE                     tx body output path; default tx.withdraw.raw
#   SIGNED_OUT_FILE              signed tx output path; default tx.withdraw.signed
#   METADATA_JSON_FILE           existing metadata JSON file to attach
#   METADATA_OUT_FILE            generated metadata path; ignored if METADATA_JSON_FILE is set
#   JOURNAL_DRAFT_FILE           generated journal draft path

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
TX_AUTHOR_HASH="${TX_AUTHOR_HASH:-$(jq -r --arg instance "$INSTANCE_ID" '.[$instance].metadata.txAuthor // empty' "$METADATA_FILE")}"
OUTPUT_IDENTIFIER="${OUTPUT_IDENTIFIER:-Dingo}"
OUTPUT_LABEL="${OUTPUT_LABEL:-Blink Labs Dingo Treasury 2026}"
WITHDRAW_REASON="${WITHDRAW_REASON:-Move enacted treasury withdrawal funds from the treasury contract reward account into the treasury script UTxO before disbursement.}"
TX_COMMENT="${TX_COMMENT:-Prepare treasury reward withdrawal for Blink Labs Dingo 2026 development.}"
JOURNAL_DATE="${JOURNAL_DATE:-$(date +%Y-%m-%d)}"

WORK_DIR="${WORK_DIR:-${REPO_ROOT}/tmp/treasury-withdrawal}"
mkdir -p "$WORK_DIR"

TREASURY_SCRIPT_FILE="${WORK_DIR}/treasury.plutus"
METADATA_OUT_FILE="${METADATA_OUT_FILE:-${REPO_ROOT}/metadata/transactions/${JOURNAL_DATE}-treasury-reward-withdrawal.json}"
mkdir -p "$(dirname "$METADATA_OUT_FILE")"

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
if [[ -z "${METADATA_JSON_FILE:-}" ]]; then
    if [[ -z "$TX_AUTHOR_HASH" ]]; then
        echo "Error: TX_AUTHOR_HASH is required when generating metadata." >&2
        exit 1
    fi
    jq -n \
        --arg context "https://raw.githubusercontent.com/SundaeSwap-finance/treasury-contracts/refs/heads/main/offchain/src/metadata/context.jsonld" \
        --arg instance "$INSTANCE_ID" \
        --arg txAuthor "$TX_AUTHOR_HASH" \
        --arg reason "$WITHDRAW_REASON" \
        --arg outputIdentifier "$OUTPUT_IDENTIFIER" \
        --arg outputLabel "$OUTPUT_LABEL" \
        --arg comment "$TX_COMMENT" '
        def chunk_string:
          if length <= 64 then .
          else [range(0; length; 64) as $i | .[$i:$i + 64]]
          end;
        def chunk_long_strings:
          if type == "string" then chunk_string
          elif type == "array" then map(chunk_long_strings)
          elif type == "object" then with_entries(.value |= chunk_long_strings)
          else .
          end;
        {
          "1694": {
            "@context": $context,
            hashAlgorithm: "blake2b-256",
            txAuthor: $txAuthor,
            instance: $instance,
            body: {
              event: "initialize",
              reason: $reason,
              outputs: {
                "0": ({
                  identifier: $outputIdentifier
                } + (if $outputLabel == "" then {} else {label: $outputLabel} end))
              }
            },
            comment: $comment
          }
        } | chunk_long_strings
    ' > "$METADATA_OUT_FILE"
    METADATA_JSON_FILE="$METADATA_OUT_FILE"
else
    if [[ -z "${TX_AUTHOR_HASH:-}" && -f "$METADATA_JSON_FILE" ]]; then
        TX_AUTHOR_HASH="$(
            jq -r '.txAuthor // .["1694"].txAuthor // empty' "$METADATA_JSON_FILE"
        )"
    fi
fi
METADATA_FLAGS=(--json-metadata-no-schema --metadata-json-file "$METADATA_JSON_FILE")

split_words() {
    local value="$1"
    tr ',[:space:]' '\n' <<<"$value" | sed '/^$/d'
}

SIGNING_KEY_FLAGS=()
SIGNING_KEY_LABELS=()
add_signing_key() {
    local key="$1"
    SIGNING_KEY_FLAGS+=(--signing-key-file "$key")
    SIGNING_KEY_LABELS+=("$key")
}

REQUIRED_SIGNER_FLAGS=()
REQUIRED_SIGNER_LABELS=()
add_required_signer_hash() {
    local hash="$1"
    REQUIRED_SIGNER_FLAGS+=(--required-signer-hash "$hash")
    REQUIRED_SIGNER_LABELS+=("$hash")
}
add_required_signer_key() {
    local key="$1"
    REQUIRED_SIGNER_FLAGS+=(--required-signer "$key")
    REQUIRED_SIGNER_LABELS+=("$key")
    add_signing_key "$key"
}

if [[ -n "${TX_AUTHOR_HASH:-}" ]]; then
    add_required_signer_hash "$TX_AUTHOR_HASH"
fi

if [[ -n "${REQUIRED_SIGNER_HASHES:-}" ]]; then
    while IFS= read -r signer_hash; do
        add_required_signer_hash "$signer_hash"
    done < <(split_words "$REQUIRED_SIGNER_HASHES")
fi

if [[ -n "${REQUIRED_SIGNER_KEYS:-}" ]]; then
    while IFS= read -r signer_key; do
        add_required_signer_key "$signer_key"
    done < <(split_words "$REQUIRED_SIGNER_KEYS")
fi

if [[ -n "${PAYMENT_SKEY:-}" ]]; then
    add_signing_key "$PAYMENT_SKEY"
fi
if [[ -n "${EXTRA_SIGNING_KEYS:-}" ]]; then
    while IFS= read -r signing_key; do
        add_signing_key "$signing_key"
    done < <(split_words "$EXTRA_SIGNING_KEYS")
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
echo "Metadata file:        ${METADATA_JSON_FILE}"
if [[ -n "${TX_AUTHOR_HASH:-}" ]]; then
    echo "Tx author hash:       ${TX_AUTHOR_HASH}"
fi
if [[ ${#REQUIRED_SIGNER_LABELS[@]} -gt 0 ]]; then
    echo "Required signers:     ${REQUIRED_SIGNER_LABELS[*]}"
fi
if [[ ${#SIGNING_KEY_LABELS[@]} -gt 0 ]]; then
    echo "Signing keys:         ${SIGNING_KEY_LABELS[*]}"
fi
echo

cardano-cli conway transaction build \
    "${NETWORK_FLAG[@]}" \
    "${TX_IN_FLAGS[@]}" \
    "${REQUIRED_SIGNER_FLAGS[@]}" \
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
TX_ID="$(cardano-cli conway transaction txid --tx-body-file "$OUT_FILE" --output-text)"
echo "Transaction id: ${TX_ID}"

if [[ ${#SIGNING_KEY_FLAGS[@]} -gt 0 ]]; then
    cardano-cli conway transaction sign \
        "${NETWORK_FLAG[@]}" \
        --tx-body-file "$OUT_FILE" \
        "${SIGNING_KEY_FLAGS[@]}" \
        --out-file "$SIGNED_OUT_FILE"
    echo "Signed transaction: ${SIGNED_OUT_FILE}"
fi

if command -v b2sum >/dev/null 2>&1; then
    METADATA_HASH="$(b2sum -l 256 "$METADATA_JSON_FILE" | awk '{print $1}')"
else
    METADATA_HASH="N/A"
fi

AMOUNT_ADA="$(awk "BEGIN { printf \"%.6f\", ${WITHDRAW_AMOUNT} / 1000000 }")"
JOURNAL_DRAFT_FILE="${JOURNAL_DRAFT_FILE:-${REPO_ROOT}/journal/${JOURNAL_DATE}-treasury-reward-withdrawal.md}"
mkdir -p "$(dirname "$JOURNAL_DRAFT_FILE")"

cat > "$JOURNAL_DRAFT_FILE" <<EOF
# Journal Entry: treasury-reward-withdrawal

| Field | Value |
|-------|-------|
| **Date** | ${JOURNAL_DATE} |
| **Transaction Hash** | \`${TX_ID}\` |
| **Action** | treasury-reward-withdrawal |
| **Amount (ADA)** | ${AMOUNT_ADA} |
| **Signers** | tx author ${TX_AUTHOR_HASH:-N/A}; fee payer ${PAYMENT_ADDRESS} |
| **Justification** | ${WITHDRAW_REASON} |
| **Metadata Hash** | \`${METADATA_HASH}\` |

## Notes

- Moves \`${WITHDRAW_AMOUNT}\` lovelace from treasury reward account \`${TREASURY_STAKE_ADDRESS}\` into treasury script address \`${TREASURY_SCRIPT_ADDRESS}\`.
- Uses treasury reference script \`${TREASURY_SCRIPT_REF}\`.
- Uses registry reference input \`${REGISTRY_TX_IN}\`.
- Metadata file: \`${METADATA_JSON_FILE}\`.
- Verify this transaction id after submission before committing the journal entry.
EOF

echo "Journal draft: ${JOURNAL_DRAFT_FILE}"
