# Threat model

Each threat names the test that covers it. Tests live in `contracts/test/`.

| Threat | What stops it | Test |
|---|---|---|
| An underwriter sees a loss coming and leaves before it is booked | Leaving needs three days' notice, and losses during the notice still land on the leaver | `test_underwriterNeedsNotice`, `invariant_noEarlyExit` |
| An underwriter hands cover shares to someone else to dodge the notice | Cover shares cannot be transferred or approved | `test_coverSharesCannotMove` |
| A loss wipes out the cover and old shares dilute the next underwriters | The cover token moves to a new epoch and old balances read as zero | `test_lossBeyondCoverWipesLayerAndReachesDepositors`, `test_noticeVoidedByWipe` |
| A covered deposit dilutes cover below what was promised | Deposits are refused above the cover floor, and `maxDeposit` says how much room is left | `test_floorLimitsDeposits`, `test_noCoverMeansNoCoveredDeposits` |
| Rounding in the vault moves value from existing holders to a newcomer | Shares are priced on what actually reached the vault, so the depositor carries their own rounding | `testFuzz_depositExitNeverProfits`, `invariant_coveredPriceHoldsWhileCovered` |
| A donation inflates the share price to steal from the next depositor | Virtual shares (offset of 10^6) in every conversion | `test_inflationAttackDoesNotPay` |
| The waterfall arithmetic is wrong in some sequence nobody thought of | An independent model runs beside the contract through random sequences and must agree to the unit; the rule itself is proved for every input | `invariant_matchesReferenceModel`, `test_everyEndStateIsReached`, `check_lossWithinCoverSparesDepositors`, `check_bigLossEmptiesCoverFirst`, `check_booksBalance`, `check_gainNeverHurts` |
| The books claim more than the vault shares are worth | Losses are booked before every action; in-kind exits resync | `invariant_booksNeverExceedHoldings`, `invariant_sharesBackedByAssets` |
| The vault is short of cash and depositors are trapped | Depositors can leave with the vault's own shares | `test_exitInKind` |
| A blocklisted address makes a shared payout revert for everyone | Every payout is pulled by its owner; nothing pays a list in a loop | by design, no batch payouts |
| An admin changes the rules | There is no owner, no pause and no upgrade path; parameters are fixed at creation | by construction |
| The history disappears when RPC nodes drop old receipts | The last 64 entries are kept in contract storage | `test_historyKeptOnChain` |

Known limits that are not bugs:

- Cover only covers a slice. A loss larger than the cover layer reaches depositors.
- The contract trusts the underlying vault's `previewRedeem`. A malicious vault could report a fake loss, which would hurt the underwriters who chose to cover that vault. Each Stepwell covers exactly one vault, so that risk stays with the people who opted into it.
- Unaudited.
