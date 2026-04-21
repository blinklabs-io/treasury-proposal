# Blink Labs Treasury Proposal: Dingo Development

Cardano Treasury Withdrawal governance action proposal to fund [Dingo](https://github.com/blinklabs-io/dingo) development.

## Overview

This repository contains everything needed to create, test, and submit a Cardano Treasury Withdrawal governance action for Blink Labs to fund 12 months of Dingo node development, including Dijkstra hard fork readiness, Leios protocol implementation, and mainnet production readiness.

## Prerequisites

- `cardano-cli` (Conway-era, v8.x+)
- `cardano-node` (preview testnet and mainnet access)
- `jq` >= 1.5
- `basenc` (GNU coreutils) >= 9.1
- `make`

## Quick Start

```bash
make help              # Show all available targets
make check-prereqs     # Verify tools are installed
make metadata          # Generate CIP-108 metadata
make hash              # Hash metadata with blake2b-256
make submit-testnet    # Full testnet submission workflow
make test-lifecycle    # Automated testnet lifecycle test
```

Every workflow in this repo is driven by a `make` target. Run `make help` for the full list. Network selection is via `NETWORK=preview|preprod|mainnet` (default: `preview`).

## Repository Structure

```
metadata/          CIP-108 proposal metadata JSON (self-contained)
docs/              Proposal narrative, budget, milestones
docs/reports/      Progress report templates
scripts/           Makefile-driven automation scripts
journal/           On-chain transaction transparency journal
contracts/         SundaeSwap treasury contract configuration
```

## Proposal

The full proposal narrative is in [docs/proposal.md](docs/proposal.md). The CIP-108 metadata JSON at [metadata/proposal-metadata.json](metadata/proposal-metadata.json) contains the complete proposal in the format required for on-chain submission.

## Smart Contracts

Uses audited [SundaeSwap treasury-contracts](https://github.com/SundaeSwap-finance/treasury-contracts) (treasury.ak + vendor.ak) with an independent oversight board for fund management. See [contracts/README.md](contracts/README.md) for the permission scheme.

## Testnet Workflow

```bash
# 1. Configure
cp config.env.example config.env
# Edit config.env with your keys and addresses

# 2. Test on preview
make test-lifecycle

# 3. Or step by step
make metadata
make hash
make governance-action NETWORK=preview
make build-tx NETWORK=preview
make sign-tx NETWORK=preview
make submit-testnet
```

## Mainnet Submission

```bash
make metadata
make upload-ipfs              # Pin metadata to IPFS for immutability
make governance-action NETWORK=mainnet
make build-tx NETWORK=mainnet
make sign-tx NETWORK=mainnet
make submit-mainnet           # Prompts for confirmation
```

Requires a 100,000 ADA governance action deposit (refunded on ratification or rejection).

## Reporting

Monthly lightweight updates and quarterly detailed reports are generated from `docs/reports/TEMPLATE.md`:

```bash
make report              # Monthly report -> docs/reports/YYYY-MM-report.md
make report-quarterly    # Quarterly report with financials -> docs/reports/YYYY-QN-report.md
```

Monthly reports omit the Financial Summary section; quarterly reports include it. If `$EDITOR` is set, the generated report opens for editing.

## Transparency Journal

Every on-chain transaction against the treasury and vendor contracts is recorded in [`journal/`](journal/):

```bash
make journal-entry       # Interactive prompt for tx hash, action, amount, signers, justification
```

See [journal/README.md](journal/README.md) for the entry format and required fields. Entries follow the [SundaeSwap metadata standard](https://github.com/SundaeSwap-finance/treasury-contracts) so anyone can verify them against on-chain data.

## License

Apache 2.0
