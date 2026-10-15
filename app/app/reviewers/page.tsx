import { ADDR, REPO_URL, explorer, sourcify, REAL_VAULT_NAME, NET } from "@/lib/config";

export const metadata = { title: "Stepwell · for reviewers" };

export default function Reviewers() {
  const rows: [string, string][] = [
    ["Factory and registry", ADDR.factory],
    [`Stepwell on ${REAL_VAULT_NAME}`, ADDR.real],
    ["Rehearsal Stepwell", ADDR.drill],
    ["Rehearsal vault (our own dollars)", ADDR.rehearsalVault],
    [`${REAL_VAULT_NAME} (Morpho, not ours)`, ADDR.realVault],
  ];
  return (
    <main className="section">
      <div className="container" style={{ maxWidth: 760 }}>
        <a className="t-small" href="/">← Back to Stepwell</a>
        <h1 className="t-h2" style={{ marginTop: 18 }}>For reviewers: three minutes.</h1>
        <ol className="limits" style={{ marginTop: 28, listStyle: "none" }}>
          <li><b>1. Press “Simulate an 8% vault loss” on the home page.</b> Our test vault, holding only our own USDC, sends 8% to our wallet on {NET}, which is how bad debt looks from outside. The cover layer shrinks and covered deposits stay where they were. Press it again to watch cover run out. No wallet needed.</li>
          <li><b>2. Look at the hero.</b> That well is the Stepwell on {REAL_VAULT_NAME}, a real Morpho vault, read live from the chain.</li>
          <li><b>3. Read the contract.</b> <span className="mono">contracts/src/Stepwell.sol</span>, about 670 lines. The waterfall is in <span className="mono">_split</span>.</li>
          <li><b>4. Run the tests.</b> <span className="mono">cd contracts &amp;&amp; arc-forge test</span>: 36 tests, including a regression test for each attack found in two reviews, five invariants checked against a separately written model and a 6,000-step reachability walk. <span className="mono">FORK=1 arc-forge test --match-contract Fork --isolate</span>: three tests on Arc mainnet state, including bad debt in the real Morpho vault. <span className="mono">halmos --contract WaterfallProofs</span>: four properties proved for every amount up to 2^64 units.</li>
        </ol>
        <h2 className="t-h3" style={{ marginTop: 48 }}>Contracts on {NET}</h2>
        <p className="t-small" style={{ marginTop: 10 }}>These run the code tagged <span className="mono">v1.0-mainnet</span>. Two issues found by a review after the deploy (a deposit warm-up that a stranger could keep restarting with dust, and interest an underwriter could keep by renewing a notice) are fixed in the repo with tests and listed in THREATS.md; neither can take anyone&apos;s money. The Steakhouse well opened on 15 October 2026 and its first deposit is in the one-day warm-up until about 01:05 UTC on 16 October.</p>
        <div className="books-wrap" style={{ marginTop: 16 }}>
          <table className="books">
            <thead><tr><th>What</th><th>Address</th><th className="r">Source</th></tr></thead>
            <tbody>
              {rows.map(([k, v]) => (
                <tr key={k}><td>{k}</td><td className="mono"><a href={explorer("address", v)} target="_blank" rel="noreferrer">{v.slice(0, 10)}…{v.slice(-6)}</a></td><td className="r"><a href={sourcify(v)} target="_blank" rel="noreferrer">Sourcify</a></td></tr>
              ))}
            </tbody>
          </table>
        </div>
        <h2 className="t-h3" style={{ marginTop: 48 }}>What we are not claiming</h2>
        <ul className="limits" style={{ marginTop: 16 }}>
          <li>No audit. Amounts are a few dollars on purpose.</li>
          <li>Cover is a slice. A loss bigger than the cover reaches depositors, and the rehearsal can show that too.</li>
          <li>Most of the money in these wells is ours. Anyone else who joins shows up in the on-chain history on the home page, by block.</li>
        </ul>
        <p className="t-small" style={{ marginTop: 32 }}><a href={REPO_URL}>Code, threat model and test logs on GitHub</a></p>
      </div>
    </main>
  );
}
