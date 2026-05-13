#!/usr/bin/env bash
set -euo pipefail

# Build one mainnet treasury disburse transaction body for each valid signer pair:
#   Chris Gianelloni + Santiago Carmuega
#   Chris Gianelloni + Pi Lanningham
#   Chris Gianelloni + Lucas Rosa
#
# This script intentionally lives outside the treasury-contracts submodule.
# It does not submit transactions.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage:
  NETWORK=mainnet CARDANO_NODE_SOCKET_PATH=/path/to/node.socket \
  PAYMENT_ADDRESS=addr... scripts/build-kraken-otc-disburse.sh

Required unless provided by config.env:
  CARDANO_NODE_SOCKET_PATH   node socket for cardano-cli transaction build
  PAYMENT_ADDRESS            fee/change address

Optional:
  PAYMENT_SKEY               fee-payer signing key; writes partial txs if set
  SIGNING_KEYS               comma/space separated extra signing keys
  EXTRA_SIGNING_KEYS         comma/space separated extra signing keys
  TREASURY_TX_IN             explicit treasury script input to spend
  FEE_TX_IN                  explicit fee input
  COLLATERAL_TX_IN           explicit collateral input
  INVALID_HEREAFTER          explicit upper validity slot
  VALIDITY_TTL_SLOTS         slots added to current tip; default 86400
  OUT_DIR                    output directory

Defaults:
  NETWORK                    mainnet
  DISBURSE_AMOUNT_LOVELACE   5630000000000
  KRAKEN_ADDRESS             addr1qyshqh3a58ht3el7pr8g7pan70mvmzzhaxv8e8ul5zlk64hrzr27g03klu862usxqsru794d03gzkk8n86ta34n85z0sujj0dz
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

CONFIG_ENV_FILE="${CONFIG_ENV_FILE:-${REPO_ROOT}/config.env}"
load_config_defaults() {
    local file="$1"
    local line key value
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        value="${value%$'\r'}"
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi
        if [[ -z "${!key+x}" ]]; then
            printf -v "$key" '%s' "$value"
            export "$key"
        fi
    done < "$file"
}
load_config_defaults "$CONFIG_ENV_FILE"

command -v cardano-cli >/dev/null 2>&1 || {
    echo "Error: cardano-cli not found in PATH." >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || {
    echo "Error: jq not found in PATH." >&2
    exit 1
}

case "${NETWORK:-mainnet}" in
    mainnet) NETWORK_FLAG=(--mainnet) ;;
    preprod) NETWORK_FLAG=(--testnet-magic 1) ;;
    preview) NETWORK_FLAG=(--testnet-magic 2) ;;
    *) echo "Error: unsupported NETWORK=${NETWORK:-}. Use mainnet, preprod, or preview." >&2; exit 1 ;;
esac

require() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "Error: ${name} is required." >&2
        exit 1
    fi
}

resolve_path() {
    local path="$1"
    if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s\n' "${REPO_ROOT}/${path}"
    fi
}

split_words() {
    local value="$1"
    tr ',[:space:]' '\n' <<<"$value" | sed '/^$/d'
}

query_utxo_json() {
    cardano-cli conway query utxo \
        "${NETWORK_FLAG[@]}" \
        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
        "$@" \
        --output-json
}

DISBURSE_AMOUNT_LOVELACE="${DISBURSE_AMOUNT_LOVELACE:-5630000000000}"
KRAKEN_ADDRESS="${KRAKEN_ADDRESS:-addr1qyshqh3a58ht3el7pr8g7pan70mvmzzhaxv8e8ul5zlk64hrzr27g03klu862usxqsru794d03gzkk8n86ta34n85z0sujj0dz}"
TREASURY_SCRIPT_ADDRESS="${TREASURY_SCRIPT_ADDRESS:-addr1x90c5a0h3qwkxquehkdg746ccaa3hdfzgp7ckx6wzdpp7lzl3f6l0zqavvpen0v63at433mmrw6jysra3vd5uy6zra7qgffay3}"
TREASURY_SCRIPT_REF="${TREASURY_SCRIPT_REF:-c133b8687c8550a8e7224421e45a7a67bc0941c85b8138f0f9e9498cce8fca08#0}"
REGISTRY_TX_IN="${REGISTRY_TX_IN:-576feff7b2f634ce2320be715f661a23944ed1157844121fbc5515c4feda155e#0}"
VALIDITY_TTL_SLOTS="${VALIDITY_TTL_SLOTS:-86400}"
WITNESS_COUNT="${WITNESS_COUNT:-3}"

