import { NextResponse } from "next/server";
import { ADDR } from "@/lib/config";

export const revalidate = 300;

/** The covered vault's current rate, from Morpho's public API. */
export async function GET() {
  try {
    const q = `{ vaultV2ByAddress(address: "${ADDR.realVault}", chainId: 5042) { netApy } }`;
    const r = await fetch("https://api.morpho.org/graphql", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ query: q }), next: { revalidate: 300 } });
    const j = await r.json();
    const apy = j?.data?.vaultV2ByAddress?.netApy;
    if (typeof apy !== "number") throw new Error("no rate");
    return NextResponse.json({ apy });
  } catch {
    return NextResponse.json({ apy: null });
  }
}
