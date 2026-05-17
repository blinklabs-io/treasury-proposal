#!/usr/bin/env bash
set -euo pipefail

# Build the Blink Labs mixed ADA/USDCx milestone funding transaction using
# cardano-cli only. This intentionally avoids the Bun/Blaze runtime path.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<'EOF'
Usage:
  NETWORK=mainnet CARDANO_NODE_SOCKET_PATH=/path/to/node.socket \
  PAYMENT_ADDRESS=addr... make fund-milestones

Required unless provided by config.env:
  CARDANO_NODE_SOCKET_PATH   node socket for cardano-cli transaction build
  PAYMENT_ADDRESS            fee/change address; WALLET_ADDRESS is also accepted

Optional:
  PAYMENT_SKEY               fee-payer / Blink signing key; writes a witness if set
  SIGNING_KEYS               comma/space separated extra signing keys
  EXTRA_SIGNING_KEYS         comma/space separated extra signing keys
  BLINK_LABS_KEYHASH         vendor key hash; defaults to the saved txAuthor
  TX_AUTHOR_HASH             TOM metadata author hash; defaults to BLINK_LABS_KEYHASH
  TREASURY_TX_INS            explicit treasury inputs, comma or space separated
  TREASURY_TX_IN             explicit single treasury input
  FEE_TX_IN                  explicit fee input
  COLLATERAL_TX_IN           explicit collateral input
  INVALID_HEREAFTER          explicit upper validity slot
  VALIDITY_TTL_SLOTS         slots added to current tip; default 86400
  WITNESS_COUNT              witness estimate for fee calculation; default signers + 1
  OUT_DIR                    output directory

Outputs:
  tmp/<run>/tx-milestone-fund.raw
  tmp/<run>/tx-milestone-fund.witness, if signing keys are provided
  tmp/<run>/tx-milestone-fund.partial.signed, if signing keys are provided
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

add_unique() {
    local value="$1"
    shift
    local -n target_array="$1"
    local existing
    for existing in "${target_array[@]}"; do
        [[ "$existing" == "$value" ]] && return 0
    done
    target_array+=("$value")
}

contains_txin() {
    local needle="$1"
    local existing
    for existing in "${SELECTED_TREASURY_TX_INS[@]}"; do
        [[ "$existing" == "$needle" ]] && return 0
    done
    return 1
}

add_selected_treasury_txin() {
    local txin="$1"
    local lovelace="$2"
    local usdcx="$3"
    if contains_txin "$txin"; then
        return 0
    fi
    SELECTED_TREASURY_TX_INS+=("$txin")
    SELECTED_TREASURY_LOVELACE=$((SELECTED_TREASURY_LOVELACE + lovelace))
    SELECTED_TREASURY_USDCX=$((SELECTED_TREASURY_USDCX + usdcx))
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
USDCX_TOTAL_BASE="${USDCX_TOTAL_BASE:-1528333333336}"
ADA_TOTAL_LOVELACE="${ADA_TOTAL_LOVELACE:-370000000000}"
VALIDITY_TTL_SLOTS="${VALIDITY_TTL_SLOTS:-86400}"

METADATA_TX_AUTHOR="$(
    jq -r --arg instance "$INSTANCE_ID" \
        '.[$instance].metadata.txAuthor // empty' \
        "$METADATA_FILE"
)"
BLINK_LABS_KEYHASH="${BLINK_LABS_KEYHASH:-${METADATA_TX_AUTHOR:-058a5ab0c66647dcce82d7244f80bfea41ba76c7c9ccaf86a41b00fe}}"
TX_AUTHOR_HASH="${TX_AUTHOR_HASH:-$BLINK_LABS_KEYHASH}"
LUCAS_HASH="${OVERSIGHT_LUCAS_ROSA:-ccc4a58ebc9aa058cd0dee6f84e4de39e23574a054e405b0ca467a88}"
SANTIAGO_HASH="${OVERSIGHT_SANTIAGO_CARMUEGA:-946a76ec4564f793d643cb13ff900f2ec578bcd521addab275af5ebb}"

