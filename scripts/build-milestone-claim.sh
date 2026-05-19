#!/usr/bin/env bash
set -euo pipefail

# Build a Blink Labs milestone claim transaction using cardano-cli only.
# Defaults to the bootstrap milestone, M-0.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
    cat <<'EOF'
Usage:
  NETWORK=mainnet CARDANO_NODE_SOCKET_PATH=/path/to/node.socket \
  PAYMENT_ADDRESS=addr... PAYMENT_SKEY=keys/blink.skey make claim-milestones

Required unless provided by config.env:
  CARDANO_NODE_SOCKET_PATH   node socket for cardano-cli transaction build
  PAYMENT_ADDRESS            fee/change address; WALLET_ADDRESS is also accepted

Optional:
  CLAIM_MILESTONES           comma/space separated milestone ids; default M-0
  VENDOR_TX_IN               explicit vendor UTxO; otherwise auto-selected
  PAYMENT_SKEY               fee-payer / Blink signing key; writes a witness if set
  SIGNING_KEYS               comma/space separated extra signing keys
  EXTRA_SIGNING_KEYS         comma/space separated extra signing keys
  BLINK_LABS_KEYHASH         vendor key hash; defaults to the saved txAuthor
  TX_AUTHOR_HASH             TOM metadata author hash; defaults to BLINK_LABS_KEYHASH
  FEE_TX_IN                  explicit fee input
  COLLATERAL_TX_IN           explicit collateral input
  INVALID_BEFORE             explicit lower validity slot; default current slot
  INVALID_HEREAFTER          explicit upper validity slot
  VALIDITY_TTL_SLOTS         slots added to INVALID_BEFORE; default 86400
  WITNESS_COUNT              witness estimate for fee calculation; default 2
  OUT_DIR                    output directory

Outputs:
  tmp/<run>/tx-milestone-claim.raw
  tmp/<run>/tx-milestone-claim.witness, if signing keys are provided
  tmp/<run>/tx-milestone-claim.partial.signed, if signing keys are provided
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

require_key_hash() {
    local label="$1"
    local hash="$2"
    if [[ ! "$hash" =~ ^[0-9a-fA-F]{56}$ ]]; then
        echo "Error: ${label} must be a 28-byte key hash hex string: ${hash}" >&2
        exit 1
    fi
}

INSTANCE_ID="${INSTANCE_ID:-d161c89f1123fac8043df44aeec0ca36b2a76e84df47592fe92980ac}"
METADATA_FILE="${INSTANCE_METADATA_FILE:-${REPO_ROOT}/metadata/offchain-metadata.json}"
METADATA_FILE="$(resolve_path "$METADATA_FILE")"

if [[ ! -f "$METADATA_FILE" ]]; then
    echo "Error: metadata file not found: ${METADATA_FILE}" >&2
    exit 1
fi

USDCX_POLICY_ID="${USDCX_POLICY_ID:-1f3aec8bfe7ea4fe14c5f121e2a92e301afe414147860d557cac7e34}"
USDCX_ASSET_NAME="${USDCX_ASSET_NAME:-5553444378}"
USDCX_DESTINATION="${USDCX_DESTINATION:-addr1q8g9808jhwhqjp3ylqgdpzzuur4u53n5zv4ahadskq6djd3lwzwsdphplcdpzla0vnksx0vd2xk70ykyfl3fmuwxr4vqv7tkrw}"
ADA_DESTINATION="${ADA_DESTINATION:-addr1qyzc5k4sceny0hxwsttjgnuqhl4yrwnkclyuetux5sdsplh9r9z8yaghysf05atjyv79t73lercjdqnejetxm307m49qsugwpk}"
USDCX_OUTPUT_MIN_ADA="${USDCX_OUTPUT_MIN_ADA:-2000000}"
VALIDITY_TTL_SLOTS="${VALIDITY_TTL_SLOTS:-86400}"

METADATA_TX_AUTHOR="$(
    jq -r --arg instance "$INSTANCE_ID" \
        '.[$instance].metadata.txAuthor // empty' \
        "$METADATA_FILE"
)"
BLINK_LABS_KEYHASH="${BLINK_LABS_KEYHASH:-${METADATA_TX_AUTHOR:-058a5ab0c66647dcce82d7244f80bfea41ba76c7c9ccaf86a41b00fe}}"
TX_AUTHOR_HASH="${TX_AUTHOR_HASH:-$BLINK_LABS_KEYHASH}"
require_key_hash "BLINK_LABS_KEYHASH" "$BLINK_LABS_KEYHASH"
require_key_hash "TX_AUTHOR_HASH" "$TX_AUTHOR_HASH"

