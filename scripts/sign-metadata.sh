#!/usr/bin/env bash
set -euo pipefail

# sign-metadata.sh - Sign CIP-100 metadata with an ed25519 key.
# Signs the blake2b-256 hash of the body field and updates the metadata JSON
# with the public key and signature in the authors witness.
#
# Usage: scripts/sign-metadata.sh [metadata-file] [signing-key-file]
#   metadata-file     Path to the metadata JSON (default: metadata/proposal-metadata.json)
#   signing-key-file  Path to a Cardano .skey file (default: keys/payment.skey)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Source configuration ─────────────────────────────────────────────────────

if [[ -f "${REPO_ROOT}/config.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/config.env"
    set +a
fi

METADATA_FILE="${1:-${REPO_ROOT}/metadata/proposal-metadata.json}"
SKEY_FILE="${2:-${REPO_ROOT}/keys/payment.skey}"

echo "=== Sign Metadata ==="
echo ""

# ── Validate inputs ──────────────────────────────────────────────────────────

if [[ ! -f "$METADATA_FILE" ]]; then
    echo "Error: Metadata file not found: ${METADATA_FILE}" >&2
    exit 1
fi

if [[ ! -f "$SKEY_FILE" ]]; then
    echo "Error: Signing key file not found: ${SKEY_FILE}" >&2
    echo "Provide a Cardano .skey file as the second argument." >&2
    exit 1
fi

# ── Check prerequisites ──────────────────────────────────────────────────────

for tool in jq openssl b2sum xxd; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: Required tool '${tool}' not found." >&2
        exit 1
    fi
done

# ── Extract body as compact JSON ─────────────────────────────────────────────

echo "Extracting body from metadata..."
BODY_JSON=$(jq -c '.body' "$METADATA_FILE")

if [[ -z "$BODY_JSON" || "$BODY_JSON" == "null" ]]; then
    echo "Error: No body field found in metadata." >&2
    exit 1
fi

# ── Hash body with blake2b-256 ───────────────────────────────────────────────

echo "Computing blake2b-256 hash of body..."
BODY_HASH=$(echo -n "$BODY_JSON" | b2sum -l 256 | cut -d' ' -f1)
echo "Body hash: ${BODY_HASH}"

# ── Extract keys from Cardano key files ──────────────────────────────────────

echo "Reading signing key..."

# Extract raw key bytes from Cardano skey (strip CBOR prefix)
SKEY_CBOR_HEX=$(jq -r '.cborHex' "$SKEY_FILE")

# Handle both 5820 (32-byte) and 5840 (64-byte) CBOR prefixes
if [[ "$SKEY_CBOR_HEX" == 5820* ]]; then
    SKEY_HEX="${SKEY_CBOR_HEX:4}"
elif [[ "$SKEY_CBOR_HEX" == 5840* ]]; then
    SKEY_HEX="${SKEY_CBOR_HEX:4:64}"  # Take first 32 bytes (seed)
else
    echo "Error: Unexpected CBOR encoding in skey file." >&2
    exit 1
fi

# Derive the corresponding vkey file path
VKEY_FILE="${SKEY_FILE%.skey}.vkey"
if [[ ! -f "$VKEY_FILE" ]]; then
    echo "Error: Corresponding vkey file not found: ${VKEY_FILE}" >&2
    exit 1
fi

VKEY_CBOR_HEX=$(jq -r '.cborHex' "$VKEY_FILE")
if [[ "$VKEY_CBOR_HEX" == 5820* ]]; then
    PUBKEY_HEX="${VKEY_CBOR_HEX:4}"
else
    echo "Error: Unexpected CBOR encoding in vkey file." >&2
    exit 1
fi

echo "Public key: ${PUBKEY_HEX}"

# ── Convert private key to PEM for openssl ───────────────────────────────────

# Ed25519 private key DER encoding:
# SEQUENCE { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING { OCTET STRING { key } } }
DER_PREFIX="302e020100300506032b657004220420"

TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

echo "${DER_PREFIX}${SKEY_HEX}" | xxd -r -p > "${TMPDIR}/skey.der"
openssl pkey -inform DER -outform PEM -in "${TMPDIR}/skey.der" -out "${TMPDIR}/skey.pem" 2>/dev/null

# ── Sign the body hash ───────────────────────────────────────────────────────

echo "Signing body hash with ed25519..."
echo -n "$BODY_HASH" | xxd -r -p > "${TMPDIR}/hash.bin"

SIGNATURE_HEX=$(openssl pkeyutl -sign -inkey "${TMPDIR}/skey.pem" -rawin \
    -in "${TMPDIR}/hash.bin" | xxd -p | tr -d '\n')

echo "Signature:  ${SIGNATURE_HEX}"

# ── Update metadata JSON ────────────────────────────────────────────────────

echo ""
echo "Updating metadata with signature..."

jq \
    --arg pubkey "$PUBKEY_HEX" \
    --arg sig "$SIGNATURE_HEX" \
    '.authors[0].witness.publicKey = $pubkey | .authors[0].witness.signature = $sig' \
    "$METADATA_FILE" > "${TMPDIR}/updated.json"

mv "${TMPDIR}/updated.json" "$METADATA_FILE"

echo ""
echo "Metadata signed successfully."
echo "File:       ${METADATA_FILE}"
echo "Public key: ${PUBKEY_HEX}"
echo "Signature:  ${SIGNATURE_HEX}"
echo ""
echo "IMPORTANT: Run 'make hash' to update the anchor-data-hash after signing."
