# Milestone Contract Operations

This repository keeps custom milestone operations outside the
`contracts/treasury-contracts` submodule.

## Funding

Build one mixed-asset vendor funding transaction:

```bash
NETWORK=mainnet make fund-milestones
```

The funding target uses `cardano-cli`, `jq`, and
`metadata/offchain-metadata.json` for the saved mainnet treasury instance. It
does not use Bun or Blaze. It creates one vendor UTxO containing the full
schedule. Keeping the schedule in one vendor UTxO matters because `vendor.ak`
allows only one vendor input in a withdraw transaction.

Generated files are written under `tmp/<date>-milestone-fund` by default and
are passed to `cardano-cli` as repo-relative paths. This also works when
`cardano-cli` is a container wrapper that cannot see host absolute paths.

Required environment:

```bash
export NETWORK=mainnet
export CARDANO_NODE_SOCKET_PATH=/path/to/node.socket
export PAYMENT_ADDRESS=addr...
export PAYMENT_SKEY=/path/to/payment.skey   # optional; writes your witness
```

If the fee payer key is also the Blink Labs signer key, point both identities
at the same key hash and signing key:

```bash
export PAYMENT_SKEY=/path/to/blink-or-chris.skey
export BLINK_LABS_KEYHASH=058a5ab0c66647dcce82d7244f80bfea41ba76c7c9ccaf86a41b00fe
export TX_AUTHOR_HASH=$BLINK_LABS_KEYHASH
```

All milestone dates are encoded as UTC timestamps.

M-10 Audit is funded with its payout status set to `Paused`. It has the normal
UTC maturation date, but it cannot be claimed until the board resumes that
payout after the auditor is engaged.

Defaults:

- Instance: `d161c89f1123fac8043df44aeec0ca36b2a76e84df47592fe92980ac`
- Vendor signer: `058a5ab0c66647dcce82d7244f80bfea41ba76c7c9ccaf86a41b00fe`
- USDCx asset: `1f3aec8bfe7ea4fe14c5f121e2a92e301afe414147860d557cac7e34.5553444378`

The script auto-selects treasury UTxOs that cover the full schedule. To force
specific inputs:

```bash
TREASURY_TX_INS='txid0#0 txid1#1' make fund-milestones
```

The generated transaction requires the Blink Labs signer plus Lucas and
Santiago. If `PAYMENT_SKEY` is set, the script writes your witness and a
partial signed transaction, but the board witnesses still need to be assembled
before submission.

## Claims

Build a claim transaction for currently matured payouts:

```bash
make claim-milestones
```

The claim script spends one vendor UTxO and sends:

- USDCx to Blink Labs hot wallet:
  `addr1q8g9808jhwhqjp3ylqgdpzzuur4u53n5zv4ahadskq6djd3lwzwsdphplcdpzla0vnksx0vd2xk70ykyfl3fmuwxr4vqv7tkrw`
- ADA to Chris Gianelloni personal wallet:
  `addr1qyzc5k4sceny0hxwsttjgnuqhl4yrwnkclyuetux5sdsplh9r9z8yaghysf05atjyv79t73lercjdqnejetxm307m49qsugwpk`

To claim as of a specific time or force a vendor input:

```bash
CLAIM_AT='2026-06-30T00:05:00Z' VENDOR_TX_IN='txid#0' make claim-milestones
```

Both scripts use the same provider and wallet environment as the Sundae
offchain CLI, for example `BLOCKFROST_KEY` and `WALLET_ADDRESS`.
