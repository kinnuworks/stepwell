# Stepwell

First-loss cover for USDC in Morpho vaults on Arc.

When a vault loses money, underwriters take the loss before depositors do. Depositors pay for that with a slice of their interest, never out of pocket. Any wallet or app can add it, because a covered deposit is a standard ERC-4626 vault.

Live site: `[link after deploy]` · For reviewers: `/reviewers`

## Why it exists

Arc's request for builders asks for exactly this: "Bundle smart-contract, vault-loss, or collateral-risk protection directly into USDC deposit and lending flows, with premiums netted from yield and standardized coverage metadata available across vaults."

Morpho vaults on Arc held about 170 million dollars on 11 October 2026 (Morpho API). Earn Kit lists them and says it does not curate, recommend or rank them. When one of them books bad debt, every depositor's share price falls by the same amount. We found nothing on Arc that pays a depositor back.

## How it works

1. A Stepwell sits on one ERC-4626 vault. Everything deposited goes into that vault and earns the same interest.
2. Depositors hold covered shares. Underwriters hold cover shares.
3. When the vault earns, depositors pass part of their interest to the cover layer: 35% when cover is 10% of the well or less, 15% at 20% or more, sliding in between.
4. When the vault loses, the loss comes out of the cover layer until it is gone. Only then does it reach depositors.
5. Underwriters need three days' notice to leave and still carry losses while they wait. Depositors leave any time, in USDC or in vault shares.
6. New covered deposits are refused if cover would drop below 15%.
7. If a loss wipes the cover out, the old cover shares are voided and a fresh layer can start.

| 850 deposited, 150 cover, a quarter of interest passed up | Depositors | Underwriters |
|---|---|---|
| The vault earns 6% | 888.25 (+4.5%) | 171.75 (+14.5%) |
| The vault loses 8% | 850.00 (no change) | 70.00 (−53.3%) |
| The vault loses 22% | 780.00 (−8.2%) | 0.00 |

## What it uses Arc for

- Morpho vaults on Arc mainnet, the ones Earn Kit lists.
- USDC as both the money and the gas.
- `Multicall3From` (`0x522f…47D0`): approving USDC and making a covered deposit are one signature from an ordinary wallet.
- Arc's Memo contract (`0x5294…e505`): apps can tag each deposit with their own reference.
- Sub-second final settlement: the rehearsal shows the settled state of a loss within a second of pressing the button.

## For apps

The covered share is an ERC-4626 vault, so code that already deposits into a Morpho vault can deposit into a Stepwell unchanged. `StepwellFactory.coverageFor(vault)` returns, for any vault address, how much cover it has, what it costs, and how much loss it has already absorbed. Anyone can open a Stepwell on any vault with `StepwellFactory.create`.

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
arc-forge test                                   # 24 tests; the fork test only runs with FORK=1
FORK=1 arc-forge test --match-contract Fork -vv  # against the real vault on Arc mainnet state
```

- 17 unit and fuzz tests.
- 5 stateful invariants, each run as 128 random campaigns of 64 calls, against an independent model of the waterfall.
- A reachability test that walks 4,000 random steps and fails unless it saw: cover wiped out, cover pierced, a loss absorbed, a notice claimed, an exit in kind, a deposit refused at the floor and the cover layer restarting.
- A fork test that deposits into Steakhouse Prime USDC on Arc mainnet state and withdraws again.

See `THREATS.md` for every threat and the test that covers it. Tests use Circle's Arc Foundry build (`arc-forge`).

## Limits

- Unaudited. Amounts are small on purpose.
- Cover covers a slice, not a total loss.
- The large USDC vaults on Arc pay about 2.5% a year, so premiums are small in dollars right now.

## Run the site

```bash
cd app && npm install && npm run dev
```

Environment: `NEXT_PUBLIC_FACTORY`, `NEXT_PUBLIC_REAL`, `NEXT_PUBLIC_DRILL`, `NEXT_PUBLIC_REHEARSAL_VAULT`, and `OPERATOR_KEY` for the rehearsal relayer (a hot key holding about 1 USDC for gas).
