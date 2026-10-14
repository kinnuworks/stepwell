import { defineChain, type Address } from "viem";

export const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL ?? "https://rpc.mainnet.arc.io";

export const arc = defineChain({
  id: Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 5042),
  name: "Arc",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: "Arc explorer", url: "https://explorer.arc.io" } },
});

const a = (v: string | undefined) => (v ?? "0x0000000000000000000000000000000000000000") as Address;

export const ADDR = {
  usdc: "0x3600000000000000000000000000000000000000" as Address,
  multicall3From: "0x522fAf9A91c41c443c66765030741e4AaCe147D0" as Address,
  memo: "0x5294E9927c3306DcBaDb03fe70b92e01cCede505" as Address,
  factory: a(process.env.NEXT_PUBLIC_FACTORY),
  rehearsalVault: a(process.env.NEXT_PUBLIC_REHEARSAL_VAULT),
  drill: a(process.env.NEXT_PUBLIC_DRILL),
  real: a(process.env.NEXT_PUBLIC_REAL),
  realVault: "0xbeef0016cb2Fd5C352ea7CA08a9f54739DFa7298" as Address,
};

export const REAL_VAULT_NAME = "Steakhouse Prime USDC";
export const REPO_URL = process.env.NEXT_PUBLIC_REPO_URL ?? "https://github.com/";
export const explorer = (kind: "tx" | "address", v: string) => `https://explorer.arc.io/${kind}/${v}`;
export const sourcify = (addr: string) => `https://repo.sourcify.dev/${arc.id}/${addr}`;
