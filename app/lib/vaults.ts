import type { Address } from "viem";
import { publicClient } from "./chain";
import { factoryAbi } from "./abi";
import { ADDR } from "./config";

export type VaultRow = {
  address: Address; name: string; asset: string; tvl: number; apy: number; liquidity: number; curator: string;
  stepwells: { address: Address; coverBps: number; cover: number; covered: number; premiumBps: number; lossAbsorbed: number }[];
};

/** Every Morpho Vault V2 on Arc, joined with Stepwell's registry. */
export async function listVaults(): Promise<VaultRow[]> {
  const q = `{ vaultV2s(first: 100, where: { chainId_in: [5042] }) { items { address name asset { symbol } totalAssetsUsd netApy liquidityUsd curators { items { name } } } } }`;
  let items: { address: Address; name: string; asset: { symbol: string }; totalAssetsUsd: number | null; netApy: number | null; liquidityUsd: number | null; curators?: { items: { name: string }[] } }[] = [];
  try {
    const r = await fetch("https://api.morpho.org/graphql", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ query: q }), next: { revalidate: 300 } });
    const j = await r.json();
    items = j?.data?.vaultV2s?.items ?? [];
  } catch { /* Morpho's API is down; show only vaults we already cover */ }
  items = items.sort((a, b) => (b.totalAssetsUsd ?? 0) - (a.totalAssetsUsd ?? 0));
  const rows: VaultRow[] = [];
  for (const v of items) {
    let stepwells: VaultRow["stepwells"] = [];
    if (ADDR.factory !== "0x0000000000000000000000000000000000000000") {
      try {
        // only Stepwells on the standard terms; anyone can create one with useless terms
        const [list, cov] = await publicClient.readContract({ address: ADDR.factory, abi: factoryAbi, functionName: "standardCoverageFor", args: [v.address] });
        stepwells = list.map((a, i) => ({
          address: a,
          coverBps: Number(cov[i].coverBps),
          cover: Number(cov[i].coverAssets) / 1e6,
          covered: Number(cov[i].coveredAssets) / 1e6,
          premiumBps: Number(cov[i].premiumBps),
          lossAbsorbed: Number(cov[i].lossAbsorbed) / 1e6,
        }));
      } catch { /* registry unreachable */ }
    }
    rows.push({
      address: v.address, name: v.name, asset: v.asset.symbol, tvl: v.totalAssetsUsd ?? 0, apy: v.netApy ?? 0,
      liquidity: v.liquidityUsd ?? 0, curator: v.curators?.items.map((c) => c.name).join(", ") ?? "", stepwells,
    });
  }
  return rows;
}
