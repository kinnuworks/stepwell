"use client";

import { useState } from "react";
import { createWalletClient, custom, type Address } from "viem";
import { ADDR, arc, explorer } from "@/lib/config";
import { factoryAbi } from "@/lib/abi";
import { STEPWELL_CREATION_CODE } from "@/lib/bytecode";

type Eth = { request: (a: { method: string; params?: unknown[] }) => Promise<unknown> };

/** Anyone can open a Stepwell on a vault that has none, with the standard parameters. */
export default function OpenStepwell({ vault, name }: { vault: Address; name: string }) {
  const [state, setState] = useState<{ text: string; hash?: string } | null>(null);
  async function open() {
    const eth = (window as unknown as { ethereum?: Eth }).ethereum;
    if (!eth) { setState({ text: "Needs a browser wallet." }); return; }
    try {
      const [account] = (await eth.request({ method: "eth_requestAccounts" })) as Address[];
      const wallet = createWalletClient({ account, chain: arc, transport: custom(eth) });
      const hash = await wallet.writeContract({
        address: ADDR.factory, abi: factoryAbi, functionName: "create",
        args: [vault, `Stepwell on ${name}`, "swV", { floorBps: 1500, coverLowBps: 1000, coverHighBps: 2000, premiumHighBps: 3500, premiumLowBps: 1500, noticeSeconds: 259200, claimWindowSeconds: 86400, warmupSeconds: 86400 }, STEPWELL_CREATION_CODE],
      });
      setState({ text: "Opened.", hash });
    } catch (e) { setState({ text: e instanceof Error ? e.message.split("\n")[0] : "Failed." }); }
  }
  return state
    ? <span className="t-micro">{state.text} {state.hash && <a href={explorer("tx", state.hash)} target="_blank" rel="noreferrer">tx</a>}</span>
    : <button className="btn btn-outline btn-sm" onClick={open}>Open a Stepwell</button>;
}
