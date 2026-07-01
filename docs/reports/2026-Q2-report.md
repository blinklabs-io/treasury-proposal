# Progress Report - Q2 2026

Period: April 1, 2026 - June 30, 2026
Report type: Quarterly

## Summary

Q2 was the quarter the Dingo treasury funding went live and the quarter's
engineering milestone - testnet block production and the Leios prototype - was
brought to completion.

The funding lifecycle ran end to end in May: the governance action was
enacted, the 6,900,000 ADA withdrawal landed in the treasury contract, the
working budget was converted to USDCx to hedge ADA price volatility over the
12-month period, the vendor milestone schedule was configured and funded, and
the first milestone (M-0 Bootstrap) was claimed. Every step is recorded in the
transparency journal with on-chain metadata.

Engineering delivered across all three quarters of the calendar year's runway
this period. April laid the block-production groundwork - consensus
correctness, era transitions, Ouroboros Genesis bootstrap, rollback and fork
recovery. May hardened the producer paths (forging, opcert tracking, chain
selection, VRF) and began serving Leios Endorser Block data. June turned the
Leios prototype into a working node - forging Endorser Blocks in the Praos slot
leader, stake-truncated committee voting, and vote diffusion - and made an
early start on Dijkstra. Throughout, the team deepened Conway ledger accounting,
overhauled Mithril bootstrap, and expanded the Blockfrost-compatible API.

Source basis: April-June 2026 main-branch history in the local Dingo,
gOuroboros, and Plutigo repositories, plus the transaction journal in
`journal/`. Per-month detail is in the monthly reports for April, May, and
June; the figures below are the sum of those three reports.

| Project | Q2 main-branch activity | Release range / output |
|---------|--------------------------|-------------------------|
| Dingo | 585 commits, 474 non-dependency | v0.29.1 through v0.61.0 |
| gOuroboros | 143 commits, 109 non-dependency | v0.163.5 through v0.186.1 |
| Plutigo | 90 commits, 71 non-dependency | v0.1.1 through v0.1.16 |

## Treasury Operations

All treasury movement this quarter occurred in May; April and June had no
treasury transactions. The sequence, each entry recorded in `journal/` with its
transaction hash, signers, and metadata hash:

- **May 12** - 6,900,000 ADA moved from the treasury contract reward account
  into the treasury script UTxO.
- **May 13** - 5,630,001 ADA disbursed to Kraken for an OTC trade, co-signed by
  oversight board member Pi Lanningham with a written attestation. Executed at
  0.2720 USDC per ADA for 1,531,360.27 USDC.
- **May 14** - USDC bridged back to Cardano as USDCx: a 100 USDC test transfer
  first to verify the bridge address, then 1,531,307.86 USDCx in full.
- **May 18** - the oversight board ran the fund action, configuring Blink Labs
  as vendor with the full milestone schedule (370,000 ADA and 1,528,333.33
  USDCx). Roughly 900,001 ADA and 2,975 USDCx remain in the treasury contract
  as contingency. M-10 Audit was funded as matured but Paused.
- **May 19** - Blink Labs claimed the matured M-0 Bootstrap milestone, 225,000
  USDCx, to the operating wallet.

As of the end of Q2, three further milestones have matured and are eligible to
be claimed but had not been claimed within the reporting period: M-1 (Infra
May, matured May 31), M-2 (Q2 Testnet, matured June 30), and M-3 (Infra June,
matured June 30). M-10 Audit remains funded-but-Paused pending auditor
engagement.

## Financial Summary

Funds were converted from ADA to USDCx in May to hedge ADA price volatility over
the 12-month budget period, so escrow balances are denominated in USDCx (with
per-milestone ADA where the schedule allocates it). The OTC conversion basis was
0.2720 USDC per ADA. The full 6,900,000 ADA withdrawal is accounted for below:
the vendor UTxO holds the milestone schedule and the treasury contract retains
the contingency. Only M-0 Bootstrap has been claimed to date.

