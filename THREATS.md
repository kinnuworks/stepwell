# Threat model

Each threat names the test or proof that covers it. Tests live in `contracts/test/`. The first five came from an outside-style review of an earlier version, which confirmed each with an exploit test; the fixes and their regression tests are below.

| Threat | What stops it | Test |
|---|---|---|
| Someone sees bad debt coming and makes a covered deposit just before it is booked, getting cover for free | New deposits wait one day in a warm-up bucket that earns and loses like a plain vault deposit before they are covered (a request-then-settle queue modelled on ERC-7540) | `test_jitDepositGetsNoCover` |
| An underwriter keeps a matured notice open as a free exit option and leaves just before a loss | From the day notice is given, the noticed shares stop earning: the payout is capped at their value on that day, and they still carry losses. The claim window is one day | `test_noticedSharesStopEarning`, `invariant_noticeIsHonoured` |
| A loss that later reverses is locked in, moving value from cover to depositors | A high-water mark: money coming back repays depositors' past losses, then the cover's, before any new interest is split | `test_recoveryRefillsCoverFirst`, `check_recoveryRestoresExactly` |
| An underwriter sees a loss coming and leaves before it is booked | Three days' notice, losses during the notice still land on the leaver | `test_underwriterNeedsNotice` |
| Cover shares are handed to someone else to dodge the notice | Cover shares cannot be transferred or approved | `test_coverSharesCannotMove` |
| A loss wipes out the cover and old shares dilute the next underwriters | The cover token moves to a new epoch and old balances read as zero; the old layer's deficit is not inherited | `test_lossBeyondCoverWipesLayerAndReachesDepositors`, `test_noticeVoidedByWipe` |
| A covered deposit dilutes cover below what was promised | Requests are refused above the cover floor | `test_floorLimitsRequests`, `test_noCoverMeansNoRequests` |
| Rounding moves value from existing holders to a newcomer | Deposits are credited with what the new vault shares are worth, so the depositor carries their own rounding | `testFuzz_requestSettleExitNeverProfits`, `invariant_coveredPriceHoldsWhileCovered` |
| A donation inflates the share price to steal from the next depositor | Virtual shares (offset 10^6) in every conversion | `test_inflationAttackDoesNotPay` |
| The arithmetic is wrong in a sequence nobody thought of | A separately written model of the rules runs beside the contract through random sequences and must agree to the unit. It caught a real bug (a memory struct aliased in `Waterfall.split`), now fixed | `invariant_matchesModel`, `test_everyEndStateIsReached` |
| The rule itself is wrong for some input | Four properties of the waterfall proved with Halmos for every amount up to 2^64 units | `check_lossWithinCoverSparesDepositors`, `check_booksBalance`, `check_gainNeverHurts`, `check_recoveryRestoresExactly` |
| The vault is short of cash and people are trapped | Depositors and underwriters can both leave with the vault's own shares | `test_maxWithdrawRespectsVaultLiquidity`, `test_exitInKind`, `test_claimCoverInKind` |
| Integrators call `withdraw(maxWithdraw())` and it reverts | `maxWithdraw` and `maxRedeem` take the vault's reported liquidity into account | `test_maxWithdrawRespectsVaultLiquidity` |
| Someone tops up another person's deposit request with dust every day, so its one-day warm-up never ends and it is never covered | Only the depositor can add to their own request (`controller == owner == msg.sender`) | `test_cannotResetAnotherDepositorsWarmup` |
| An underwriter cancels or renews a notice to get back the interest the noticed shares were meant to forfeit, keeping a standing exit option for free | Cancelling or renewing a notice burns the cover shares that hold what the noticed shares earned since notice day; that value stays with the other underwriters | `test_cancelledNoticeForfeitsItsGain`, `test_renewedNoticeForfeitsItsGain` |
| Someone registers a Stepwell with useless terms and wallets show it as cover | The factory marks standard-terms Stepwells; `standardCoverageFor` returns only those, and the site reads only those | `test_registryOnlyVouchesForStandardTerms` |
| Someone registers an impostor contract through the factory | The factory refuses creation code whose hash differs from the one fixed at deployment | by construction |
| Losses in the real Morpho vault are not detected | Fork test on Arc mainnet state: the real Steakhouse Prime USDC adapter reports a 2% markdown, Vault V2 lowers its share price, and cover alone takes it | `test_fork_morphoBadDebtIsBookedAsLoss` |
| The one-signature path through Multicall3From and Memo credits the wrong account | Fork test: the wallet itself ends up holding the request | `test_fork_oneSignatureDepositThroughMemo` |
| The rehearsal operator key is stolen | The rehearsal vault is capped at 25 USDC of the team's own money, can lose at most 10% per call and at most once a minute | by construction |
| A blocklisted address makes a shared payout revert for everyone | Every payout is pulled by its owner; nothing pays a list in a loop | by design |
| An admin changes the rules | No owner, no pause, no upgrade path; parameters fixed at creation | by construction |
| The history disappears when RPC nodes drop old receipts | The last 64 entries are kept in contract storage | `test_historyKeptOnChain` |

Arc and Morpho details that shaped the code:

- Morpho Vault V2 reports `maxDeposit` and `maxWithdraw` as 0 by design, so Stepwell reads 0 as "unknown" and lets the vault's own deposit or withdraw decide.
- Morpho Vault V2 books interest and losses once per transaction and caches its totals, so deposits are credited from the shares minted, not from holdings before and after. Fork tests run with `--isolate` for the same reason.
- USDC on Arc is native, with 18 decimals natively and 6 through its ERC-20 interface; Stepwell only uses the ERC-20 interface.

Known limits that are not bugs:

- Cover covers a slice. A loss bigger than the cover layer reaches depositors.
- A vault's management fee, if it ever exceeds interest, lowers the share price and is taken by cover like any loss.
- Cover can leave. The floor only blocks new requests; the coverage figures show cover under notice.
- The contract trusts the vault's `previewRedeem`. A malicious vault could fake a loss, which would hurt the underwriters who chose to cover that vault.
- Unaudited.

## Found after the mainnet deploy

A blind review on 15 October 2026, after the contracts went live, found the two issues in the warm-up and notice rows above (the dust top-up and the notice renewal). Both are fixed in this repo with regression tests. **The contracts on Arc mainnet run the earlier code, tagged `v1.0-mainnet`, and still have both issues.** Neither can take anyone's money: the first can delay another person's cover, and the second lets an underwriter keep interest the rules say they give up. The fixed version goes to mainnet in the next deploy, alongside a migration of the seed amounts.