require_key_hash "BLINK_LABS_KEYHASH" "$BLINK_LABS_KEYHASH"
require_key_hash "TX_AUTHOR_HASH" "$TX_AUTHOR_HASH"
require_key_hash "OVERSIGHT_LUCAS_ROSA" "$LUCAS_HASH"
require_key_hash "OVERSIGHT_SANTIAGO_CARMUEGA" "$SANTIAGO_HASH"

require CARDANO_NODE_SOCKET_PATH
PAYMENT_ADDRESS="${PAYMENT_ADDRESS:-${WALLET_ADDRESS:-}}"
CHANGE_ADDRESS="${CHANGE_ADDRESS:-$PAYMENT_ADDRESS}"
if [[ -z "$CHANGE_ADDRESS" ]]; then
    echo "Error: PAYMENT_ADDRESS, WALLET_ADDRESS, or CHANGE_ADDRESS is required." >&2
    exit 1
fi

TREASURY_SCRIPT_REF="${TREASURY_SCRIPT_REF:-c133b8687c8550a8e7224421e45a7a67bc0941c85b8138f0f9e9498cce8fca08#0}"
REGISTRY_TX_IN="${REGISTRY_TX_IN:-576feff7b2f634ce2320be715f661a23944ed1157844121fbc5515c4feda155e#0}"

RUN_LABEL="${RUN_LABEL:-$(date -u +%Y-%m-%d-milestone-fund)}"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/tmp/${RUN_LABEL}}"
mkdir -p "$OUT_DIR"

TREASURY_SCRIPT_FILE="${OUT_DIR}/treasury.plutus"
VENDOR_SCRIPT_FILE="${OUT_DIR}/vendor.plutus"
SCHEDULE_FILE="${OUT_DIR}/milestone-schedule.json"
REDEEMER_FILE="${OUT_DIR}/fund-redeemer.json"
VENDOR_DATUM_FILE="${OUT_DIR}/vendor-datum.json"
METADATA_JSON_FILE="${METADATA_JSON_FILE:-${OUT_DIR}/metadata-milestone-fund.json}"
TREASURY_SELECTED_JSON="${OUT_DIR}/treasury-selected-utxos.json"
MANIFEST_FILE="${OUT_DIR}/manifest.tsv"
TX_BODY_FILE="${TX_BODY_FILE:-${OUT_DIR}/tx-milestone-fund.raw}"
WITNESS_FILE="${WITNESS_FILE:-${OUT_DIR}/tx-milestone-fund.witness}"
PARTIAL_SIGNED_FILE="${PARTIAL_SIGNED_FILE:-${OUT_DIR}/tx-milestone-fund.partial.signed}"

jq -r --arg instance "$INSTANCE_ID" '
  .[$instance].scripts.treasuryScript.script
  | {type:"PlutusScriptV3", description:"", cborHex:.}
' "$METADATA_FILE" > "$TREASURY_SCRIPT_FILE"

jq -r --arg instance "$INSTANCE_ID" '
  .[$instance].scripts.vendorScript.script
  | {type:"PlutusScriptV3", description:"", cborHex:.}
' "$METADATA_FILE" > "$VENDOR_SCRIPT_FILE"

TREASURY_SCRIPT_ADDRESS="$(
    cardano-cli address build \
        --payment-script-file "$TREASURY_SCRIPT_FILE" \
        --stake-script-file "$TREASURY_SCRIPT_FILE" \
        "${NETWORK_FLAG[@]}"
)"
VENDOR_SCRIPT_ADDRESS="$(
    cardano-cli address build \
        --payment-script-file "$VENDOR_SCRIPT_FILE" \
        --stake-script-file "$VENDOR_SCRIPT_FILE" \
        "${NETWORK_FLAG[@]}"
)"

cardano-cli address info --address "$TREASURY_SCRIPT_ADDRESS" >/dev/null
cardano-cli address info --address "$VENDOR_SCRIPT_ADDRESS" >/dev/null
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