TX_AUTHOR_HASH="${TX_AUTHOR_HASH:-${BLINK_LABS_KEYHASH:-058a5ab0c66647dcce82d7244f80bfea41ba76c7c9ccaf86a41b00fe}}"
SANTIAGO_HASH="${OVERSIGHT_SANTIAGO_CARMUEGA:-946a76ec4564f793d643cb13ff900f2ec578bcd521addab275af5ebb}"
PI_HASH="${OVERSIGHT_PI_LANNINGHAM:-e0b68e229f9c043ab610067ed7f3c6d662b8f3c6bb4ec452c11f6411}"
LUCAS_HASH="${OVERSIGHT_LUCAS_ROSA:-ccc4a58ebc9aa058cd0dee6f84e4de39e23574a054e405b0ca467a88}"

require CARDANO_NODE_SOCKET_PATH
CHANGE_ADDRESS="${CHANGE_ADDRESS:-${PAYMENT_ADDRESS:-}}"
if [[ -z "$CHANGE_ADDRESS" ]]; then
    echo "Error: PAYMENT_ADDRESS or CHANGE_ADDRESS is required." >&2
    exit 1
fi

if [[ ! "$DISBURSE_AMOUNT_LOVELACE" =~ ^[0-9]+$ ]]; then
    echo "Error: DISBURSE_AMOUNT_LOVELACE must be an integer lovelace amount." >&2
    exit 1
fi

cardano-cli address info --address "$KRAKEN_ADDRESS" >/dev/null
cardano-cli address info --address "$TREASURY_SCRIPT_ADDRESS" >/dev/null

RUN_LABEL="${RUN_LABEL:-$(date -u +%Y-%m-%d-kraken-otc)}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/tmp/${RUN_LABEL}}"
mkdir -p "$OUT_DIR"

REDEEMER_FILE="${REDEEMER_FILE:-${OUT_DIR}/disburse-redeemer.json}"
METADATA_JSON_FILE="${METADATA_JSON_FILE:-${OUT_DIR}/metadata-kraken-otc-disburse.json}"
MANIFEST_FILE="${MANIFEST_FILE:-${OUT_DIR}/manifest.tsv}"

jq -n --argjson amount "$DISBURSE_AMOUNT_LOVELACE" '
  {
    constructor: 3,
    fields: [
      {
        map: [
          {
            k: {bytes: ""},
            v: {
              map: [
                {
                  k: {bytes: ""},
                  v: {int: $amount}
                }
              ]
            }
          }
        ]
      }
    ]
  }
' > "$REDEEMER_FILE"

if [[ ! -s "$METADATA_JSON_FILE" ]]; then
    jq -n \
        --arg context "https://raw.githubusercontent.com/SundaeSwap-finance/treasury-contracts/refs/heads/main/offchain/src/metadata/context.jsonld" \
        --arg instance "d161c89f1123fac8043df44aeec0ca36b2a76e84df47592fe92980ac" \
        --arg txAuthor "$TX_AUTHOR_HASH" \
        --arg destination "Kraken OTC address" \
        --arg txLabel "Kraken OTC trade" \
        --arg description "Disburse 5,630,000 ADA to Kraken for OTC trade." \
        --arg justification "Move treasury ADA to Kraken for OTC execution." \
        --arg comment "Prepare Kraken OTC disbursement for Blink Labs treasury funds." '
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
            "hashAlgorithm": "blake2b-256",
            "txAuthor": $txAuthor,
            "instance": $instance,
            "body": {
              "event": "disburse",
              "label": $txLabel,
              "description": $description,
              "justification": $justification,
              "destination": {
                "label": $destination
              }
            },
            "comment": $comment
          }
        } | chunk_long_strings
    ' > "$METADATA_JSON_FILE"
fi
jq empty "$METADATA_JSON_FILE" || {
    echo "Error: metadata JSON is invalid: ${METADATA_JSON_FILE}" >&2
    echo "Remove the file or set METADATA_JSON_FILE to a valid metadata file." >&2
    exit 1
}

