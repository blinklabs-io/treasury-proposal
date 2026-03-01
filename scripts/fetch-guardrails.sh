#!/usr/bin/env bash
set -euo pipefail

# fetch-guardrails.sh - Fetch the on-chain guardrails (constitution) script.
# Queries the constitution for the script hash, then attempts to download
# the script from known sources. Works on any network.
#
# Usage: NETWORK=preview scripts/fetch-guardrails.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# ── Source configuration ─────────────────────────────────────────────────────

if [[ -f "${REPO_ROOT}/config.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/config.env"
    set +a
fi

# ── Network flags ────────────────────────────────────────────────────────────

case "${NETWORK:-preview}" in
    mainnet) QUERY_FLAG=(--mainnet) ;;
    preprod) QUERY_FLAG=(--testnet-magic 1) ;;
    *)       QUERY_FLAG=(--testnet-magic 2) ;;
esac

echo "=== Fetch Guardrails Script ==="
echo ""
echo "Network: ${NETWORK:-preview}"
echo ""

# ── Query constitution ───────────────────────────────────────────────────────

echo "Querying on-chain constitution..."

CONSTITUTION_JSON=$(cardano-cli conway query constitution "${QUERY_FLAG[@]}" --out-file /dev/stdout)
SCRIPT_HASH=$(echo "$CONSTITUTION_JSON" | jq -r '.script // empty')

if [[ -z "$SCRIPT_HASH" ]]; then
    echo "No guardrails script on this network. None needed for governance actions."
    exit 0
fi

echo "Script hash: ${SCRIPT_HASH}"

ANCHOR_URL=$(echo "$CONSTITUTION_JSON" | jq -r '.anchor.url // empty')
echo "Constitution anchor: ${ANCHOR_URL}"

OUTPUT_FILE="${SCRIPTS_DIR}/guardrails.plutus"

# ── Check if we already have it ──────────────────────────────────────────────

if [[ -f "$OUTPUT_FILE" ]]; then
    EXISTING_HASH=$(cardano-cli hash script --script-file "$OUTPUT_FILE" 2>/dev/null || echo "")
    if [[ "$EXISTING_HASH" == "$SCRIPT_HASH" ]]; then
        echo ""
        echo "Guardrails script already present and hash matches."
        echo "File: ${OUTPUT_FILE}"
        exit 0
    else
        echo "Existing script hash mismatch (${EXISTING_HASH}), re-fetching..."
    fi
fi

# ── Try known sources ────────────────────────────────────────────────────────

fetch_and_verify() {
    local url="$1" tmpfile
    tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" RETURN

    echo "  Trying: ${url}"
    if ! curl -sL --fail --max-time 30 "$url" -o "$tmpfile" 2>/dev/null; then
        return 1
    fi

    # Verify it's valid JSON with a script type
    if ! jq -e '.type' "$tmpfile" >/dev/null 2>&1; then
        return 1
    fi

    local dl_hash
    dl_hash=$(cardano-cli hash script --script-file "$tmpfile" 2>/dev/null || echo "")
    if [[ "$dl_hash" == "$SCRIPT_HASH" ]]; then
        cp "$tmpfile" "$OUTPUT_FILE"
        return 0
    fi

    echo "    Hash mismatch: got ${dl_hash}"
    return 1
}

echo ""
echo "Searching for guardrails script..."

# Source 1: IntersectMBO repos (known locations for compiled scripts)
KNOWN_URLS=(
    "https://raw.githubusercontent.com/IntersectMBO/interim-constitution/main/guardrails-script.plutus"
    "https://raw.githubusercontent.com/IntersectMBO/governance-actions/main/guardrails-script/guardrails.plutus"
)

for url in "${KNOWN_URLS[@]}"; do
    if fetch_and_verify "$url"; then
        echo ""
        echo "Guardrails script downloaded and verified."
        echo "File: ${OUTPUT_FILE}"
        echo "Hash: ${SCRIPT_HASH}"
        exit 0
    fi
done

# Source 2: If the constitution anchor URL points to a JSON document,
# check if it references the script
if [[ -n "$ANCHOR_URL" ]]; then
    echo ""
    echo "Checking constitution anchor document..."

    ANCHOR_CONTENT=$(curl -sL --fail --max-time 30 "$ANCHOR_URL" 2>/dev/null || echo "")
    if [[ -n "$ANCHOR_CONTENT" ]]; then
        # Look for script URLs in the constitution document
        SCRIPT_URLS=$(echo "$ANCHOR_CONTENT" | jq -r '
            .. | strings | select(test("guardrail|plutus|script.*\\.plutus"; "i"))
        ' 2>/dev/null || echo "")

        for url in $SCRIPT_URLS; do
            if [[ "$url" =~ ^https?:// ]] && fetch_and_verify "$url"; then
                echo ""
                echo "Guardrails script downloaded and verified."
                echo "File: ${OUTPUT_FILE}"
                echo "Hash: ${SCRIPT_HASH}"
                exit 0
            fi
        done
    fi
fi

# ── Not found ────────────────────────────────────────────────────────────────

echo ""
echo "Error: Could not find guardrails script matching hash ${SCRIPT_HASH}" >&2
echo "" >&2
echo "To resolve manually:" >&2
echo "  1. Find the guardrails Plutus script for your network" >&2
echo "  2. Verify: cardano-cli hash script --script-file <file>" >&2
echo "  3. Copy to: ${OUTPUT_FILE}" >&2
echo "" >&2
echo "Common sources:" >&2
echo "  - https://github.com/IntersectMBO/governance-actions" >&2
echo "  - Your network's governance documentation" >&2
exit 1