read -r SCHEDULE_USDCX_TOTAL SCHEDULE_ADA_TOTAL < <(
    jq -r '
      [([.[].usdcx_base] | add), ([.[].ada_lovelace] | add)] | @tsv
    ' "$SCHEDULE_FILE"
)

if (( SCHEDULE_USDCX_TOTAL != USDCX_TOTAL_BASE )); then
    echo "Error: milestone USDCx total ${SCHEDULE_USDCX_TOTAL} != expected ${USDCX_TOTAL_BASE}." >&2
    exit 1
fi
if (( SCHEDULE_ADA_TOTAL != ADA_TOTAL_LOVELACE )); then
    echo "Error: milestone ADA total ${SCHEDULE_ADA_TOTAL} != expected ${ADA_TOTAL_LOVELACE}." >&2
    exit 1
fi

jq -n \
    --arg policy "$USDCX_POLICY_ID" \
    --arg asset "$USDCX_ASSET_NAME" \
    --argjson ada "$ADA_TOTAL_LOVELACE" \
    --argjson usdcx "$USDCX_TOTAL_BASE" '
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
  {
    constructor: 2,
    fields: [
      value_map($ada; $policy; $asset; $usdcx)
    ]
  }
' > "$REDEEMER_FILE"

jq \
    --arg vendor "$BLINK_LABS_KEYHASH" \
    --arg policy "$USDCX_POLICY_ID" \
    --arg asset "$USDCX_ASSET_NAME" '
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
  {
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
' "$SCHEDULE_FILE" > "$VENDOR_DATUM_FILE"

if [[ ! -s "$METADATA_JSON_FILE" ]]; then
    jq -n \
        --slurpfile schedule "$SCHEDULE_FILE" \
        --arg context "https://raw.githubusercontent.com/SundaeSwap-finance/treasury-contracts/refs/heads/main/offchain/src/metadata/context.jsonld" \
        --arg instance "$INSTANCE_ID" \
        --arg txAuthor "$TX_AUTHOR_HASH" \
        --arg vendorKeyHash "$BLINK_LABS_KEYHASH" \
        --arg usdcxPolicy "$USDCX_POLICY_ID" \
        --arg usdcxAsset "$USDCX_ASSET_NAME" \
        --arg blinkHotWallet "addr1q8g9808jhwhqjp3ylqgdpzzuur4u53n5zv4ahadskq6djd3lwzwsdphplcdpzla0vnksx0vd2xk70ykyfl3fmuwxr4vqv7tkrw" \
        --arg adaWallet "addr1qyzc5k4sceny0hxwsttjgnuqhl4yrwnkclyuetux5sdsplh9r9z8yaghysf05atjyv79t73lercjdqnejetxm307m49qsugwpk" '
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
              "event": "fund",
              "label": "Blink Labs milestone funding",
              "description": "Fund one mixed ADA/USDCx vendor UTxO for Blink Labs treasury milestones.",
              "vendor": {
                "keyHash": $vendorKeyHash,
                "usdcxDestination": $blinkHotWallet,
                "adaDestination": $adaWallet
              },
              "asset": {
                "ticker": "USDCx",
                "policyId": $usdcxPolicy,
                "assetName": $usdcxAsset
              },
              "totals": {
                "usdcxBaseUnits": 1528333333336,
                "adaLovelace": 370000000000
              },
              "milestones": $schedule[0]
            },
            "comment": "M-10 Audit is funded as matured but Paused; the board can resume it after the auditor is engaged."
          }
        } | chunk_long_strings
    ' > "$METADATA_JSON_FILE"
fi
jq empty "$METADATA_JSON_FILE" || {
    echo "Error: metadata JSON is invalid: ${METADATA_JSON_FILE}" >&2
    exit 1
}

if [[ -z "${INVALID_HEREAFTER:-}" ]]; then
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
    INVALID_HEREAFTER=$((CURRENT_SLOT + VALIDITY_TTL_SLOTS))
fi