if [[ -z "${INVALID_HEREAFTER:-}" ]]; then
    TIP_JSON="$(
        cardano-cli conway query tip \
            "${NETWORK_FLAG[@]}" \
            --socket-path "$CARDANO_NODE_SOCKET_PATH"
    )"
    CURRENT_SLOT="$(jq -r '.slot // .slotInEpoch // empty' <<<"$TIP_JSON")"
    if [[ -z "$CURRENT_SLOT" || ! "$CURRENT_SLOT" =~ ^[0-9]+$ ]]; then
        echo "Error: could not read current slot from query tip." >&2
        exit 1
    fi
    INVALID_HEREAFTER=$((CURRENT_SLOT + VALIDITY_TTL_SLOTS))
fi

if [[ -z "${TREASURY_TX_IN:-}" ]]; then
    TREASURY_UTXOS="$(query_utxo_json --address "$TREASURY_SCRIPT_ADDRESS")"
    TREASURY_TX_IN="$(
        jq -r --argjson amount "$DISBURSE_AMOUNT_LOVELACE" '
          [to_entries[]
            | select(.value.value.lovelace >= $amount)
            | {txin: .key, lovelace: .value.value.lovelace}]
          | sort_by(-.lovelace)
          | .[0].txin // empty
        ' <<<"$TREASURY_UTXOS"
    )"
    if [[ -z "$TREASURY_TX_IN" ]]; then
        echo "Error: no treasury UTxO at ${TREASURY_SCRIPT_ADDRESS} can cover ${DISBURSE_AMOUNT_LOVELACE} lovelace." >&2
        echo "Set TREASURY_TX_IN=<txid#index> to choose one explicitly." >&2
        exit 1
    fi
fi

TREASURY_SELECTED="$(query_utxo_json --tx-in "$TREASURY_TX_IN")"
TREASURY_INPUT_LOVELACE="$(
    jq -r --arg txin "$TREASURY_TX_IN" '.[$txin].value.lovelace // empty' <<<"$TREASURY_SELECTED"
)"
if [[ -z "$TREASURY_INPUT_LOVELACE" ]]; then
    echo "Error: could not resolve treasury input ${TREASURY_TX_IN}." >&2
    exit 1
fi
if (( TREASURY_INPUT_LOVELACE < DISBURSE_AMOUNT_LOVELACE )); then
    echo "Error: treasury input has ${TREASURY_INPUT_LOVELACE} lovelace, need ${DISBURSE_AMOUNT_LOVELACE}." >&2
    exit 1
fi
TREASURY_REMAINDER_LOVELACE=$((TREASURY_INPUT_LOVELACE - DISBURSE_AMOUNT_LOVELACE))
TREASURY_ASSET_TERMS="$(
    jq -r --arg txin "$TREASURY_TX_IN" '
      .[$txin].value
      | to_entries
      | map(select(.key != "lovelace"))
      | map(.key as $policy | .value | to_entries[] | "\(.value) " + $policy + "." + .key)
      | join(" + ")
    ' <<<"$TREASURY_SELECTED"
)"
TREASURY_REMAINDER_VALUE="${TREASURY_REMAINDER_LOVELACE}${TREASURY_ASSET_TERMS:+ + ${TREASURY_ASSET_TERMS}}"

SELECTED_FEE_UTXOS=()
if [[ -z "${FEE_TX_IN:-}" ]]; then
    require PAYMENT_ADDRESS
    FEE_UTXOS="$(query_utxo_json --address "$PAYMENT_ADDRESS")"
    mapfile -t SELECTED_FEE_UTXOS < <(
        jq -r '
          [to_entries[]
            | select(.value.value.lovelace > 5000000)
            | {txin: .key, lovelace: .value.value.lovelace}]
          | sort_by(-.lovelace)
          | .[:2][]
          | .txin
        ' <<<"$FEE_UTXOS"
    )
    if [[ -z "${SELECTED_FEE_UTXOS[0]:-}" ]]; then
        echo "Error: no fee UTxO over 5 ADA found at ${PAYMENT_ADDRESS}." >&2
        echo "Set FEE_TX_IN=<txid#index> to choose one explicitly." >&2
        exit 1
    fi
    FEE_TX_IN="${SELECTED_FEE_UTXOS[0]}"
fi
COLLATERAL_TX_IN="${COLLATERAL_TX_IN:-${SELECTED_FEE_UTXOS[1]:-${FEE_TX_IN}}}"

SIGNING_KEY_FLAGS=()
add_signing_key() {
    local key_path
    key_path="$(resolve_path "$1")"
    if [[ ! -f "$key_path" ]]; then
        echo "Error: signing key not found: ${key_path}" >&2
        exit 1
    fi
    SIGNING_KEY_FLAGS+=(--signing-key-file "$key_path")
}

