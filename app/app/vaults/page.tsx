import { listVaults } from "@/lib/vaults";
import { explorer } from "@/lib/config";
import OpenStepwell from "@/components/OpenStepwell";

export const revalidate = 60;
export const metadata = { title: "Stepwell · every Morpho vault on Arc, and its cover" };

const usd = (n: number) => n >= 1e6 ? "$" + (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? "$" + (n / 1e3).toFixed(1) + "k" : "$" + n.toFixed(2);

export default async function Vaults() {
  const rows = await listVaults();
  const total = rows.reduce((a, r) => a + r.tvl, 0);
  const covered = rows.filter((r) => r.stepwells.length > 0).length;
  return (
    <main className="section">
      <div className="container">
        <a className="t-small" href="/">← Back to Stepwell</a>
        <div className="section-head section-head--left" style={{ marginTop: 18 }}>
          <div className="eyebrow"><span className="dot" />Coverage registry</div>
          <h2>Every Morpho vault on Arc, and how well it is covered.</h2>
          <p className="lead">
            {rows.length} vaults hold {usd(total)}. {covered} {covered === 1 ? "has" : "have"} a Stepwell. Any app can read these figures from the
            factory in one call, and anyone can open a Stepwell on a vault that has none.
          </p>
        </div>
        <div className="card books-wrap">
          <table className="books">
            <thead><tr><th>Vault</th><th>Curator</th><th className="r">Deposits</th><th className="r">Rate</th><th className="r">Instant cash</th><th>Cover</th><th></th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.address}>
                  <td><a href={explorer("address", r.address)} target="_blank" rel="noreferrer"><b>{r.name}</b></a><div className="t-micro">{r.asset}</div></td>
                  <td>{r.curator || "—"}</td>
                  <td className="r">{usd(r.tvl)}</td>
                  <td className="r">{(r.apy * 100).toFixed(2)}%</td>
                  <td className="r">{usd(r.liquidity)}</td>
                  <td>
                    {r.stepwells.length === 0 ? <span className="t-micro">No cover</span> : r.stepwells.map((s) => (
                      <div key={s.address} className="t-small"><b style={{ color: "var(--accent)" }}>{(s.coverBps / 100).toFixed(1)}% cover</b> · {usd(s.cover)} standing · {(s.premiumBps / 100).toFixed(0)}% of interest</div>
                    ))}
                  </td>
                  <td>{r.stepwells.length === 0 && <OpenStepwell vault={r.address} name={r.name} />}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="t-micro" style={{ marginTop: 14 }}>Vault figures from Morpho&apos;s public API, refreshed every five minutes. Cover figures read from the Stepwell factory on Arc mainnet.</p>
      </div>
    </main>
  );
}
