import { NextResponse } from "next/server";
import { createWalletClient, http, parseUnits } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arc, ADDR, RPC_URL } from "@/lib/config";
import { publicClient } from "@/lib/chain";
import { rehearsalAbi, stepwellAbi } from "@/lib/abi";

export const dynamic = "force-dynamic";

const ERC20 = [
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

let busyUntil = 0;

/** One button, two directions: a dry season marks the rehearsal vault down by 8%, and rain puts
 *  the lost money back. The relayer pays the gas, so visitors need no wallet. */
export async function POST(req: Request) {
  const key = process.env.OPERATOR_KEY as `0x${string}` | undefined;
  if (!key) return NextResponse.json({ error: "Rehearsals are switched off on this deployment." }, { status: 503 });
  if (Date.now() < busyUntil) return NextResponse.json({ error: "Someone else is running a rehearsal. Try again in a few seconds." }, { status: 429 });
  busyUntil = Date.now() + 8_000;
  try {
    const { action } = (await req.json().catch(() => ({}))) as { action?: string };
    const account = privateKeyToAccount(key);
    const wallet = createWalletClient({ account, chain: arc, transport: http(RPC_URL) });
    const t0 = Date.now();
    let hash: `0x${string}`;
    if (action === "rain") {
      const bal = await publicClient.readContract({ address: ADDR.usdc, abi: ERC20, functionName: "balanceOf", args: [account.address] });
      const keep = parseUnits("0.3", 6); // gas money for future rehearsals
      const amount = bal > keep ? bal - keep : 0n;
      if (amount === 0n) throw new Error("Nothing to put back yet.");
      const a = await wallet.writeContract({ address: ADDR.usdc, abi: ERC20, functionName: "approve", args: [ADDR.rehearsalVault, amount] });
      await publicClient.waitForTransactionReceipt({ hash: a });
      hash = await wallet.writeContract({ address: ADDR.rehearsalVault, abi: rehearsalAbi, functionName: "refill", args: [amount] });
    } else {
      hash = await wallet.writeContract({ address: ADDR.rehearsalVault, abi: rehearsalAbi, functionName: "lose", args: [800n] });
    }
    await publicClient.waitForTransactionReceipt({ hash });
    const settledMs = Date.now() - t0;
    const sync = await wallet.writeContract({ address: ADDR.drill, abi: stepwellAbi, functionName: "sync" });
    await publicClient.waitForTransactionReceipt({ hash: sync });
    return NextResponse.json({ hash, sync, settledMs });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message.split("\n")[0] : "The rehearsal failed." }, { status: 500 });
  } finally {
    busyUntil = 0;
  }
}