| Category | Allocated | Claimed (Q2) | Remaining |
|----------|-----------|--------------|-----------|
| Engineering (milestones M-0, M-2, M-6, M-11, M-13) | 995,000 USDCx + 370,000 ADA | 225,000 USDCx (M-0) | 770,000 USDCx + 370,000 ADA |
| Security Audit (M-10, Paused) | 500,000 USDCx | 0 | 500,000 USDCx |
| Infrastructure (8 monthly milestones) | 33,333.33 USDCx | 0 | 33,333.33 USDCx |
| Contingency (retained in treasury contract) | 900,001.18 ADA + 2,974.53 USDCx | 0 | 900,001.18 ADA + 2,974.53 USDCx |
| **Total** | **1,531,307.86 USDCx + 1,270,001.18 ADA** | **225,000 USDCx** | **1,306,307.86 USDCx + 1,270,001.18 ADA** |

The 370,000 ADA held in the vendor schedule vests alongside the quarterly
engineering milestones; the 900,001 ADA contingency never left the treasury
contract and sweeps back to the Cardano treasury if unused. All balances derive
from the documented on-chain amounts in the journal entries.

### Treasury Journal Reference

All individual transactions are recorded in [`journal/`](../../journal/).

## Treasury Milestone

The Q2 engineering milestone was testnet block production and the Leios
prototype, and it matured at the end of June. Both halves reached completion
this quarter.

On block production, Dingo moved from consensus and era-transition correctness
(April) through producer hardening - credential validation, per-pool opcert
tracking, cardano-node-matched Praos chain selection, VRF fixes (May) - to
selection and forging that hold up under real network conditions: same-tip peer
pinning, configurable multi-active header sync, optional forged-block validation
before diffusion, checkpoint-based validation, and near-tip/epoch-clock stall
fixes (June). Era-transition correctness was proven end to end from Shelley
through Conway.

On Leios, the prototype advanced from serving merged Ranking Block and Endorser
Block data over N2C (May) to a node that forges Endorser Blocks inside the Praos
slot leader, votes with a stake-truncated committee and quorum, and diffuses
votes over a dedicated mini-protocol (June), coordinated against a named Leios
testnet (musashi) tracking the IOG prototype spec. gOuroboros supplied the
CIP-CDDL Endorser Block type, the Leios/Dijkstra block header, the LeiosVotes
mini-protocol, and the certificate scheme, and refactored Leios out of the era
model. The quarter also closed with an early start on the next milestone -
initial Dijkstra support across Dingo and gOuroboros (block headers, redeemers,
protocol-parameter serialization, at-tip nonce handling).

## Per-Project Summary

Detailed per-month breakdowns are in the April, May, and June monthly reports.

- **Dingo** (`v0.29.1` → `v0.61.0`): block-production and consensus hardening,
  Ouroboros Genesis bootstrap, the Leios prototype (forging, committee voting,
  vote diffusion, musashi testnet), initial Dijkstra support, deep Conway ledger
  accounting (rewards, MIR, pool-deposit refunds, governance enactment cleanup),
  a Mithril v2 overhaul with a public sync API, storage/backfill performance, and
  continued Blockfrost API alignment.
- **gOuroboros** (`v0.163.5` → `v0.186.1`): protocol and ledger support feeding
  Dingo - Leios (Endorser Block type, LeiosVotes, certificates, header) and
  initial Dijkstra, Conway governance constructors and query helpers, DMQ
  (CIP-0137) work, peer-sharing and LocalStateQuery additions, CBOR diagnostics,
  and hardened ledger validation.
- **Plutigo** (`v0.1.1` → `v0.1.16`): a sustained evaluator performance push
  (stack-machine rewrite, DeBruijn specialization, builtin/ed25519 caching,
  arena allocation, single-pass JSON decoding), decoder and parser hardening,
  and security-review findings addressed.

## Risks and Issues

The known risks from the proposal remain the baseline: storage scalability at
mainnet scale, Leios specification instability, and technical execution
unknowns. Two quarter-specific notes:

- **Leios specification tracking** - the prototype is developed against an
  evolving spec (synced to the `2026w25` prototype and the musashi testnet this
  quarter). This is mitigated as planned by direct collaboration with the IOG
  research team, but the moving target continues to drive rework.
- **Security audit not yet started** - the M-10 Audit milestone is funded but
  Paused pending engagement of an auditor. Engaging the audit firm is a priority
  for the second half so the audit can run against a stabilizing codebase.
