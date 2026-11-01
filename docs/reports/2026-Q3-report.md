# Progress Report - Q3 2026

Period: July 1, 2026 - September 30, 2026
Report type: Quarterly

## Summary

Q3 focused on making Dingo more reliable under sustained use: storage and
mempool work, ledger correctness, recovery, and testing across database backends.
The Leios prototype continued to track Musashi, while Dijkstra and Plutus V4
work carried forward into the next quarter's scope.

July introduced a DAG mempool and lock-free ledger snapshots, expanded reward
and governance processing, and kept Leios aligned with four successive Musashi
prototype revisions. August added real SQLite, PostgreSQL, and MySQL conformance
runs and hardened block production, database lifecycle handling, and Leios
fetch and recovery paths. September improved SQL hot paths, added database and
ledger-pipeline metrics, and introduced a Koios-backed from-genesis parity run.
Throughout the quarter, gOuroboros supplied protocol and ledger fixes, Plutigo
advanced V4 support, and ouroboros-mock expanded the fixtures used to test Dingo.

During Q3, treasury activity was limited to the July 1 claim of three
milestones that matured in Q2. After quarter-end, the Dingo GitHub milestone
"Operational Hardening and Storage Scalability" was closed on October 16 with
119 of 119 issues closed. Across Blink Labs repositories, all 156 issues
assigned to milestones with this title are closed. The Q3 Storage payout and
the three matured infrastructure payouts were claimed that day. The September
report's target-volume performance gap remains relevant: it records no
validation at roughly 100 million UTxOs and a 500 GB chain, so that validation
continues into Q4.

Source basis: the July, August, and September monthly reports, drawing on local
main-branch history in Dingo, gOuroboros, Plutigo, and ouroboros-mock, plus the
transaction journal in `journal/`. Dingo and gOuroboros commit totals below are
the sums of the three monthly reports and include dependency updates.

| Project | Q3 main-branch activity | Release range / output |
|---------|-------------------------|------------------------|
| Dingo | 1,218 commits | v0.61.1 through v0.75.0 |
| gOuroboros | 391 commits | v0.186.2 through v0.208.5 |
| Plutigo | V4 evaluator and script-context support | v0.1.17 through v0.8.0 |
| ouroboros-mock | All-era fixtures and conformance corpus updates | v0.15.0 through v0.20.4 |

## Milestones

| Milestone | Target | Status | Notes |
|-----------|--------|--------|-------|
| Q2 2026: Testnet block production and Leios prototype | End of Q2 2026 | Complete | The block-production and Leios-prototype milestone matured at the end of June; M-2 was claimed July 1. |
| Q3 2026: Operational hardening and storage scalability | End of Q3 2026 | Complete (closed 2026-10-16) | Dingo GitHub milestone closed with 119/119 issues complete; M-6 and the three matured infrastructure payouts were claimed October 16. Target-volume validation continues into Q4. |
| Q4 2026: Dijkstra readiness and Leios integration | End of Q4 2026 | Planned | Dijkstra readiness, Plutigo V4, and Leios consensus integration carry into Q4 alongside continued scale and reliability validation. |
| Q1 2027: Mainnet readiness, audit completion, and ecosystem integration | End of Q1 2027 | Target | Mainnet readiness, audit completion, and ecosystem integration remain the final-quarter targets. |

## Treasury Operations

On July 1, Blink Labs claimed M-1 Infra May, M-2 Q2 Testnet, and M-3 Infra June
in transaction [`d423bf42...9486f00`](../../journal/2026-07-01-milestone-claim.md).
The claim released 233,333.333334 USDCx and 92,500 ADA: 4,166.666667 USDCx
for each infrastructure milestone, and 225,000 USDCx plus 92,500 ADA for
M-2. USDCx went to the Blink Labs hot wallet and ADA to Chris Gianelloni's
personal wallet, as recorded in the journal.

The vendor remainder was 1,070,000.000002 USDCx and 277,500 ADA. No further
treasury transactions are recorded during Q3.

As of the end of Q3, four further milestones have matured but have no recorded
claim: M-4 (Infra July, July 31), M-5 (Infra August, August 31), M-6 (Q3
Storage, September 30), and M-7 (Infra September, September 30). Together they
allocate 237,500.000001 USDCx and 92,500 ADA. M-10 Audit remains
funded-but-Paused on-chain.