require CARDANO_NODE_SOCKET_PATH
PAYMENT_ADDRESS="${PAYMENT_ADDRESS:-${WALLET_ADDRESS:-}}"
CHANGE_ADDRESS="${CHANGE_ADDRESS:-$PAYMENT_ADDRESS}"
if [[ -z "$CHANGE_ADDRESS" ]]; then
    echo "Error: PAYMENT_ADDRESS, WALLET_ADDRESS, or CHANGE_ADDRESS is required." >&2
    exit 1
fi

REGISTRY_TX_IN="${REGISTRY_TX_IN:-576feff7b2f634ce2320be715f661a23944ed1157844121fbc5515c4feda155e#0}"
CLAIM_MILESTONES="${CLAIM_MILESTONES:-M-0}"

RUN_LABEL="${RUN_LABEL:-$(date -u +%Y-%m-%d-milestone-claim)}"
OUT_DIR="${OUT_DIR:-tmp/${RUN_LABEL}}"
mkdir -p "$OUT_DIR"

VENDOR_SCRIPT_FILE="${OUT_DIR}/vendor.plutus"
SCHEDULE_FILE="${OUT_DIR}/milestone-schedule.json"
REDEEMER_FILE="${OUT_DIR}/withdraw-redeemer.json"
REMAINING_DATUM_FILE="${OUT_DIR}/vendor-datum-remaining.json"
METADATA_JSON_FILE="${METADATA_JSON_FILE:-${OUT_DIR}/metadata-milestone-claim.json}"
VENDOR_SELECTED_JSON="${OUT_DIR}/vendor-selected-utxo.json"
MANIFEST_FILE="${OUT_DIR}/manifest.tsv"
TX_BODY_FILE="${TX_BODY_FILE:-${OUT_DIR}/tx-milestone-claim.raw}"
WITNESS_FILE="${WITNESS_FILE:-${OUT_DIR}/tx-milestone-claim.witness}"
PARTIAL_SIGNED_FILE="${PARTIAL_SIGNED_FILE:-${OUT_DIR}/tx-milestone-claim.partial.signed}"

write_plutus_script() {
    local script_name="$1"
    local out_file="$2"
    local cbor

    cbor="$(
        jq -er --arg instance "$INSTANCE_ID" --arg script "$script_name" '
          .[$instance].scripts[$script].script
        ' "$METADATA_FILE"
    )" || {
        echo "Error: could not read ${script_name} from ${METADATA_FILE} for instance ${INSTANCE_ID}." >&2
        exit 1
    }

    jq -n --arg cbor "$cbor" '
      {type:"PlutusScriptV3", description:"", cborHex:$cbor}
    ' > "$out_file"

    if [[ ! -s "$out_file" ]]; then
        echo "Error: failed to write Plutus script file: ${out_file}" >&2
        exit 1
    fi
}

write_plutus_script vendorScript "$VENDOR_SCRIPT_FILE"

VENDOR_SCRIPT_ADDRESS="$(
    cardano-cli address build \
        --payment-script-file "$VENDOR_SCRIPT_FILE" \
        --stake-script-file "$VENDOR_SCRIPT_FILE" \
        "${NETWORK_FLAG[@]}"
)"

cardano-cli address info --address "$VENDOR_SCRIPT_ADDRESS" >/dev/null
cardano-cli address info --address "$USDCX_DESTINATION" >/dev/null
cardano-cli address info --address "$ADA_DESTINATION" >/dev/null
cardano-cli address info --address "$CHANGE_ADDRESS" >/dev/null