if [[ -n "${PAYMENT_SKEY:-}" ]]; then
    add_signing_key "$PAYMENT_SKEY"
fi
if [[ -n "${SIGNING_KEYS:-}" ]]; then
    while IFS= read -r signing_key; do
        add_signing_key "$signing_key"
    done < <(split_words "$SIGNING_KEYS")
fi
if [[ -n "${EXTRA_SIGNING_KEYS:-}" ]]; then
    while IFS= read -r signing_key; do
        add_signing_key "$signing_key"
    done < <(split_words "$EXTRA_SIGNING_KEYS")
fi

printf 'candidate\tboard_hash\ttx_id\ttx_body\twitness\tassembled_tx\n' > "$MANIFEST_FILE"

echo "Network:             ${NETWORK_FLAG[*]}"
echo "Output dir:          ${OUT_DIR}"
echo "Treasury input:      ${TREASURY_TX_IN} (${TREASURY_INPUT_LOVELACE} lovelace)"
echo "Kraken output:       ${DISBURSE_AMOUNT_LOVELACE} lovelace"
echo "Treasury remainder:  ${TREASURY_REMAINDER_VALUE}"
echo "Fee input:           ${FEE_TX_IN}"
echo "Collateral input:    ${COLLATERAL_TX_IN}"
echo "Invalid hereafter:   ${INVALID_HEREAFTER}"
echo "Metadata:            ${METADATA_JSON_FILE}"
echo

CANDIDATES=(
    "santiago-carmuega:${SANTIAGO_HASH}"
    "pi-lanningham:${PI_HASH}"
    "lucas-rosa:${LUCAS_HASH}"
)

for candidate in "${CANDIDATES[@]}"; do
    signer_label="${candidate%%:*}"
    board_hash="${candidate#*:}"
    tx_body="${OUT_DIR}/tx-kraken-otc-chris-${signer_label}.raw"
    witness_file=""
    assembled_tx=""

    cardano-cli conway transaction build \
        "${NETWORK_FLAG[@]}" \
        --socket-path "$CARDANO_NODE_SOCKET_PATH" \
        --witness-override "$WITNESS_COUNT" \
        --tx-in "$TREASURY_TX_IN" \
            --spending-tx-in-reference "$TREASURY_SCRIPT_REF" \
            --spending-plutus-script-v3 \
            --spending-reference-tx-in-inline-datum-present \
            --spending-reference-tx-in-redeemer-file "$REDEEMER_FILE" \
        --tx-in "$FEE_TX_IN" \
        --tx-in-collateral "$COLLATERAL_TX_IN" \
        --read-only-tx-in-reference "$REGISTRY_TX_IN" \
        --required-signer-hash "$TX_AUTHOR_HASH" \
        --required-signer-hash "$board_hash" \
        --invalid-hereafter "$INVALID_HEREAFTER" \
        --tx-out "${KRAKEN_ADDRESS}+${DISBURSE_AMOUNT_LOVELACE}" \
        --tx-out "${TREASURY_SCRIPT_ADDRESS}+${TREASURY_REMAINDER_VALUE}" \
        --tx-out-inline-datum-value '{}' \
        --change-address "$CHANGE_ADDRESS" \
        --json-metadata-no-schema \
        --metadata-json-file "$METADATA_JSON_FILE" \
        --out-file "$tx_body"

    tx_id="$(
        cardano-cli conway transaction txid \
            --tx-body-file "$tx_body" \
            --output-text
    )"

    if [[ ${#SIGNING_KEY_FLAGS[@]} -gt 0 ]]; then
        witness_file="${OUT_DIR}/tx-kraken-otc-chris-${signer_label}.witness"
        assembled_tx="${OUT_DIR}/tx-kraken-otc-chris-${signer_label}.partial.signed"
        cardano-cli conway transaction witness \
            --tx-body-file "$tx_body" \
            "${SIGNING_KEY_FLAGS[@]}" \
            "${NETWORK_FLAG[@]}" \
            --out-file "$witness_file"
        cardano-cli conway transaction assemble \
            --tx-body-file "$tx_body" \
            --witness-file "$witness_file" \
            --out-file "$assembled_tx"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "chris-${signer_label}" \
        "$board_hash" \
        "$tx_id" \
        "$tx_body" \
        "$witness_file" \
        "$assembled_tx" >> "$MANIFEST_FILE"

    echo "Built chris-${signer_label}: ${tx_id}"
done

echo
echo "Manifest: ${MANIFEST_FILE}"
