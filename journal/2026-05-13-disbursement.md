# Journal Entry: disbursement

| Field | Value |
|-------|-------|
| **Date** | 2026-05-13 |
| **Transaction Hash** | `29722610ea0ebfb6dbb4e43d24a766087dd104629fc1dcf8d72fe24838f6476c` |
| **Action** | disbursement |
| **Amount (ADA)** | 5630000 |
| **Signers** | Chris Gianelloni,Pi Lanningham |
| **Justification** | Send to Kraken for OTC trade |
| **Metadata Hash** | `4b94777ee114927c0f16ebe5480450c867e7bc085b2917c2fa018e0cb394669a` |

## Notes

- Uses treasury reference script `c133b8687c8550a8e7224421e45a7a67bc0941c85b8138f0f9e9498cce8fca08#0`.
- Uses registry reference input `576feff7b2f634ce2320be715f661a23944ed1157844121fbc5515c4feda155e#0`.
- Metadata file: `metadata/transactions/2026-05-13-disbursement.json`.

https://cexplorer.io/tx/29722610ea0ebfb6dbb4e43d24a766087dd104629fc1dcf8d72fe24838f6476c

This disbursement was sent to Kraken for an OTC trade of ADA to USDC. It includes all funds for the Dingo project, minus 900000 ADA contingency
and 370000 ADA which will be used as partial payment to Chris Gianelloni throughout the year.

The Kraken address was taken from the site directly. [image](kraken-otc-deposit.png)

Pi attests that his signature confirms:
- your identity as via voice call as Chris Gianelloni [image](kraken-otc-call-pi-chris.png)
- the transaction is well formed (according to cquisitor) and has not yet expired
- it is from the treasury contract that received cardano treasury funds
- it is withdrawing a pre-communicated amount, and returning the surplus to the treasury
- it is sending the withdrawn amount to an address that was shown to me in what appears to be a kraken OTC deposit address
- that address has no prior activity on chain, but does have an attached stake key with 48m ADA, consistent with a large exchange
- the metadata is well formed and describes the disbursal in accordance with the CIP-100 metadata standard set out for treasury withdrawals
- other inputs on the transaction do not belong to the key I am signing with
- funds from that input are returned, minus fees, to the same wallet
- the collateral input doesn't belong to the key I am signing with, and instead come from the wallet used to sign for fees
- it already has a signature attached from the other key, pre-communicated to me as yours
- it invokes the treasury contract as a spending validator
