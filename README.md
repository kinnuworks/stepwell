# Stepwell

First-loss cover for USDC in Morpho vaults on Arc.

When a vault loses money, underwriters take the loss before depositors do. Depositors pay for that with a slice of their interest, never out of pocket. Any wallet or app can add it, because a covered deposit is a standard ERC-4626 vault.

Live site: `[link after deploy]` · For reviewers: `/reviewers`

## Why it exists

Arc's request for builders asks for exactly this: "Bundle smart-contract, vault-loss, or collateral-risk protection directly into USDC deposit and lending flows, with premiums netted from yield and standardized coverage metadata available across vaults."

Morpho vaults on Arc held about 170 million dollars on 11 October 2026 (Morpho API). Earn Kit lists them and says it does not curate, recommend or rank them. When one of them books bad debt, every depositor's share price falls by the same amount. We found nothing on Arc that pays a depositor back.

## How it works

1. A Stepwell sits on one ERC-4626 vault. Everything deposited goes into that vault and earns the same interest.
2. Underwriters put up cover and hold cover shares. Depositors hold covered shares.
3. A covered deposit is a request first. For one day it earns and loses like a plain vault deposit. After that, anyone can settle it into covered shares. This stops people buying cover just before bad debt they can already see.
4. When the vault earns, depositors pass part of their interest to the cover layer: 35% when cover is 10% of the well or less, 15% at 20% or more, sliding in between.
5. When the vault loses, deposits still warming up take their own share, the cover layer takes the rest until it is gone, and only then does it reach covered deposits.
6. When money comes back after a loss, it repays covered depositors first, then the cover layer, before anyone earns again.
7. Underwriters give three days' notice to leave. From that day their shares stop earning but still carry losses, and they have one day to claim.
8. Covered deposits leave any time, in USDC, or in vault shares if the vault is short of cash. Underwriters can claim in vault shares too.
9. New requests are refused if cover would drop below 15%.
10. If a loss wipes the cover out, the old cover shares are voided and a fresh layer starts owing nothing.

| 850 covered, 150 cover, a quarter of interest passed up | Covered depositors | Underwriters |
|---|---|---|
| The vault earns 6% | 888.25 (+4.5%) | 171.75 (+14.5%) |
| The vault loses 8% | 850.00 (no change) | 70.00 (−53.3%) |
| ...and then gets the 8% back | 850.00 | 150.00 (made whole first) |
| The vault loses 22% | 780.00 (−8.2%) | 0.00 |

At Steakhouse Prime USDC's rate when this was written (3.12%), with 15% cover, covered depositors keep about 2.4% and underwriters earn about 7%.

## What it uses Arc for

- Morpho vaults on Arc mainnet, the ones Earn Kit lists.
- USDC as both the money and the gas.
- `Multicall3From` (`0x522f…47D0`): approving USDC and requesting a covered deposit are one signature from an ordinary wallet. Tested on a fork of Arc mainnet.
- Arc's Memo contract (`0x5294…e505`): apps can tag each deposit with their own reference.
- Sub-second final settlement: the rehearsal shows the settled state of a loss within a second of pressing the button.

## For apps

Covered shares are ERC-4626 on the way out (withdraw, redeem, previews). Deposits go through `requestDeposit`, then `settle` after the warm-up, modelled on ERC-7540's request-then-claim flow; the synchronous `deposit` and `mint` report zero room and revert. `StepwellFactory.standardCoverageFor(vault)` returns, for any vault address, the Stepwells on standard terms and their figures: cover, covered deposits, deposits warming up, cover under notice, premium, losses absorbed and what cover is still owed. Anyone can open a Stepwell on any vault with `StepwellFactory.create`; the factory checks the creation code against a fixed hash.

## For apps, concretely

- `sdk/stepwell.ts`: `coverageFor(client, factory, vault)`, which counts only Stepwells on standard terms unless you ask for all; `coveredDepositCalls(...)`, which returns the approve-and-request calls for one signature through Multicall3From, with your app's reference attached through Memo; and `settleCall(...)` for the day after. Depends only on viem.
- `/embed?ref=your-app`: a cover card any app can put next to a vault in an iframe.
- `/vaults`: every Morpho vault on Arc, its deposits, rate and instant cash, and whether it has cover. Anyone can open a Stepwell on a vault that has none.

## Contracts

| Contract | Arc mainnet |
|---|---|
| StepwellFactory | `[after deploy]` |
| Stepwell on Steakhouse Prime USDC | `[after deploy]` |
| Rehearsal Stepwell | `[after deploy]` |
| RehearsalVault (holds only our own USDC) | `[after deploy]` |

No owner, no admin key, no upgrade path.

## Tests

```bash
cd contracts
arc-forge test                                              # 33 tests
FORK=1 arc-forge test --match-contract Fork --isolate -vv   # 3 tests against Arc mainnet state
halmos --contract WaterfallProofs                           # 4 proofs for every input
```

- 27 unit, fuzz and regression tests, including one for each attack an earlier review found.
- 5 stateful invariants, each 128 random campaigns of 64 calls with no test-side booking, against a separately written model of the rules. The model caught a real bug in an earlier version (a memory struct aliased inside the waterfall), now fixed.
- A reachability test that walks 6,000 random steps and fails unless it reaches: cover wiped out, cover pierced, a loss absorbed, recovery refilling cover, a notice claimed, a deposit settled, a request cancelled, an exit in kind, a request refused at the floor and the cover layer restarting.
- Fork tests on Arc mainnet state: request, settle and redeem against Steakhouse Prime USDC; a 2% bad-debt markdown in its real Morpho adapter, booked entirely by cover; and the one-signature deposit through Multicall3From and Memo.
- Four properties of the waterfall proved for every input with Halmos: a loss within the cover never touches covered deposits; the buckets always add up to what the vault holds; interest never makes any bucket poorer; a loss followed by the same amount coming back restores both layers exactly.

`THREATS.md` lists every threat and the test or proof that covers it.

## Limits

- Unaudited. Amounts are small on purpose.
- Cover covers a slice, not a total loss.
- The large USDC vaults on Arc pay about 3% a year, so premiums are small in dollars right now.
- Vault fees that ever exceed interest show up as a loss, and cover takes it.

## Run the site

```bash
cd app && npm install && npm run dev
```

Environment: `NEXT_PUBLIC_FACTORY`, `NEXT_PUBLIC_REAL`, `NEXT_PUBLIC_DRILL`, `NEXT_PUBLIC_REHEARSAL_VAULT`, `NEXT_PUBLIC_SITE_URL`, `SEED_DEPOSITOR`, and `OPERATOR_KEY` for the rehearsal relayer (a hot key holding about 1 USDC for gas).
