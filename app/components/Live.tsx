"use client";

import { useCallback, useEffect, useState } from "react";
import { createWalletClient, custom, encodeFunctionData, keccak256, parseUnits, toHex, type Address } from "viem";
import WellDrawing from "./WellDrawing";
import { readWell, KIND_LABEL, publicClient, type WellState } from "@/lib/chain";
import { ADDR, arc, explorer, REAL_VAULT_NAME } from "@/lib/config";
import { stepwellAbi } from "@/lib/abi";

const money = (n: number) => "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const short = (h: string) => h.slice(0, 8) + "…" + h.slice(-6);

export function useWell(address: Address, every = 6000) {
  const [state, setState] = useState<WellState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const refresh = useCallback(async () => {
    try { setState(await readWell(address)); setError(null); }
    catch { setError("Could not read Arc right now. Retrying."); }
  }, [address]);
  useEffect(() => {
    refresh();
    const t = setInterval(refresh, every);
    return () => clearInterval(t);
  }, [refresh, every]);
  return { state, error, refresh };
}

function Readout({ s }: { s: WellState }) {
  return (
    <div className="well-readout">
      <div><div className="k">Covered deposits</div><div className="v">{money(s.covered)}</div><div className="d">exit any time</div></div>
      <div><div className="k">First-loss cover</div><div className="v">{money(s.cover)}</div><div className="d">{(s.coverBps / 100).toFixed(1)}% of the well</div></div>
      <div><div className="k">Losses absorbed</div><div className="v">{money(s.lossAbsorbed)}</div><div className="d">{money(s.lossPassedThrough)} reached depositors</div></div>
    </div>
  );
}

/** The hero: the real Stepwell on a Morpho vault, read live from Arc. */
export function HeroWell() {
  const { state, error } = useWell(ADDR.real);
  const total = state ? state.covered + state.cover : 0;
  return (
    <div className="window">
      <div className="window__bar">
        <div className="lights"><i /><i /><i /></div>
        <span className="window__title">Stepwell · {REAL_VAULT_NAME}</span>
      </div>
      {state ? (
        <>
          <WellDrawing covered={state.covered} cover={state.cover} scaleTotal={total} />
          <Readout s={state} />
          <div className="window__foot">
            <span>Read from Arc mainnet, block {state.block.toString()}</span>
            <a href={explorer("address", ADDR.real)} target="_blank" rel="noreferrer">contract</a>
          </div>
        </>
      ) : (
        <div style={{ padding: 40 }} className="t-small">{error ?? "Reading the well from Arc…"}</div>
      )}
    </div>
  );
}

type Run = { label: string; hash: string; ms: number };

/** Try it: a rehearsal vault holding the team's own dollars. Visitors trigger real mainnet losses. */
export function Rehearsal() {
  const { state, refresh } = useWell(ADDR.drill, 4000);
  const [start, setStart] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ text: string; err?: boolean } | null>(null);
  const [runs, setRuns] = useState<Run[]>([]);
  useEffect(() => { if (state && start === null) setStart(state.covered + state.cover); }, [state, start]);

  async function go(action: "drought" | "rain") {
    if (!state) return;
    setBusy(true);
    const before = { s: state.covered, j: state.cover };
    setMsg({ text: action === "drought" ? "Marking the vault down by 8% on Arc mainnet…" : "Putting the lost money back…" });
    try {
      const r = await fetch("/api/rehearse", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action }) });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error);
      const after = await readWell(ADDR.drill);
      await refresh();
      setRuns((x) => [{ label: action === "drought" ? "Dry season, vault −8%" : "Rain, money put back", hash: j.hash, ms: j.settledMs }, ...x].slice(0, 4));
      if (action === "drought") {
        const lost = before.s + before.j - (after.covered + after.cover);
        const fromCover = before.j - after.cover;
        setMsg({
          text: after.lossPassedThrough > state.lossPassedThrough
            ? `The loss was bigger than the cover. Underwriters lost everything first, and depositors are down ${money(before.s - after.covered)}. Cover is a buffer, and a buffer can run out.`
            : `The vault lost ${money(lost)}. ${money(fromCover)} of it came out of the cover. Depositors still have ${money(after.covered)}. Final in ${(j.settledMs / 1000).toFixed(2)} seconds.`,
        });
      } else {
        setMsg({ text: `The money is back. Interest is split as usual: most to depositors, a slice to the underwriters.` });
      }
    } catch (e) {
      setMsg({ text: e instanceof Error ? e.message : "Something went wrong.", err: true });
    } finally {
      setBusy(false);
    }
  }

  const total = state ? state.covered + state.cover : 0;
  return (
    <div className="try">
      <div className="card">
        <div className="eyebrow"><span className="dot" />Real money, real chain</div>
        <h3 className="t-h3" style={{ marginTop: 12 }}>Go on, break it.</h3>
        <p className="t-small" style={{ marginTop: 10 }}>
          This well sits on a small vault holding our own dollars. Press the button and the vault loses 8% for real on Arc mainnet.
          Watch which water goes. No wallet needed; we pay the gas.
        </p>
        <div className="cta-row" style={{ justifyContent: "flex-start", marginTop: 20 }}>
          <button className="btn btn-candy" disabled={busy || !state} onClick={() => go("drought")}>Start a dry season</button>
          <button className="btn btn-outline" disabled={busy || !state} onClick={() => go("rain")}>Let it rain</button>
        </div>
        <p className={"status" + (msg?.err ? " err" : "")} aria-live="polite">{msg?.text}</p>
        {runs.length > 0 && (
          <div className="receipt-list">
            {runs.map((r) => (
              <div className="receipt" key={r.hash}>
                <span>{r.label}</span>
                <a href={explorer("tx", r.hash)} target="_blank" rel="noreferrer">{short(r.hash)} · {r.ms} ms</a>
              </div>
            ))}
          </div>
        )}
      </div>
      <div className="stage stage--soft">
        <div className="window">
          <div className="window__bar"><div className="lights"><i /><i /><i /></div><span className="window__title">Rehearsal well</span></div>
          {state && start ? (
            <>
              <WellDrawing covered={state.covered} cover={state.cover} scaleTotal={start} startTotal={start} />
              <Readout s={state} />
            </>
          ) : <div style={{ padding: 40 }} className="t-small">Reading the rehearsal well…</div>}
        </div>
      </div>
    </div>
  );
}

