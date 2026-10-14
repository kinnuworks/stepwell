import { ADDR, REPO_URL, explorer, sourcify, REAL_VAULT_NAME } from "@/lib/config";

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
          <li><b>1. Press “Start a dry season” on the home page.</b> A vault holding our own USDC loses 8% on Arc mainnet. The cover layer shrinks and covered deposits stay where they were. The receipt and the settlement time appear under the button. No wallet needed.</li>
          <li><b>2. Look at the hero.</b> That well is the Stepwell on {REAL_VAULT_NAME}, a real Morpho vault, read live from the chain.</li>
          <li><b>3. Read the contract.</b> <span className="mono">contracts/src/Stepwell.sol</span>, about 500 lines. The waterfall is in <span className="mono">_split</span>.</li>
          <li><b>4. Run the tests.</b> <span className="mono">cd contracts &amp;&amp; arc-forge test</span>. 24 tests: unit, fuzz, five invariants checked against an independent model, and a walk that proves every end state was reached. <span className="mono">FORK=1 arc-forge test --match-contract Fork</span> runs against the real vault on mainnet state.</li>
        </ol>
        <h2 className="t-h3" style={{ marginTop: 48 }}>Contracts on Arc mainnet</h2>
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
          <li>Most of the money in these wells is ours. We say who else has joined in the README, by address.</li>
        </ul>
        <p className="t-small" style={{ marginTop: 32 }}><a href={REPO_URL}>Code, threat model and test logs on GitHub</a></p>
      </div>
    </main>
  );
}
