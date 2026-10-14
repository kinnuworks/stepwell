import { HeroWell, Rehearsal, Books, DepositPanel, LiveStats, StakeBadge } from "@/components/Live";
import Reveal from "@/components/Reveal";
import { ADDR, REPO_URL, REAL_VAULT_NAME, explorer } from "@/lib/config";

const SITE = process.env.NEXT_PUBLIC_SITE_URL ?? "https://stepwell.vercel.app";

const Icon = ({ d }: { d: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={d} /></svg>
);

export default function Home() {
  return (
    <>
      <nav className="nav">
        <div className="nav__bar">
          <a className="nav__brand" href="#top"><img className="app-icon" src="/icon.svg" alt="" />Stepwell</a>
          <div className="nav__links">
            <a href="#how">How it works</a>
            <a href="#try">Try it</a>
            <a href="#apps">For apps</a>
            <a href="/vaults">Vaults</a>
            <a href="#proof">Proof</a>
          </div>
          <a className="btn btn-ink btn-sm" href="#deposit">Deposit</a>
        </div>
      </nav>

      <main id="top">
        <section className="hero hero--split">
          <div className="container">
            <div>
              <StakeBadge />
              <h1>When a vault loses money, underwriters pay <em className="t-serif">first.</em></h1>
              <p className="lead">
                Stepwell is first-loss cover for USDC in Morpho vaults on Arc. Underwriters take any loss before covered depositors do,
                and depositors pay for that with a slice of their interest, never out of pocket. If a loss is bigger than the cover,
                the rest reaches depositors, and this page shows you exactly how much cover there is.
              </p>
              <div className="cta-row">
                <a className="btn btn-candy btn-lg" href="#try">Simulate a loss on mainnet</a>
                <a className="btn btn-outline btn-lg" href="#apps">Add cover to your app</a>
              </div>
              <p className="trust"><span>No owner key</span><span>Covered depositors leave any time</span><span>Unaudited, small amounts</span></p>
            </div>
            <div className="stage">
              <HeroWell />
            </div>
          </div>
        </section>

        <section className="section" style={{ paddingTop: 56, paddingBottom: 24 }}>
          <div className="container"><LiveStats /></div>
        </section>

        <section className="section" id="how">
          <div className="container">
            <div className="section-head">
              <div className="eyebrow"><span className="dot" />How it works</div>
              <h2>One vault, two layers, one rule about who pays.</h2>
              <p className="lead">
                Arc asked for exactly this in its request for builders: vault-loss protection bundled into deposit flows, paid for out of yield,
                with coverage figures any app can read. The name comes from Indian stepwells, where the surface water goes first in a drought
                and the deep water stays.
              </p>
              <p className="t-small" style={{ marginTop: 10 }}><a href="https://www.arc.io/blog/the-unfinished-business-of-finance-machine-commerce-and-global-money" target="_blank" rel="noreferrer" style={{ textDecoration: "underline" }}>Read Arc&apos;s request for builders</a></p>
            </div>
            <div className="grid grid-2">
              <div className="card card--flat">
                <div className="eyebrow">A Morpho vault today</div>
                <h3 className="t-title" style={{ marginTop: 10 }}>Everyone shares the loss.</h3>
                <p className="t-small" style={{ marginTop: 8 }}>
                  If a borrower defaults and the vault books bad debt, every depositor&apos;s share price drops by the same amount.
                  Earn Kit lists vaults; it does not rank or protect them. There is nothing on Arc that pays a depositor back.
                </p>
              </div>
              <div className="card card--chosen">
                <div className="eyebrow">The same vault, through Stepwell</div>
                <h3 className="t-title" style={{ marginTop: 10 }}>Underwriters take it first.</h3>
                <p className="t-small" style={{ marginTop: 8 }}>
                  The loss comes out of the cover layer until it is gone. A depositor&apos;s share price does not move while any cover
                  is left. Underwriters accept that for a share of everyone&apos;s interest, which is larger when cover is thin.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="section section--alt">
          <div className="container stack">
            <div className="split">
              <div>
                <div className="eyebrow">Premium</div>
                <h3>Paid from interest. Priced by how thin the cover is.</h3>
                <p className="lead">
                  When cover is 10% of the well or less, depositors pass up 35% of their interest. At 20% or more, they pass up 15%.
                  In between it slides. Thin cover pays underwriters more, which brings more of them in.
                </p>
                <div className="chips"><span className="chip">Read on every interaction</span><span className="chip">No oracle</span><span className="chip">Nothing paid up front</span></div>
              </div>
              <div className="stage stage--soft">
                <div className="window">
                  <div className="window__bar"><div className="lights"><i /><i /><i /></div><span className="window__title">Premium curve</span></div>
                  <svg className="curve" viewBox="0 0 420 220" aria-hidden="true">
                    <line x1="40" y1="180" x2="400" y2="180" stroke="var(--line-2)" />
                    <line x1="40" y1="20" x2="40" y2="180" stroke="var(--line-2)" />
                    <polyline points="40,40 130,40 220,126 400,126" fill="none" stroke="var(--accent)" strokeWidth="3" strokeLinejoin="round" />
                    <circle cx="175" cy="83" r="6" fill="var(--accent)" />
                    <text x="186" y="78" fontSize="12" fill="var(--ink-2)" fontFamily="var(--font-mono)">15% cover: 25% of interest</text>
                    <text x="44" y="34" fontSize="11" fill="var(--ink-3)" fontFamily="var(--font-mono)">35%</text>
                    <text x="360" y="120" fontSize="11" fill="var(--ink-3)" fontFamily="var(--font-mono)">15%</text>
                    <text x="122" y="198" fontSize="11" fill="var(--ink-3)" fontFamily="var(--font-mono)">10%</text>
                    <text x="212" y="198" fontSize="11" fill="var(--ink-3)" fontFamily="var(--font-mono)">20%</text>
                    <text x="300" y="214" fontSize="11" fill="var(--ink-3)" fontFamily="var(--font-mono)">cover ratio</text>
                  </svg>
                </div>
              </div>
            </div>

            <div className="split split--flip">
              <div>
                <div className="eyebrow">No gaming it</div>
                <h3>Nobody can jump in before a loss or out just ahead of one.</h3>
                <p className="lead">
                  A new covered deposit spends one day earning and losing like a plain vault deposit before it is covered, so seeing bad debt
                  coming doesn&apos;t buy free cover. An underwriter who wants out gives three days&apos; notice, stops earning that day and
                  still carries losses until they leave.
                </p>
                <div className="chips"><span className="chip">One-day warm-up</span><span className="chip">Notice carries losses, earns nothing</span><span className="chip">Cover shares can&apos;t be sold on</span><span className="chip">Exit in kind if the vault is short of cash</span></div>
              </div>
              <div className="stage stage--soft">
                <div className="timeline" aria-hidden="true">
                  <div><b>Day 0</b>Gives notice. Stops earning from today. Still exposed to losses.</div>
                  <div><b>Day 0 to 3</b>A loss in the vault comes out of their share like everyone else&apos;s cover.</div>
                  <div><b>Day 3 to 4</b>Collects what is left, in USDC or vault shares. After day 4 the notice lapses.</div>
                </div>
              </div>
            </div>

            <div className="split">
              <div>
                <div className="eyebrow">If cover runs out</div>
                <h3>A buffer can run out, and it refills first.</h3>
                <p className="lead">
                  If a loss is bigger than the cover, the cover layer goes to zero first and the rest reaches depositors. If money comes
                  back later, it repays depositors&apos; loss first, then the cover&apos;s, before anyone earns again. Wiped-out cover shares
                  are voided, so a fresh layer never inherits the last one&apos;s debt.
                </p>
              </div>
              <div className="stage stage--soft">
                <div className="window">
                  <div className="window__bar"><div className="lights"><i /><i /><i /></div><span className="window__title">850 deposited, 150 cover</span></div>
                  <table className="books" style={{ margin: 0 }}>
                    <thead><tr><th style={{ paddingLeft: 16 }}>The vault&apos;s year</th><th className="r">Depositors</th><th className="r" style={{ paddingRight: 16 }}>Underwriters</th></tr></thead>
                    <tbody>
                      <tr><td style={{ paddingLeft: 16 }}>Earns 6%</td><td className="r">$888.25 · +4.5%</td><td className="r" style={{ paddingRight: 16 }}>$171.75 · +14.5%</td></tr>
                      <tr><td style={{ paddingLeft: 16 }}>Loses 8%</td><td className="r">$850.00 · no change</td><td className="r" style={{ paddingRight: 16 }}>$70.00 · −53.3%</td></tr>
                      <tr><td style={{ paddingLeft: 16 }}>Loses 22%</td><td className="r">$780.00 · −8.2%</td><td className="r" style={{ paddingRight: 16 }}>$0.00 · gone</td></tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section className="section" id="try">
          <div className="container">
            <div className="section-head">
              <div className="eyebrow"><span className="dot" />Try it on this page</div>
              <h2>Watch cover take a loss, on mainnet.</h2>
              <p className="lead">Every press is a real transaction on Arc mainnet. The receipt and the time from your click to a final result appear under the button.</p>
            </div>
            <Rehearsal />
          </div>
        </section>

        <section className="section section--alt" id="apps">
          <div className="container">
            <div className="split">
              <div>
                <div className="eyebrow">For wallets and fintech apps</div>
                <h3>Offer covered savings with one call.</h3>
                <p className="lead">
                  If your app puts users&apos; USDC into a Morpho vault through Earn Kit, you can put it through Stepwell instead. The
                  covered share is a standard ERC-4626 vault, so the code you already have works unchanged.
                </p>
                <div className="chips">
                  <span className="chip">ERC-4626 covered shares</span>
                  <span className="chip">One signature with Multicall3From</span>
                  <span className="chip">Memo tags each deposit with your app</span>
                  <span className="chip">Anyone can open a Stepwell on any vault</span>
                </div>
              </div>
              <div>
              <div className="window window--dark">
                <div className="window__bar"><div className="lights"><i /><i /><i /></div><span className="window__title">your-app.ts</span></div>
                <pre className="code">{`// `}<span className="c">covered deposit for a user, in one signature</span>{`
`}<span className="k">await</span>{` wallet.writeContract({
  address: MULTICALL3_FROM, abi, functionName: `}<span className="s">&quot;aggregate3&quot;</span>{`,
  args: [[
    approve(USDC, stepwell, amount),
    deposit(stepwell, amount, user),
  ]],
});

// `}<span className="c">how well is this vault covered? one read, any app</span>{`
`}<span className="k">const</span>{` [c] = `}<span className="k">await</span>{` factory.read.coverageFor([vault]);
c.coverBps      `}<span className="c">// 1500 = 15% of the well is cover</span>{`
c.premiumBps    `}<span className="c">// 2500 = 25% of interest passed up</span>{`
c.lossAbsorbed  `}<span className="c">// losses cover has already taken</span>{`

// `}<span className="c">or just show the cover card next to your vault</span>{`
<iframe src="${SITE}/embed?ref=your-app" />`}</pre>
              </div>
              <p className="t-small" style={{ marginTop: 12 }}><a href="/vaults" style={{ textDecoration: "underline" }}>See every Morpho vault on Arc and its cover →</a></p>
              </div>
            </div>
          </div>
        </section>

        <section className="section" id="deposit">
          <div className="container">
            <div className="section-head">
              <div className="eyebrow"><span className="dot" />{REAL_VAULT_NAME} on Morpho</div>
              <h2>Deposit with cover, or be the cover.</h2>
              <p className="lead">Same vault, same interest. The only question is which layer you want to stand in. Figures below use the vault&apos;s rate today.</p>
            </div>
            <DepositPanel />
          </div>
        </section>

        <section className="section section--alt" id="books">
          <div className="container">
            <div className="section-head">
              <div className="eyebrow">The books</div>
              <h2>Everything that happened, kept on chain.</h2>
              <p className="lead">The last 64 entries live in the contract itself, so this table never goes blank when a node forgets old receipts.</p>
            </div>
            <Books />
          </div>
        </section>

        <section className="section" id="proof">
          <div className="container">
            <div className="section-head">
              <div className="eyebrow">Proof</div>
              <h2>Check our work. <span className="t-muted">Then check it again.</span></h2>
            </div>
            <div className="grid grid-3" style={{ gridAutoRows: "1fr" }}>
              {[
                ["M9 12l2 2 4-4M5 4h14v16H5z", "Checked against a second model", "A separately written model of the rules runs beside the contract through thousands of random actions and must agree to the unit. It already caught one real bug, which is fixed."],
                ["M12 3v18M3 12h18", "Every end state reached", "A random walk of 6,000 steps fails unless it reaches cover wiped out, cover pierced, recovery refilling cover, a notice claimed, a deposit settled and cancelled, an exit in kind, a deposit refused and a restart from empty."],
                ["M4 7h16M4 12h16M4 17h10", "Five invariants", "The books never exceed the vault holdings. Covered shares never lose value while cover remains. Nobody redeems more than exists. No underwriter leaves early. The model matches."],
                ["M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6z", "No owner, no upgrades", "Every parameter is fixed when a Stepwell is created. There is no admin key, no pause and no way to change the code."],
                ["M3 12h4l3-8 4 16 3-8h4", "Bad debt on the real vault", `Fork tests on Arc mainnet state make ${REAL_VAULT_NAME}'s Morpho adapter report a 2% markdown, the way Vault V2 books bad debt, and check that cover alone pays.`],
                ["M4 4h16v12H4zM8 20h8", "Arc-native", "USDC is the gas and the asset. Multicall3From makes approve and deposit one signature. Arc's Memo contract tags deposits by app."],
                ["M5 12h14M12 5l7 7-7 7", "Proved, not sampled", "The loss rule is one pure function, and four of its properties are proved for every possible input with symbolic execution: losses within cover never touch depositors, the books always balance."],
              ].map(([d, t, p], i) => (
                <Reveal key={t} i={i}>
                  <div className="tile">
                    <span className="icon-tile"><Icon d={d} /></span>
                    <div><div className="t-title">{t}</div><p>{p}</p></div>
                  </div>
                </Reveal>
              ))}
            </div>
            <div className="cta-row">
              <a className="btn btn-outline" href={REPO_URL} target="_blank" rel="noreferrer">Read the code</a>
              <a className="btn btn-ghost" href={explorer("address", ADDR.factory)} target="_blank" rel="noreferrer">Factory on Arc</a>
            </div>
          </div>
        </section>

        <section className="section">
          <div className="container" style={{ maxWidth: 760 }}>
            <div className="section-head section-head--left">
              <div className="eyebrow">Next</div>
              <h2>What a grant would pay for.</h2>
            </div>
            <ul className="limits">
              <li><b>Seed cover on a large vault.</b> Put the grant into the cover layer of a Stepwell on Galaxy USDC or Keyrock Prime USDC, so the first real depositors have something under them.</li>
              <li><b>One wallet integration.</b> Wire the SDK into one Earn Kit wallet or savings app, so its users see a cover figure beside each vault and can choose a covered deposit.</li>
              <li><b>Prepare for an audit.</b> Freeze the contracts, write the spec the tests already encode, and open a contest before any real size goes in.</li>
            </ul>
          </div>
        </section>

        <section className="section section--alt">
          <div className="container" style={{ maxWidth: 760 }}>
            <div className="section-head section-head--left">
              <div className="eyebrow">Limits, written plainly</div>
              <h2>What it does not do.</h2>
            </div>
            <ul className="limits">
              <li><b>It covers a slice, not everything.</b> Cover is as thick as the money underwriters put up, at least 15% of the well when a deposit is made. A total loss of the vault would reach depositors.</li>
              <li><b>It is unaudited.</b> The contracts add their own risk on top of the vault&apos;s. Amounts here are small on purpose.</li>
              <li><b>Yields are low right now.</b> The large USDC vaults on Arc pay about 3% a year, so premiums are small in dollars. The arithmetic is the same at any rate.</li>
              <li><b>Vault fees count as losses.</b> If a vault&apos;s management fee ever exceeds its interest, the share price dips and the cover layer takes it.</li>
              <li><b>Cover can leave.</b> The 15% floor only blocks new deposits. Underwriters can still give notice, which the coverage figures show as cover under notice.</li>
              <li><b>Exits depend on the vault&apos;s cash.</b> If the vault is short of liquidity, a depositor can still leave with vault shares instead of USDC.</li>
            </ul>
          </div>
        </section>

        <section className="section">
          <div className="container">
            <div className="section-head"><h2>Questions</h2></div>
            <div className="faq">
              {[
                ["Who pays the premium?", "Depositors, out of interest the vault has already earned. Nobody sends a separate payment. If the vault earns nothing, nobody pays anything."],
                ["Why would anyone underwrite?", "With 15% cover and a quarter of interest passed up, underwriters earn about 2.4 times what the vault pays, around 7.5% a year at today's rate. The trade is that a loss takes their money first."],
                ["Why does my deposit wait a day?", "So nobody can see bad debt coming and buy cover just before it is booked. For that day your deposit earns and loses like a plain vault deposit. After it, anyone can settle it into covered shares, and the site does it for you."],
                ["What stops an underwriter leaving just before a loss?", "Three days' notice, losses during those three days still hit them, and from the day they give notice they stop earning. Cover shares can't be transferred, so they can't be sold to someone else either."],
                ["Is my money stuck if the vault is short of cash?", "No. Covered depositors can leave with the vault's own shares, which they can redeem later or hold."],
                ["Can I add this to my app?", "Yes. The covered share is an ERC-4626 vault, and the factory tells any app how well a vault is covered in one read. Anyone can open a Stepwell on any vault."],
                ["Why Arc?", "USDC is both the money and the gas, settlement is final in under a second, and the Morpho vaults Arc's Earn Kit lists are where this money already sits. Arc also asked for exactly this in its request for builders."],
              ].map(([q, a]) => (
                <details key={q}><summary>{q}</summary><p>{a}</p></details>
              ))}
            </div>
          </div>
        </section>

        <section className="section section--alt">
          <div className="container" style={{ textAlign: "center" }}>
            <img src="/icon.svg" alt="" style={{ width: 88, height: 88, margin: "0 auto 24px", borderRadius: 20, boxShadow: "var(--shadow-2)" }} />
            <h2>Keep the deep water. <span className="t-muted">Let someone else hold the surface.</span></h2>
            <div className="cta-row">
              <a className="btn btn-candy btn-lg" href="#deposit">Deposit with cover</a>
              <a className="btn btn-outline btn-lg" href="#try">Try a dry season first</a>
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <div className="container">
          <span style={{ display: "flex", alignItems: "center", gap: 10 }}><img className="app-icon" src="/icon.svg" alt="" />Stepwell, built on Arc</span>
          <span style={{ display: "flex", gap: 18 }}>
            <a href={REPO_URL}>Code</a>
            <a href={explorer("address", ADDR.factory)}>Contracts</a>
            <a href="/reviewers">For reviewers</a>
          </span>
        </div>
      </footer>
    </>
  );
}
