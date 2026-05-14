#!/usr/bin/env bash
set -euo pipefail

# Create the Kraken USDC bridge Crate2 address, then poll until deployment
# completes. This script does not submit Cardano transactions.

usage() {
    cat <<'EOF'
Usage:
  scripts/deploy-kraken-usdc-bridge.sh [cardano-address]

Optional environment:
  CARDANO_ADDRESS          address for the create request; default is the treasury script address
  REQUEST_FILE             generated JSON request path; default is OUT_DIR/kraken-usdc-bridge-request.json
  STATUS_ADDRESS           Cardano address used in /crate2/status/{address}; default is CARDANO_ADDRESS
  CRATE2_BASE_URL          API base URL
  POLL_INTERVAL_SECONDS    seconds between polls; default 10
  MAX_POLLS                maximum status polls; default 0 means forever
  OUT_DIR                  response output directory; default is a /tmp directory
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 1
fi

command -v curl >/dev/null 2>&1 || {
    echo "Error: curl not found in PATH." >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || {
    echo "Error: jq not found in PATH." >&2
    exit 1
}

CRATE2_BASE_URL="${CRATE2_BASE_URL:-https://production-docker.usdcx.aws.iohkdev.io}"
CARDANO_ADDRESS="${CARDANO_ADDRESS:-${1:-addr1x90c5a0h3qwkxquehkdg746ccaa3hdfzgp7ckx6wzdpp7lzl3f6l0zqavvpen0v63at433mmrw6jysra3vd5uy6zra7qgffay3}}"
STATUS_ADDRESS="${STATUS_ADDRESS:-$CARDANO_ADDRESS}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-10}"
MAX_POLLS="${MAX_POLLS:-0}"
OUT_DIR="${OUT_DIR:-$(mktemp -d -t crate2-kraken-usdc-bridge.XXXXXX)}"
REQUEST_FILE="${REQUEST_FILE:-${OUT_DIR}/kraken-usdc-bridge-request.json}"

if [[ -z "$CARDANO_ADDRESS" ]]; then
    echo "Error: cardano address must not be empty." >&2
    exit 1
fi
if [[ ! "$POLL_INTERVAL_SECONDS" =~ ^[0-9]+$ || "$POLL_INTERVAL_SECONDS" -eq 0 ]]; then
    echo "Error: POLL_INTERVAL_SECONDS must be a positive integer." >&2
    exit 1
fi
if [[ ! "$MAX_POLLS" =~ ^[0-9]+$ ]]; then
    echo "Error: MAX_POLLS must be a non-negative integer." >&2
    exit 1
fi
mkdir -p "$OUT_DIR"
mkdir -p "$(dirname "$REQUEST_FILE")"

jq -n --arg cardanoAddress "$CARDANO_ADDRESS" \
    '{"cardanoAddress": $cardanoAddress}' > "$REQUEST_FILE"
jq empty "$REQUEST_FILE" || {
    echo "Error: generated request is not valid JSON: ${REQUEST_FILE}" >&2
    exit 1
}

ADDRESS_URL="${CRATE2_BASE_URL%/}/crate2/address"
STATUS_URL="${CRATE2_BASE_URL%/}/crate2/status/${STATUS_ADDRESS}"
POST_RESPONSE_FILE="${OUT_DIR}/crate2-address-response.json"
STATUS_RESPONSE_FILE="${OUT_DIR}/crate2-status-response.json"

extract_status() {
    jq -r '[.. | objects | .status? // empty | select(. != "")][0] // empty' "$1"
}

extract_crate2_address() {
    jq -r '[.. | objects | (.crate2Address? // .crate2_address? // empty) | select(. != "")][0] // empty' "$1"
}

echo "Cardano address: ${CARDANO_ADDRESS}"
echo "Request JSON:    ${REQUEST_FILE}"
echo "Address URL:     ${ADDRESS_URL}"
echo "Status URL:      ${STATUS_URL}"
echo "Response dir:    ${OUT_DIR}"
echo

http_code="$(
    curl -sS \
        -w '%{http_code}' \
        -o "$POST_RESPONSE_FILE" \
        -X POST \
        -H 'Content-Type: application/json' \
        --data-binary @"$REQUEST_FILE" \
        "$ADDRESS_URL"
)"

if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    echo "Error: POST ${ADDRESS_URL} returned HTTP ${http_code}." >&2
    echo "Response saved to: ${POST_RESPONSE_FILE}" >&2
    cat "$POST_RESPONSE_FILE" >&2
    exit 1
fi

echo "POST accepted with HTTP ${http_code}."

poll_count=0
while true; do
    poll_count=$((poll_count + 1))
    http_code="$(
        curl -sS \
            -w '%{http_code}' \
            -o "$STATUS_RESPONSE_FILE" \
            "$STATUS_URL"
    )"

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]] && jq empty "$STATUS_RESPONSE_FILE" >/dev/null 2>&1; then
        status_value="$(extract_status "$STATUS_RESPONSE_FILE")"
        if [[ -z "$status_value" ]]; then
            status_value="UNKNOWN"
        fi
        echo "Poll ${poll_count}: status=${status_value}"

        if [[ "${status_value^^}" == "DEPLOYED" ]]; then
            crate2_address="$(extract_crate2_address "$STATUS_RESPONSE_FILE")"
            if [[ -z "$crate2_address" ]]; then
                echo "Error: status is DEPLOYED but crate2Address was not found." >&2
                echo "Response saved to: ${STATUS_RESPONSE_FILE}" >&2
                cat "$STATUS_RESPONSE_FILE" >&2
                exit 1
            fi
            echo
            echo "crate2Address: ${crate2_address}"
            exit 0
        fi
    else
        echo "Poll ${poll_count}: HTTP ${http_code}; response saved to ${STATUS_RESPONSE_FILE}" >&2
    fi

    if [[ "$MAX_POLLS" -gt 0 && "$poll_count" -ge "$MAX_POLLS" ]]; then
        echo "Error: reached MAX_POLLS=${MAX_POLLS} before DEPLOYED." >&2
        exit 124
    fi

    sleep "$POLL_INTERVAL_SECONDS"
done
