import { listVaults } from "@/lib/vaults";
import { explorer } from "@/lib/config";
import OpenStepwell from "@/components/OpenStepwell";

export const revalidate = 60;
export const metadata = { title: "Stepwell · every Morpho vault on Arc, and its cover" };

const usd = (n: number) => n >= 1e6 ? "$" + (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? "$" + (n / 1e3).toFixed(1) + "k" : "$" + n.toFixed(2);

export default async function Vaults({ searchParams }: { searchParams: Promise<{ all?: string }> }) {
  const { all } = await searchParams;
  const everything = await listVaults();
  const rows = all ? everything : everything.filter((r) => r.tvl >= 10_000 || r.stepwells.length > 0);
  const hidden = everything.length - rows.length;
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
            {everything.length} vaults hold {usd(everything.reduce((a, r) => a + r.tvl, 0))}. {covered} {covered === 1 ? "has" : "have"} a Stepwell on the standard terms. Any app can read these figures from the
            factory in one call, and anyone can open a Stepwell on a vault that has none.
          </p>
        </div>
        <div className="card books-wrap">
          <table className="books">
            <thead><tr><th>Vault</th><th className="hide-sm">Curator</th><th className="r">Deposits</th><th className="r hide-sm">Rate</th><th className="r hide-sm">Instant cash</th><th>Cover</th><th className="hide-sm"></th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.address}>
                  <td><a href={explorer("address", r.address)} target="_blank" rel="noreferrer"><b>{r.name}</b></a><div className="t-micro mono">{r.asset} · {r.address.slice(0, 6)}…{r.address.slice(-4)}</div></td>
                  <td className="hide-sm">{r.curator || <span className="t-micro">No curator listed</span>}</td>
                  <td className="r">{usd(r.tvl)}</td>
                  <td className="r hide-sm">{(r.apy * 100).toFixed(2)}%</td>
                  <td className="r hide-sm">{usd(r.liquidity)}</td>
                  <td>
                    {r.stepwells.length === 0 ? <span className="t-micro">No cover</span> : r.stepwells.map((s) => (
                      <div key={s.address} className="t-small"><b style={{ color: "var(--accent)" }}>{(s.coverBps / 100).toFixed(1)}% cover</b> · {usd(s.cover)} standing · {(s.premiumBps / 100).toFixed(0)}% of interest</div>
                    ))}
                  </td>
                  <td className="hide-sm">{r.stepwells.length === 0 && r.tvl >= 10_000 && <OpenStepwell vault={r.address} name={r.name} />}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {hidden > 0 && <p className="t-small" style={{ marginTop: 14 }}><a href="/vaults?all=1" style={{ textDecoration: "underline" }}>Show {hidden} test and dust vaults under $10k</a></p>}
        <p className="t-micro" style={{ marginTop: 14 }}>Instant cash is what Morpho&apos;s API reports as withdrawable now; vaults lending into the same markets share it, so several show the same figure. Vault figures from Morpho&apos;s public API, refreshed every five minutes. Cover figures read from the Stepwell factory on Arc mainnet.</p>
      </div>
    </main>
  );
}