SELECTED_TREASURY_TX_INS=()
SELECTED_TREASURY_LOVELACE=0
SELECTED_TREASURY_USDCX=0

if [[ -n "${TREASURY_TX_INS:-}${TREASURY_TX_IN:-}" ]]; then
    explicit_treasury="${TREASURY_TX_INS:-${TREASURY_TX_IN:-}}"
    while IFS= read -r txin; do
        SELECTED_TREASURY_TX_INS+=("$txin")
    done < <(split_words "$explicit_treasury")

    if [[ ${#SELECTED_TREASURY_TX_INS[@]} -eq 0 ]]; then
        echo "Error: TREASURY_TX_INS was provided but no tx-ins were parsed." >&2
        exit 1
    fi

    TREASURY_QUERY_FLAGS=()
    for txin in "${SELECTED_TREASURY_TX_INS[@]}"; do
        TREASURY_QUERY_FLAGS+=(--tx-in "$txin")
    done
    query_utxo_json "${TREASURY_QUERY_FLAGS[@]}" > "$TREASURY_SELECTED_JSON"
else
    TREASURY_ALL_JSON="${OUT_DIR}/treasury-all-utxos.json"
    query_utxo_json --address "$TREASURY_SCRIPT_ADDRESS" > "$TREASURY_ALL_JSON"

    mapfile -t USDCX_ROWS < <(
        jq -r --arg policy "$USDCX_POLICY_ID" --arg asset "$USDCX_ASSET_NAME" '
          [to_entries[]
            | {
                txin: .key,
                lovelace: (.value.value.lovelace // 0),
                usdcx: (.value.value[$policy][$asset] // 0)
              }
            | select(.usdcx > 0)]
          | sort_by(-.usdcx, -.lovelace)
          | .[]
          | [.txin, .lovelace, .usdcx] | @tsv
        ' "$TREASURY_ALL_JSON"
    )

    for row in "${USDCX_ROWS[@]}"; do
        if (( SELECTED_TREASURY_USDCX >= USDCX_TOTAL_BASE )); then
            break
        fi
        IFS=$'\t' read -r txin lovelace usdcx <<<"$row"
        add_selected_treasury_txin "$txin" "$lovelace" "$usdcx"
    done

    mapfile -t ADA_ROWS < <(
        jq -r --arg policy "$USDCX_POLICY_ID" --arg asset "$USDCX_ASSET_NAME" '
          [to_entries[]
            | {
                txin: .key,
                lovelace: (.value.value.lovelace // 0),
                usdcx: (.value.value[$policy][$asset] // 0)
              }
            | select(.lovelace > 0)]
          | sort_by(-.lovelace, -.usdcx)
          | .[]
          | [.txin, .lovelace, .usdcx] | @tsv
        ' "$TREASURY_ALL_JSON"
    )

    for row in "${ADA_ROWS[@]}"; do
        if (( SELECTED_TREASURY_LOVELACE >= ADA_TOTAL_LOVELACE )); then
            break
        fi
        IFS=$'\t' read -r txin lovelace usdcx <<<"$row"
        add_selected_treasury_txin "$txin" "$lovelace" "$usdcx"
    done

    if (( SELECTED_TREASURY_USDCX < USDCX_TOTAL_BASE )); then
        echo "Error: treasury UTxOs only cover ${SELECTED_TREASURY_USDCX} USDCx base units; need ${USDCX_TOTAL_BASE}." >&2
        echo "Set TREASURY_TX_INS='txid#ix ...' to choose inputs explicitly." >&2
        exit 1
    fi
    if (( SELECTED_TREASURY_LOVELACE < ADA_TOTAL_LOVELACE )); then
        echo "Error: treasury UTxOs only cover ${SELECTED_TREASURY_LOVELACE} lovelace; need ${ADA_TOTAL_LOVELACE}." >&2
        echo "Set TREASURY_TX_INS='txid#ix ...' to choose inputs explicitly." >&2
        exit 1
    fi

    SELECTED_TXINS_JSON="$(
        printf '%s\n' "${SELECTED_TREASURY_TX_INS[@]}" | jq -R . | jq -s .
    )"
    jq --argjson txins "$SELECTED_TXINS_JSON" '
      with_entries(select(.key as $k | $txins | index($k)))
    ' "$TREASURY_ALL_JSON" > "$TREASURY_SELECTED_JSON"
fi

read -r TREASURY_INPUT_LOVELACE TREASURY_INPUT_USDCX < <(
    jq -r --arg policy "$USDCX_POLICY_ID" --arg asset "$USDCX_ASSET_NAME" '
      [
        ([to_entries[] | (.value.value.lovelace // 0)] | add // 0),
        ([to_entries[] | (.value.value[$policy][$asset] // 0)] | add // 0)
      ] | @tsv
    ' "$TREASURY_SELECTED_JSON"
)

if (( TREASURY_INPUT_USDCX < USDCX_TOTAL_BASE )); then
    echo "Error: selected treasury inputs contain ${TREASURY_INPUT_USDCX} USDCx base units; need ${USDCX_TOTAL_BASE}." >&2
    exit 1
fi
if (( TREASURY_INPUT_LOVELACE < ADA_TOTAL_LOVELACE )); then
    echo "Error: selected treasury inputs contain ${TREASURY_INPUT_LOVELACE} lovelace; need ${ADA_TOTAL_LOVELACE}." >&2
    exit 1
fi

TREASURY_REMAINDER_LOVELACE=$((TREASURY_INPUT_LOVELACE - ADA_TOTAL_LOVELACE))
TREASURY_REMAINDER_ASSETS="$(
    jq -r \
      --arg policy "$USDCX_POLICY_ID" \
      --arg asset "$USDCX_ASSET_NAME" \
      --argjson usdcx "$USDCX_TOTAL_BASE" '
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
    ' "$TREASURY_SELECTED_JSON"
)"
TREASURY_REMAINDER_VALUE="${TREASURY_REMAINDER_LOVELACE}${TREASURY_REMAINDER_ASSETS:+ + ${TREASURY_REMAINDER_ASSETS}}"
VENDOR_VALUE="${ADA_TOTAL_LOVELACE} + ${USDCX_TOTAL_BASE} ${USDCX_POLICY_ID}.${USDCX_ASSET_NAME}"

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

TREASURY_SPEND_FLAGS=()
for txin in "${SELECTED_TREASURY_TX_INS[@]}"; do
    TREASURY_SPEND_FLAGS+=(
        --tx-in "$txin"
        --spending-tx-in-reference "$TREASURY_SCRIPT_REF"
        --spending-plutus-script-v3
    )
    DATUM_MODE="$(
        jq -r --arg txin "$txin" '
          .[$txin] as $u
          | if (($u.inlineDatum? // $u.inlineDatumRaw? // null) != null) then "inline"
            elif (($u.datumHash? // $u.datumhash? // null) != null) then "hash"
            else "none"
            end
        ' "$TREASURY_SELECTED_JSON"
    )"
    case "$DATUM_MODE" in
        inline)
            TREASURY_SPEND_FLAGS+=(--spending-reference-tx-in-inline-datum-present)
            ;;
        hash)
            echo "Error: selected treasury input ${txin} has a datum hash, not an inline datum." >&2
            echo "Choose another input or extend this script with a datum file for that input." >&2
            exit 1
            ;;
        none)
            ;;
        *)
            echo "Error: could not determine datum mode for treasury input ${txin}." >&2
            exit 1
            ;;
    esac
    TREASURY_SPEND_FLAGS+=(--spending-reference-tx-in-redeemer-file "$REDEEMER_FILE")
done

REQUIRED_SIGNER_HASHES=()
add_unique "$BLINK_LABS_KEYHASH" REQUIRED_SIGNER_HASHES
add_unique "$LUCAS_HASH" REQUIRED_SIGNER_HASHES
add_unique "$SANTIAGO_HASH" REQUIRED_SIGNER_HASHES
add_unique "$TX_AUTHOR_HASH" REQUIRED_SIGNER_HASHES
if [[ -n "${EXTRA_REQUIRED_SIGNER_HASHES:-}" ]]; then
    while IFS= read -r signer_hash; do
        require_key_hash "EXTRA_REQUIRED_SIGNER_HASHES" "$signer_hash"
        add_unique "$signer_hash" REQUIRED_SIGNER_HASHES
    done < <(split_words "$EXTRA_REQUIRED_SIGNER_HASHES")
fi

WITNESS_COUNT="${WITNESS_COUNT:-$((${#REQUIRED_SIGNER_HASHES[@]} + 1))}"
REQUIRED_SIGNER_FLAGS=()
for signer_hash in "${REQUIRED_SIGNER_HASHES[@]}"; do
    REQUIRED_SIGNER_FLAGS+=(--required-signer-hash "$signer_hash")
done

TX_OUTPUT_FLAGS=(
    --tx-out "${VENDOR_SCRIPT_ADDRESS}+${VENDOR_VALUE}"
    --tx-out-inline-datum-file "$VENDOR_DATUM_FILE"
)
if (( TREASURY_REMAINDER_LOVELACE > 0 )) || [[ -n "$TREASURY_REMAINDER_ASSETS" ]]; then
    TX_OUTPUT_FLAGS+=(
        --tx-out "${TREASURY_SCRIPT_ADDRESS}+${TREASURY_REMAINDER_VALUE}"
        --tx-out-inline-datum-value '{}'
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

echo "Network:              ${NETWORK_FLAG[*]}"
echo "Output dir:           ${OUT_DIR}"
echo "Treasury address:     ${TREASURY_SCRIPT_ADDRESS}"
echo "Vendor address:       ${VENDOR_SCRIPT_ADDRESS}"
echo "Treasury inputs:      ${SELECTED_TREASURY_TX_INS[*]}"
echo "Treasury input ADA:   ${TREASURY_INPUT_LOVELACE}"
echo "Treasury input USDCx: ${TREASURY_INPUT_USDCX}"
echo "Vendor output:        ${VENDOR_VALUE}"
echo "Treasury remainder:   ${TREASURY_REMAINDER_VALUE}"
echo "Fee input:            ${FEE_TX_IN}"
echo "Collateral input:     ${COLLATERAL_TX_IN}"
echo "Required signers:     ${REQUIRED_SIGNER_HASHES[*]}"
echo "Witness override:     ${WITNESS_COUNT}"
echo "Invalid hereafter:    ${INVALID_HEREAFTER}"
echo "Metadata:             ${METADATA_JSON_FILE}"
echo

cardano-cli conway transaction build \
    "${NETWORK_FLAG[@]}" \
    --socket-path "$CARDANO_NODE_SOCKET_PATH" \
    --witness-override "$WITNESS_COUNT" \
    "${TREASURY_SPEND_FLAGS[@]}" \
    --tx-in "$FEE_TX_IN" \
    --tx-in-collateral "$COLLATERAL_TX_IN" \
    --read-only-tx-in-reference "$REGISTRY_TX_IN" \
    "${REQUIRED_SIGNER_FLAGS[@]}" \
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

printf 'tx_id\ttx_body\twitness\tassembled_tx\trequired_signers\n' > "$MANIFEST_FILE"
printf '%s\t%s\t%s\t%s\t%s\n' \
    "$TX_ID" \
    "$TX_BODY_FILE" \
    "$WITNESS_OUTPUT" \
    "$PARTIAL_SIGNED_OUTPUT" \
    "${REQUIRED_SIGNER_HASHES[*]}" >> "$MANIFEST_FILE"

echo "Built milestone funding tx: ${TX_ID}"
echo "Tx body: ${TX_BODY_FILE}"
if [[ -n "$WITNESS_OUTPUT" ]]; then
    echo "Witness: ${WITNESS_OUTPUT}"
    echo "Partial signed tx: ${PARTIAL_SIGNED_OUTPUT}"
fi
echo "Manifest: ${MANIFEST_FILE}"