/** The books: the last entries, kept in contract storage. */
export function Books() {
  const { state } = useWell(ADDR.real, 10000);
  const drill = useWell(ADDR.drill, 10000).state;
  const [which, setWhich] = useState<"real" | "drill">("drill");
  const s = which === "real" ? state : drill;
  return (
    <div className="card">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap", marginBottom: 16 }}>
        <div className="segmented" role="tablist">
          <button aria-selected={which === "drill"} onClick={() => setWhich("drill")}>Rehearsal well</button>
          <button aria-selected={which === "real"} onClick={() => setWhich("real")}>{REAL_VAULT_NAME}</button>
        </div>
        <span className="t-micro">Read from contract storage, not from old receipts</span>
      </div>
      <div className="books-wrap">
        <table className="books">
          <thead><tr><th>Block</th><th>What happened</th><th className="r">Amount</th><th className="r">Covered</th><th className="r">Cover</th></tr></thead>
          <tbody>
            {(s?.revisions ?? []).map((r, i) => (
              <tr key={i}>
                <td className="mono">{r.block.toString()}</td>
                <td>{KIND_LABEL[r.kind] ?? r.kind}</td>
                <td className="r">{r.kind === 4 ? "notice" : money(r.amount)}</td>
                <td className="r">{money(r.deep)}</td>
                <td className="r">{money(r.cover)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

type Eth = { request: (a: { method: string; params?: unknown[] }) => Promise<unknown> };
const ERC20_APPROVE = [{ type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] }] as const;
const MEMO = [{ type: "function", name: "memo", stateMutability: "nonpayable", inputs: [{ name: "target", type: "address" }, { name: "data", type: "bytes" }, { name: "memoId", type: "bytes32" }, { name: "memoData", type: "bytes" }], outputs: [] }] as const;
const M3F = [{ type: "function", name: "aggregate3", stateMutability: "payable", inputs: [{ type: "tuple[]", components: [{ name: "target", type: "address" }, { name: "allowFailure", type: "bool" }, { name: "callData", type: "bytes" }] }], outputs: [{ type: "tuple[]", components: [{ name: "success", type: "bool" }, { name: "returnData", type: "bytes" }] }] }] as const;

/** Deposit with cover, or underwrite: one signature through Arc's Multicall3From. */
/** Deposits are routed through Arc's Memo contract so the app that sent them is on the record.
 *  Memo calls the Stepwell through Arc's CallFrom precompile, so the depositor is still the sender. */
export function DepositPanel({ appRef: fixedRef }: { appRef?: string }) {
  const [appRef, setAppRef] = useState(fixedRef ?? "stepwell.site");
  useEffect(() => {
    const r = new URLSearchParams(window.location.search).get("ref");
    if (!fixedRef && r) setAppRef(r.slice(0, 64));
  }, [fixedRef]);
  const [mode, setMode] = useState<"deposit" | "cover">("deposit");
  const [amount, setAmount] = useState("1.00");
  const [account, setAccount] = useState<Address | null>(null);
  const [msg, setMsg] = useState<{ text: string; err?: boolean; hash?: string } | null>(null);
  const { state, refresh } = useWell(ADDR.real, 8000);
  const eth = typeof window !== "undefined" ? (window as unknown as { ethereum?: Eth }).ethereum : undefined;

  async function connect() {
    if (!eth) { setMsg({ text: "No browser wallet found. Install one, or use the rehearsal above, which needs none.", err: true }); return; }
    const [a] = (await eth.request({ method: "eth_requestAccounts" })) as Address[];
    try { await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x" + arc.id.toString(16) }] }); }
    catch { await eth.request({ method: "wallet_addEthereumChain", params: [{ chainId: "0x" + arc.id.toString(16), chainName: "Arc", nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 }, rpcUrls: arc.rpcUrls.default.http, blockExplorerUrls: ["https://explorer.arc.io"] }] }); }
    setAccount(a);
  }

  async function submit() {
    if (!eth || !account) return;
    try {
      const value = parseUnits(amount || "0", 6);
      if (value <= 0n) throw new Error("Enter an amount.");
      const wallet = createWalletClient({ account, chain: arc, transport: custom(eth) });
      const call = mode === "deposit"
        ? encodeFunctionData({ abi: stepwellAbi, functionName: "deposit", args: [value, account] })
        : encodeFunctionData({ abi: stepwellAbi, functionName: "depositCover", args: [value, account] });
      setMsg({ text: "Confirm in your wallet. Approval and deposit go in one signature, tagged with this app's memo." });
      const hash = await wallet.writeContract({
        address: ADDR.multicall3From, abi: M3F, functionName: "aggregate3",
        args: [[
          { target: ADDR.usdc, allowFailure: false, callData: encodeFunctionData({ abi: ERC20_APPROVE, functionName: "approve", args: [ADDR.real, value] }) },
          { target: ADDR.memo, allowFailure: false, callData: encodeFunctionData({ abi: MEMO, functionName: "memo", args: [ADDR.real, call, keccak256(toHex(appRef)), toHex(appRef)] }) },
        ]],
      });
      const t0 = Date.now();
      await publicClient.waitForTransactionReceipt({ hash });
      await refresh();
      setMsg({ text: `Done. Final in ${((Date.now() - t0) / 1000).toFixed(2)} seconds.`, hash });
    } catch (e) {
      setMsg({ text: e instanceof Error ? e.message.split("\n")[0] : "The transaction did not go through.", err: true });
    }
  }

  const room = state ? Math.max(0, state.cover * 10000 / state.floorBps - state.cover - state.covered) : 0;
  return (
    <div className="card card--raised" style={{ maxWidth: 460, marginInline: "auto" }}>
      <div className="segmented">
        <button aria-pressed={mode === "deposit"} onClick={() => setMode("deposit")}>Deposit with cover</button>
        <button aria-pressed={mode === "cover"} onClick={() => setMode("cover")}>Underwrite</button>
      </div>
      <p className="t-small" style={{ marginTop: 14 }}>
        {mode === "deposit"
          ? `Your USDC goes into ${REAL_VAULT_NAME} on Morpho. If the vault loses money, the cover layer pays first. You give up ${state ? (state.premiumBps / 100).toFixed(0) : "about 25"}% of your interest for it, and you can leave any time.`
          : "You earn a slice of every depositor's interest on top of the vault's own rate. A loss takes your money first. Leaving needs three days' notice, and you still carry losses while you wait."}
      </p>
      <div className="field">
        <label htmlFor="amt">Amount in USDC</label>
        <input id="amt" className="input" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
        {mode === "deposit" && state && <span className="t-micro">Room for covered deposits right now: {money(room)}</span>}
      </div>
      <div style={{ marginTop: 18 }}>
        {account
          ? <button className="btn btn-candy" style={{ width: "100%" }} onClick={submit}>{mode === "deposit" ? "Deposit with cover" : "Put up cover"}</button>
          : <button className="btn btn-ink" style={{ width: "100%" }} onClick={connect}>Connect a wallet</button>}
      </div>
      <p className={"status" + (msg?.err ? " err" : "")} aria-live="polite">
        {msg?.text} {msg?.hash && <a className="mono" href={explorer("tx", msg.hash)} target="_blank" rel="noreferrer">{short(msg.hash)}</a>}
      </p>
      <p className="t-micro">Unaudited. Keep it to amounts you are happy to lose.</p>
    </div>
  );
}

export function LiveStats() {
  const real = useWell(ADDR.real, 12000).state;
  const drill = useWell(ADDR.drill, 12000).state;
  if (!real || !drill) return null;
  return (
    <div className="proof-strip">
      <div className="stat"><b>{money(real.covered + drill.covered)}</b><span>covered deposits on Arc</span></div>
      <div className="stat"><b>{money(real.cover + drill.cover)}</b><span>first-loss cover standing</span></div>
      <div className="stat"><b>{money(real.lossAbsorbed + drill.lossAbsorbed)}</b><span>losses taken by cover</span></div>
      <div className="stat"><b>{(real.premiumBps / 100).toFixed(0)}%</b><span>of interest passed to cover today</span></div>
    </div>
  );
}
