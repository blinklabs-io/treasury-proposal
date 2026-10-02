# Treasury Transaction Journal

Public transparency journal tracking all on-chain transactions related to the
Blink Labs treasury proposal. Every movement of funds -- disbursements, milestone
claims, sweeps, and reorganizations -- is recorded here with full provenance so
that any community member can independently verify the history.

Transaction metadata follows the
[SundaeSwap metadata standard](https://github.com/SundaeSwap-finance/treasury-contracts)
used by the treasury and vendor smart contracts.

## Entry Format

Each entry is a dated markdown file:

```
YYYY-MM-DD-description.md
```

For example:

```
2026-04-01-q1-milestone-claim.md
2026-07-15-sweep-early-unclaimed.md
```

## Required Fields

Every journal entry **must** include the following fields:

| Field | Description |
|-------|-------------|
| **Date** | Calendar date the transaction was submitted (YYYY-MM-DD) |
| **Transaction Hash** | 64-character hex transaction ID visible on-chain |
| **Action** | One of: `disbursement`, `milestone-claim`, `sweep-early`, `reorganize`, `fund`, `pause`, `resume`, `modify-project`, `other` |
| **Amount (ADA)** | ADA transferred in this transaction (use `0` for non-financial actions) |
| **Signers** | Names or roles of all parties who signed |
| **Justification** | Human-readable explanation of why this transaction was made |
| **Metadata Hash** | blake2b-256 hash of the on-chain metadata datum, if applicable |

## Verification

Anyone can verify a journal entry by:

1. Looking up the **Transaction Hash** on a Cardano explorer (e.g., CardanoScan, cexplorer)
2. Confirming the on-chain metadata matches the recorded **Metadata Hash**
3. Checking that the **Amount** and **Action** match the on-chain datum

## Site-Generated Milestone Balances

The Pages build derives the vendor schedule from the fund transaction metadata
in `metadata/transactions/` and counts milestone claims from `withdraw`
metadata documents matched to `milestone-claim` journal entries by date. Keep a
transaction metadata JSON file for every milestone claim. If a claim is missing
its journal entry or matching metadata, or a later schedule change, sweep, or
reorganization needs reconciliation, the site omits the derived balance rather
than displaying a stale figure.

## Adding an Entry

Use the helper script:

```bash
make journal-entry
# or directly:
scripts/journal-entry.sh
```

The script will prompt for each required field and generate a properly formatted
entry in this directory.