jq -n '
[
  {id:"M-0", description:"Bootstrap", usdcx_base:225000000000, ada_lovelace:0, date_utc:"2026-05-18T00:00:00Z", maturation:1779062400000, status:"Active"},
  {id:"M-1", description:"Infra May", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-05-31T00:00:00Z", maturation:1780185600000, status:"Active"},
  {id:"M-2", description:"Q2 Testnet", usdcx_base:225000000000, ada_lovelace:92500000000, date_utc:"2026-06-30T00:00:00Z", maturation:1782777600000, status:"Active"},
  {id:"M-3", description:"Infra June", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-06-30T00:00:00Z", maturation:1782777600000, status:"Active"},
  {id:"M-4", description:"Infra July", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-07-31T00:00:00Z", maturation:1785456000000, status:"Active"},
  {id:"M-5", description:"Infra August", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-08-31T00:00:00Z", maturation:1788134400000, status:"Active"},
  {id:"M-6", description:"Q3 Storage", usdcx_base:225000000000, ada_lovelace:92500000000, date_utc:"2026-09-30T00:00:00Z", maturation:1790726400000, status:"Active"},
  {id:"M-7", description:"Infra September", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-09-30T00:00:00Z", maturation:1790726400000, status:"Active"},
  {id:"M-8", description:"Infra October", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-10-31T00:00:00Z", maturation:1793404800000, status:"Active"},
  {id:"M-9", description:"Infra November", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-11-30T00:00:00Z", maturation:1795996800000, status:"Active"},
  {id:"M-10", description:"Audit", usdcx_base:500000000000, ada_lovelace:0, date_utc:"2026-06-30T00:00:00Z", maturation:1782777600000, status:"Paused"},
  {id:"M-11", description:"Q4 Leios", usdcx_base:225000000000, ada_lovelace:92500000000, date_utc:"2026-12-31T00:00:00Z", maturation:1798675200000, status:"Active"},
  {id:"M-12", description:"Infra December", usdcx_base:4166666667, ada_lovelace:0, date_utc:"2026-12-31T00:00:00Z", maturation:1798675200000, status:"Active"},
  {id:"M-13", description:"Q1 Mainnet", usdcx_base:95000000000, ada_lovelace:92500000000, date_utc:"2027-01-31T00:00:00Z", maturation:1801353600000, status:"Active"}
]
' > "$SCHEDULE_FILE"

CLAIM_IDS_JSON="$(
    split_words "$CLAIM_MILESTONES" | jq -R . | jq -s .
)"
if [[ "$CLAIM_IDS_JSON" == "[]" ]]; then
    echo "Error: CLAIM_MILESTONES did not contain any milestone ids." >&2
    exit 1
fi

UNKNOWN_CLAIMS="$(
    jq -r --argjson ids "$CLAIM_IDS_JSON" '
      [ $ids[] as $id | select(([.[].id] | index($id) | not)) | $id ] | join(" ")
    ' "$SCHEDULE_FILE"
)"
if [[ -n "$UNKNOWN_CLAIMS" ]]; then
    echo "Error: unknown milestone id(s): ${UNKNOWN_CLAIMS}" >&2
    exit 1
fi

NOW_MS="$(date -u +%s)000"
UNMATURED_CLAIMS="$(
    jq -r --argjson ids "$CLAIM_IDS_JSON" --argjson now "$NOW_MS" '
      [ .[]
        | select(.id as $id | $ids | index($id))
        | select(.status != "Active" or .maturation >= $now)
        | "\(.id)(status=\(.status),date=\(.date_utc))"
      ] | join(" ")
    ' "$SCHEDULE_FILE"
)"
if [[ -n "$UNMATURED_CLAIMS" && "${ALLOW_UNMATURED_CLAIM:-0}" != "1" ]]; then
    echo "Error: selected milestone(s) are not active and mature yet: ${UNMATURED_CLAIMS}" >&2
    echo "Set CLAIM_MILESTONES to an active matured milestone, or set ALLOW_UNMATURED_CLAIM=1 for dry-run debugging only." >&2
    exit 1
fi

read -r CLAIM_USDCX CLAIM_ADA CLAIM_COUNT REMAINING_COUNT < <(
    jq -r --argjson ids "$CLAIM_IDS_JSON" '
      [
        ([.[] | select(.id as $id | $ids | index($id)) | .usdcx_base] | add // 0),
        ([.[] | select(.id as $id | $ids | index($id)) | .ada_lovelace] | add // 0),
        ([.[] | select(.id as $id | $ids | index($id))] | length),
        ([.[] | select(.id as $id | ($ids | index($id) | not))] | length)
      ] | @tsv
    ' "$SCHEDULE_FILE"
)

if (( CLAIM_COUNT == 0 )); then
    echo "Error: no milestones selected." >&2
    exit 1
fi
if (( CLAIM_USDCX == 0 && CLAIM_ADA == 0 )); then
    echo "Error: selected milestones have no payout." >&2
    exit 1
fi

jq -n '{constructor: 0, fields: []}' > "$REDEEMER_FILE"

jq \
    --arg vendor "$BLINK_LABS_KEYHASH" \
    --arg policy "$USDCX_POLICY_ID" \
    --arg asset "$USDCX_ASSET_NAME" \
    --argjson ids "$CLAIM_IDS_JSON" '
  def value_map($lovelace; $policy_id; $asset_name; $asset_amount):
    {
      map: [
        if $lovelace > 0 then
          {k:{bytes:""}, v:{map:[{k:{bytes:""}, v:{int:$lovelace}}]}}
        else empty end,
        if $asset_amount > 0 then
          {k:{bytes:$policy_id}, v:{map:[{k:{bytes:$asset_name}, v:{int:$asset_amount}}]}}
        else empty end
      ]
    };
  map(select(.id as $id | ($ids | index($id) | not)))
  | {
      constructor: 0,
      fields: [
        {constructor: 0, fields: [{bytes: $vendor}]},
        {
          list: map({
            constructor: 0,
            fields: [
              {int: .maturation},
              value_map(.ada_lovelace; $policy; $asset; .usdcx_base),
              {
                constructor: (if .status == "Paused" then 1 else 0 end),
                fields: []
              }
            ]
          })
        }
      ]
    }
' "$SCHEDULE_FILE" > "$REMAINING_DATUM_FILE"

if [[ ! -s "$METADATA_JSON_FILE" ]]; then
    jq -n \
        --slurpfile schedule "$SCHEDULE_FILE" \
        --arg context "https://raw.githubusercontent.com/SundaeSwap-finance/treasury-contracts/refs/heads/main/offchain/src/metadata/context.jsonld" \
        --arg instance "$INSTANCE_ID" \
        --arg txAuthor "$TX_AUTHOR_HASH" \
        --argjson ids "$CLAIM_IDS_JSON" '
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
        $schedule[0] as $milestones
        | {
            "1694": {
              "@context": $context,
              "hashAlgorithm": "blake2b-256",
              "txAuthor": $txAuthor,
              "instance": $instance,
              "body": {
                "event": "withdraw",
                "milestones": (
                  reduce ($milestones[] | select(.id as $id | $ids | index($id))) as $m
                    ({}; .[$m.id] = {comment: ("Claim " + $m.description + " milestone payout.")})
                )
              },
              "comment": "Blink Labs milestone claim."
            }
          } | chunk_long_strings
    ' > "$METADATA_JSON_FILE"
fi
jq empty "$METADATA_JSON_FILE" || {
    echo "Error: metadata JSON is invalid: ${METADATA_JSON_FILE}" >&2
    exit 1
}

if [[ -z "${INVALID_BEFORE:-}" || -z "${INVALID_HEREAFTER:-}" ]]; then
    TIP_JSON="$(
        cardano-cli conway query tip \
            "${NETWORK_FLAG[@]}" \
            --socket-path "$CARDANO_NODE_SOCKET_PATH"
    )"
    CURRENT_SLOT="$(jq -r '.slot // empty' <<<"$TIP_JSON")"
    if [[ -z "$CURRENT_SLOT" || ! "$CURRENT_SLOT" =~ ^[0-9]+$ ]]; then
        echo "Error: could not read current slot from query tip." >&2
        exit 1
    fi
    INVALID_BEFORE="${INVALID_BEFORE:-$CURRENT_SLOT}"
    INVALID_HEREAFTER="${INVALID_HEREAFTER:-$((INVALID_BEFORE + VALIDITY_TTL_SLOTS))}"
fi

if [[ -z "${VENDOR_TX_IN:-}" ]]; then
    VENDOR_UTXOS="${OUT_DIR}/vendor-all-utxos.json"
    query_utxo_json --address "$VENDOR_SCRIPT_ADDRESS" > "$VENDOR_UTXOS"
    VENDOR_TX_IN="$(
        jq -r --arg policy "$USDCX_POLICY_ID" --arg asset "$USDCX_ASSET_NAME" --argjson claim "$CLAIM_USDCX" '
          [to_entries[]
            | {
                txin: .key,
                lovelace: (.value.value.lovelace // 0),
                usdcx: (.value.value[$policy][$asset] // 0),
                has_inline_datum: (((.value.inlineDatum? // .value.inlineDatumRaw? // null) != null))
              }
            | select(.has_inline_datum and .usdcx >= $claim)]
          | sort_by(-.usdcx, -.lovelace)
          | .[0].txin // empty
        ' "$VENDOR_UTXOS"
    )"
    if [[ -z "$VENDOR_TX_IN" ]]; then
        echo "Error: no vendor UTxO with an inline datum can cover the selected USDCx claim." >&2
        echo "Set VENDOR_TX_IN=<txid#index> explicitly, usually the funding tx output at the vendor address." >&2
        exit 1
    fi
fi

query_utxo_json --tx-in "$VENDOR_TX_IN" > "$VENDOR_SELECTED_JSON"
read -r VENDOR_INPUT_LOVELACE VENDOR_INPUT_USDCX < <(
    jq -r --arg txin "$VENDOR_TX_IN" --arg policy "$USDCX_POLICY_ID" --arg asset "$USDCX_ASSET_NAME" '
      [
        (.[$txin].value.lovelace // 0),
        (.[$txin].value[$policy][$asset] // 0)
      ] | @tsv
    ' "$VENDOR_SELECTED_JSON"
)
if (( VENDOR_INPUT_USDCX < CLAIM_USDCX )); then
    echo "Error: vendor input contains ${VENDOR_INPUT_USDCX} USDCx base units; claim needs ${CLAIM_USDCX}." >&2
    exit 1
fi
if (( VENDOR_INPUT_LOVELACE < CLAIM_ADA )); then
    echo "Error: vendor input contains ${VENDOR_INPUT_LOVELACE} lovelace; claim needs ${CLAIM_ADA}." >&2
    exit 1
fi

VENDOR_REMAINDER_LOVELACE=$((VENDOR_INPUT_LOVELACE - CLAIM_ADA))
VENDOR_REMAINDER_ASSETS="$(
    jq -r \
      --arg policy "$USDCX_POLICY_ID" \
      --arg asset "$USDCX_ASSET_NAME" \
      --argjson usdcx "$CLAIM_USDCX" '
      reduce (
        to_entries[]
        | .value.value
        | to_entries[]
        | select(.key != "lovelace")
        | .key as $policy_id
        | .value
        | to_entries[]
        | {policy: $policy_id, asset: .key, qty: .value}
      ) as $a
      ({}; .[$a.policy][$a.asset] += $a.qty)
      | to_entries
      | map(
          .key as $policy_id
          | .value
          | to_entries[]
          | {
              policy: $policy_id,
              asset: .key,
              qty: (.value - (if $policy_id == $policy and .key == $asset then $usdcx else 0 end))
            }
          | select(.qty > 0)
          | "\(.qty) \(.policy).\(.asset)"
        )
      | join(" + ")
    ' "$VENDOR_SELECTED_JSON"
)"
VENDOR_REMAINDER_VALUE="${VENDOR_REMAINDER_LOVELACE}${VENDOR_REMAINDER_ASSETS:+ + ${VENDOR_REMAINDER_ASSETS}}"

SELECTED_FEE_UTXOS=()
if [[ -z "${FEE_TX_IN:-}" ]]; then
    if [[ -z "$PAYMENT_ADDRESS" ]]; then
        echo "Error: PAYMENT_ADDRESS or FEE_TX_IN is required for fee input selection." >&2
        exit 1
    fi
    FEE_UTXOS="$(query_utxo_json --address "$PAYMENT_ADDRESS")"
    mapfile -t SELECTED_FEE_UTXOS < <(
        jq -r '
          [to_entries[]
            | {
                txin: .key,
                lovelace: (.value.value.lovelace // 0),
                asset_count: ([.value.value | keys[] | select(. != "lovelace")] | length)
              }
            | select(.lovelace > 5000000)]
          | sort_by(.asset_count, -.lovelace)
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

TX_OUTPUT_FLAGS=()
if (( CLAIM_USDCX > 0 )); then
    TX_OUTPUT_FLAGS+=(
        --tx-out "${USDCX_DESTINATION}+${USDCX_OUTPUT_MIN_ADA} + ${CLAIM_USDCX} ${USDCX_POLICY_ID}.${USDCX_ASSET_NAME}"
    )
fi
if (( CLAIM_ADA > 0 )); then
    TX_OUTPUT_FLAGS+=(
        --tx-out "${ADA_DESTINATION}+${CLAIM_ADA}"
    )
fi
if (( REMAINING_COUNT > 0 )) || (( VENDOR_REMAINDER_LOVELACE > 0 )) || [[ -n "$VENDOR_REMAINDER_ASSETS" ]]; then
    TX_OUTPUT_FLAGS+=(
        --tx-out "${VENDOR_SCRIPT_ADDRESS}+${VENDOR_REMAINDER_VALUE}"
        --tx-out-inline-datum-file "$REMAINING_DATUM_FILE"
    )
fi

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

WITNESS_COUNT="${WITNESS_COUNT:-2}"

echo "Network:                 ${NETWORK_FLAG[*]}"
echo "Output dir:              ${OUT_DIR}"
echo "Claim milestones:        ${CLAIM_MILESTONES}"
echo "Vendor address:          ${VENDOR_SCRIPT_ADDRESS}"
echo "Vendor input:            ${VENDOR_TX_IN}"
echo "Vendor input ADA:        ${VENDOR_INPUT_LOVELACE}"
echo "Vendor input USDCx:      ${VENDOR_INPUT_USDCX}"
echo "Claim USDCx:             ${CLAIM_USDCX}"
echo "Claim ADA:               ${CLAIM_ADA}"
echo "USDCx destination:       ${USDCX_DESTINATION}"
echo "ADA destination:         ${ADA_DESTINATION}"
echo "Vendor remainder:        ${VENDOR_REMAINDER_VALUE}"
echo "Fee input:               ${FEE_TX_IN}"
echo "Collateral input:        ${COLLATERAL_TX_IN}"
echo "Required signer:         ${BLINK_LABS_KEYHASH}"
echo "Witness override:        ${WITNESS_COUNT}"
echo "Invalid before:          ${INVALID_BEFORE}"
echo "Invalid hereafter:       ${INVALID_HEREAFTER}"
echo "Metadata:                ${METADATA_JSON_FILE}"
echo

cardano-cli conway transaction build \
    "${NETWORK_FLAG[@]}" \
    --socket-path "$CARDANO_NODE_SOCKET_PATH" \
    --witness-override "$WITNESS_COUNT" \
    --tx-in "$VENDOR_TX_IN" \
        --tx-in-script-file "$VENDOR_SCRIPT_FILE" \
        --tx-in-inline-datum-present \
        --tx-in-redeemer-file "$REDEEMER_FILE" \
    --tx-in "$FEE_TX_IN" \
    --tx-in-collateral "$COLLATERAL_TX_IN" \
    --read-only-tx-in-reference "$REGISTRY_TX_IN" \
    --required-signer-hash "$BLINK_LABS_KEYHASH" \
    --invalid-before "$INVALID_BEFORE" \
    --invalid-hereafter "$INVALID_HEREAFTER" \
    "${TX_OUTPUT_FLAGS[@]}" \
    --change-address "$CHANGE_ADDRESS" \
    --json-metadata-no-schema \
    --metadata-json-file "$METADATA_JSON_FILE" \
    --out-file "$TX_BODY_FILE"

TX_ID="$(
    cardano-cli conway transaction txid \
        --tx-body-file "$TX_BODY_FILE" \
        --output-text
)"

WITNESS_OUTPUT=""
PARTIAL_SIGNED_OUTPUT=""
if [[ ${#SIGNING_KEY_FLAGS[@]} -gt 0 ]]; then
    cardano-cli conway transaction witness \
        --tx-body-file "$TX_BODY_FILE" \
        "${SIGNING_KEY_FLAGS[@]}" \
        "${NETWORK_FLAG[@]}" \
        --out-file "$WITNESS_FILE"
    cardano-cli conway transaction assemble \
        --tx-body-file "$TX_BODY_FILE" \
        --witness-file "$WITNESS_FILE" \
        --out-file "$PARTIAL_SIGNED_FILE"
    WITNESS_OUTPUT="$WITNESS_FILE"
    PARTIAL_SIGNED_OUTPUT="$PARTIAL_SIGNED_FILE"
fi

METADATA_HASH="$(
    cardano-cli hash anchor-data --file-text "$METADATA_JSON_FILE"
)"

printf 'tx_id\ttx_body\twitness\tassembled_tx\tmetadata\tmetadata_hash\tclaim_milestones\n' > "$MANIFEST_FILE"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$TX_ID" \
    "$TX_BODY_FILE" \
    "$WITNESS_OUTPUT" \
    "$PARTIAL_SIGNED_OUTPUT" \
    "$METADATA_JSON_FILE" \
    "$METADATA_HASH" \
    "$CLAIM_MILESTONES" >> "$MANIFEST_FILE"

echo "Built milestone claim tx: ${TX_ID}"
echo "Tx body: ${TX_BODY_FILE}"
if [[ -n "$WITNESS_OUTPUT" ]]; then
    echo "Witness: ${WITNESS_OUTPUT}"
    echo "Partial signed tx: ${PARTIAL_SIGNED_OUTPUT}"
fi
echo "Metadata hash: ${METADATA_HASH}"
echo "Manifest: ${MANIFEST_FILE}"
