#!/usr/bin/env bash
set -euo pipefail

# generate-metadata.sh - Assemble CIP-108 proposal metadata JSON.
# Reads docs/proposal.md if available; otherwise uses existing metadata or
# creates a template with placeholder fields.
#
# Usage: scripts/generate-metadata.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROPOSAL_MD="${REPO_ROOT}/docs/proposal.md"
METADATA_JSON="${REPO_ROOT}/metadata/proposal-metadata.json"

echo "=== Generate Proposal Metadata ==="
echo ""

# ── Case 1: proposal.md exists - assemble metadata from it ─────────────────

if [[ -f "$PROPOSAL_MD" ]]; then
    echo "Found docs/proposal.md - assembling CIP-108 metadata..."

    # Extract sections from proposal.md.
    # Expected structure: # Title, ## Abstract, ## Motivation, ## Rationale
    TITLE=$(head -1 "$PROPOSAL_MD" | sed 's/^#\+ *//')

    extract_section() {
        local file="$1" heading="$2"
        # Extract text between the given ## heading and the next ## heading (or EOF)
        sed -n "/^## ${heading}/,/^## /{ /^## ${heading}/d; /^## /d; p; }" "$file" \
            | sed '/^$/{ N; /^\n$/d; }' \
            | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }

    ABSTRACT=$(extract_section "$PROPOSAL_MD" "Abstract")
    MOTIVATION=$(extract_section "$PROPOSAL_MD" "Motivation")
    RATIONALE=$(extract_section "$PROPOSAL_MD" "Rationale")

    # Fall back to placeholder if section is empty
    : "${ABSTRACT:=TODO: Write abstract}"
    : "${MOTIVATION:=TODO: Write motivation}"
    : "${RATIONALE:=TODO: Write rationale}"

    jq -n \
        --arg title "$TITLE" \
        --arg abstract "$ABSTRACT" \
        --arg motivation "$MOTIVATION" \
        --arg rationale "$RATIONALE" \
        '{
            "@context": {
                "@language": "en-us",
                "CIP100": "https://github.com/cardano-foundation/CIPs/blob/master/CIP-0100/README.md#",
                "CIP108": "https://github.com/cardano-foundation/CIPs/blob/master/CIP-0108/README.md#",
                "hashAlgorithm": "CIP100:hashAlgorithm",
                "body": {
                    "@id": "CIP108:body",
                    "@context": {
                        "references": "CIP108:references",
                        "title": "CIP108:title",
                        "abstract": "CIP108:abstract",
                        "motivation": "CIP108:motivation",
                        "rationale": "CIP108:rationale"
                    }
                }
            },
            "hashAlgorithm": "blake2b-256",
            "body": {
                "title": $title,
                "abstract": $abstract,
                "motivation": $motivation,
                "rationale": $rationale,
                "references": []
            }
        }' > "$METADATA_JSON"

    echo "Metadata assembled from docs/proposal.md"
    echo "Output: ${METADATA_JSON}"
    exit 0
fi

# ── Case 2: proposal.md missing, metadata already exists ───────────────────

echo "Warning: docs/proposal.md not found." >&2

if [[ -f "$METADATA_JSON" ]]; then
    echo "Using existing metadata: ${METADATA_JSON}"
    echo ""
    echo "To regenerate, create docs/proposal.md and re-run this script."
    exit 0
fi

# ── Case 3: Neither exists - create a template ────────────────────────────

echo "Creating CIP-108 template with placeholder fields..."

mkdir -p "$(dirname "$METADATA_JSON")"

cat > "$METADATA_JSON" <<'TEMPLATE'
{
  "@context": {
    "@language": "en-us",
    "CIP100": "https://github.com/cardano-foundation/CIPs/blob/master/CIP-0100/README.md#",
    "CIP108": "https://github.com/cardano-foundation/CIPs/blob/master/CIP-0108/README.md#",
    "hashAlgorithm": "CIP100:hashAlgorithm",
    "body": {
      "@id": "CIP108:body",
      "@context": {
        "references": "CIP108:references",
        "title": "CIP108:title",
        "abstract": "CIP108:abstract",
        "motivation": "CIP108:motivation",
        "rationale": "CIP108:rationale"
      }
    }
  },
  "hashAlgorithm": "blake2b-256",
  "body": {
    "title": "TODO: Proposal title",
    "abstract": "TODO: Proposal abstract",
    "motivation": "TODO: Proposal motivation",
    "rationale": "TODO: Proposal rationale",
    "references": []
  }
}
TEMPLATE

echo "Template created: ${METADATA_JSON}"
echo ""
echo "Next steps:"
echo "  1. Edit ${METADATA_JSON} directly, or"
echo "  2. Create docs/proposal.md and re-run this script."
