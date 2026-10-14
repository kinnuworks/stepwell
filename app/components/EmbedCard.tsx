"use client";

import WellDrawing from "./WellDrawing";
import { useWell } from "./Live";
import { ADDR, REAL_VAULT_NAME } from "@/lib/config";

const money = (n: number) => "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function EmbedCard({ appRef }: { appRef: string }) {
  const { state } = useWell(ADDR.real, 10000);
  if (!state) return <div className="card t-small">Reading cover from Arc…</div>;
  return (
    <div className="card" style={{ padding: 0, overflow: "hidden", maxWidth: 420 }}>
      <WellDrawing covered={state.covered} cover={state.cover} scaleTotal={state.covered + state.cover} />
      <div style={{ padding: "14px 16px" }}>
        <div className="eyebrow"><span className="dot" />Covered by Stepwell</div>
        <p className="t-small" style={{ marginTop: 8 }}>
          The first {money(state.cover)} of any loss in {REAL_VAULT_NAME} is taken by underwriters ({(state.coverBps / 100).toFixed(1)}% of the well).
          Covered depositors pass {(state.premiumBps / 100).toFixed(0)}% of their interest to them.
        </p>
        <a className="btn btn-candy btn-sm" style={{ marginTop: 12 }} href={`/?ref=${encodeURIComponent(appRef)}#deposit`} target="_top">Deposit with cover</a>
      </div>
    </div>
  );
}