On October 16, Blink Labs claimed M-4 through M-7 in transaction
[`8c36ed0c...29f010e3d`](../../journal/2026-10-16-milestone-claim.md). The
claim released 237,500.000001 USDCx and 92,500 ADA. The vendor contract then
held 832,500.000001 USDCx and 185,000 ADA. Dingo's security audit firm
engagement issue (#1904) was also closed that day; M-10 remains paused on-chain
pending the board's resume action.

## Financial Summary

Funds were converted from ADA to USDCx in May to hedge ADA price volatility over
the 12-month budget period. The OTC conversion basis was 0.2720 USDC per ADA.
The funded allocation did not change this quarter. The table shows Q3 claims
and the remaining balances after both the Q2 Bootstrap claim and the July 1
claim.

| Category | Allocated | Claimed (Q3) | Remaining |
|----------|-----------|--------------|-----------|
| Engineering (milestones M-0, M-2, M-6, M-11, M-13) | 995,000 USDCx + 370,000 ADA | 225,000 USDCx + 92,500 ADA (M-2) | 545,000 USDCx + 277,500 ADA |
| Security Audit (M-10, Paused) | 500,000 USDCx | 0 | 500,000 USDCx |
| Infrastructure (8 monthly milestones) | 33,333.33 USDCx | 8,333.33 USDCx (M-1, M-3) | 25,000 USDCx |
| Contingency (retained in treasury contract) | 900,001.18 ADA + 2,974.53 USDCx | 0 | 900,001.18 ADA + 2,974.53 USDCx |
| Total | 1,531,307.86 USDCx + 1,270,001.18 ADA | 233,333.33 USDCx + 92,500 ADA | 1,072,974.53 USDCx + 1,177,501.18 ADA |

Cumulative claims through September 30 total 458,333.333334 USDCx and 92,500
ADA. After the October 16 claim, cumulative claims total 695,833.333335 USDCx
and 185,000 ADA. The vendor balance after that claim was 832,500.000001 USDCx
and 185,000 ADA; the treasury contract's contingency remains separate. All
balances derive from the documented on-chain amounts in the journal entries;
table values are rounded to two decimal places where needed, as in Q2.

### Treasury Journal Reference

All individual transactions are recorded in [`journal/`](../../journal/).

## Treasury Milestone

The Q3 engineering milestone was operational hardening and storage scalability,
with mainnet-scale testing, long-running stability, cross-node validation, and
security audit kickoff. The Dingo GitHub milestone closed on October 16 after
all 119 assigned Dingo issues were closed. Its tracked closeout includes the
72-hour soak-testing issue (#1899), Haskell-node cross-node validation issue
(#1900), and security audit firm engagement issue (#1904). The quarterly
evidence below describes the state at September 30; target-volume validation
continues into Q4.

On storage, July added lock-free ledger snapshots, configurable FIFO and DAG
mempools, connection-pool limits, and stake and reward indexes. August expanded
conformance execution across SQLite, PostgreSQL, and MySQL, bounded Badger
snapshots and garbage-collection waits, and improved shutdown and database
lifecycle handling. September optimized SQLite and SQL-store paths and added
query, connection-pool, and ledger-stage metrics. These changes support scale
validation, but the monthly reports do not yet establish performance at the
proposal's target of roughly 100 million UTxOs and a 500 GB chain.

On reliability, Dingo strengthened KES and operational-certificate checks,
Genesis selection, rollback and fork recovery, Mithril bootstrap, and block
publication. Leios gained persistent Endorser Block tracking, voter-key and
stake-snapshot checks, bounded caches, and safer fetch and certificate-serving
behavior. The new Koios-backed parity run and expanded conformance fixtures
provide more ways to check ledger behavior. Long-running stability and the
planned block-by-block comparison against the Haskell node remain work to
complete.

Q4 carries that validation forward alongside Dijkstra readiness, Plutigo V4,
Leios consensus integration, and remaining Node-to-Client and LocalStateQuery
work. The audit-firm engagement issue closed on October 16. M-10 remains
paused on-chain until the oversight board resumes that payout.

## Per-Project Summary

Detailed per-month breakdowns are in the [July](2026-07-report.md),
[August](2026-08-report.md), and [September](2026-09-report.md) monthly reports.

- Dingo (`v0.61.1` → `v0.75.0`): storage and mempool improvements, database
  conformance coverage, reward and governance correctness, Leios persistence
  and recovery, Dijkstra committee and block validation, Mithril and producer
  hardening, expanded Blockfrost API coverage, parity tooling, and a KES agent
  client.
- gOuroboros (`v0.186.2` → `v0.208.5`): Leios wire-format and fetch updates,
  Dijkstra ledger fields and validation, Byron and Genesis consensus work,
  governance and reward rules, CBOR hardening, BlockFetch improvements, and
  CIP-0137 message authentication.
- Plutigo (`v0.1.17` → `v0.8.0`): V4 builtins, cost parameters, script-context
  builders and Value encoding, mainnet script replay tooling, evaluator and
  program validation fixes, and a native Keccak-256 implementation.
- ouroboros-mock (`v0.15.0` → `v0.20.4`): DRep delegation, an observable
  ChainSync harness, all-era block and protocol fixtures, governance
  observability, Leios mock conversations, and Blueprint corpus validation.

## Upcoming Work

- Continue mainnet-scale storage and long-running stability validation,
  including cross-node ledger comparisons and target-volume benchmarks.
- Advance Dijkstra readiness, Plutigo V4, Leios consensus integration, and
  remaining Node-to-Client and LocalStateQuery work.
- Coordinate with the oversight board on resuming the paused M-10 audit payout.

## Risks and Issues

The known risks from the proposal remain the baseline: storage scalability at
mainnet scale, Leios specification instability, and technical execution
unknowns. Two quarter-specific notes:

- Mainnet-scale validation remains open. Backend conformance and storage
  optimizations progressed, but the September report did not establish
  target-volume benchmarks at roughly 100 million UTxOs and a 500 GB chain.
- The audit-firm engagement issue closed on October 16, but M-10 remains
  funded and Paused on-chain pending board action. The audit and remediation
  schedule remains compressed against the Q1 mainnet-readiness target.
