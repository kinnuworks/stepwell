/**
 * Stepwell for apps. Two things most integrations need:
 *   1. how well a vault is covered (one read from the factory), and
 *   2. the calls for a covered deposit in one signature on Arc.
 * Depends only on viem.
 */
import { encodeFunctionData, keccak256, parseAbi, toHex, type Address, type PublicClient } from "viem";

export const ARC = {
  usdc: "0x3600000000000000000000000000000000000000" as Address,
  multicall3From: "0x522fAf9A91c41c443c66765030741e4AaCe147D0" as Address,
  memo: "0x5294E9927c3306DcBaDb03fe70b92e01cCede505" as Address,
};

const coverageStruct =
  "struct Coverage { address underlying; uint256 coveredAssets; uint256 coverAssets; uint256 settlingAssets; uint256 coverBps; uint256 premiumBps; uint256 floorBps; uint256 noticeSeconds; uint256 warmupSeconds; uint256 coverUnderNotice; uint256 lossAbsorbed; uint256 lossPassedThrough; uint256 interestToCover; uint256 coverDeficit; }";
const factoryAbi = parseAbi([
  coverageStruct,
  "function coverageFor(address vault) view returns (Coverage[])",
  "function standardCoverageFor(address vault) view returns (address[] stepwells, Coverage[] coverages)",
  "function stepwellsFor(address vault) view returns (address[])",
]);
export const stepwellAbi = parseAbi([
  "function requestDeposit(uint256 assets, address controller, address owner) returns (uint256)",
  "function claimableDepositRequest(uint256 requestId, address controller) view returns (uint256)",
  "function settle(address controller) returns (uint256)",
  "function depositCover(uint256 assets, address receiver) returns (uint256)",
  "function maxRequest() view returns (uint256)",
]);
const erc20 = parseAbi(["function approve(address spender, uint256 amount) returns (bool)"]);
const memoAbi = parseAbi(["function memo(address target, bytes data, bytes32 memoId, bytes memoData)"]);
export const multicall3FromAbi = parseAbi([
  "function aggregate3((address target, bool allowFailure, bytes callData)[] calls) payable returns ((bool success, bytes returnData)[])",
]);

export type Coverage = {
  stepwell: Address;
  coveredUsdc: number; // settled, covered deposits
  settlingUsdc: number; // deposits still in their warm-up, not covered yet
  coverUsdc: number;
  coverUnderNoticeUsdc: number; // cover that has asked to leave
  coverPct: number;
  premiumPct: number;
  lossAbsorbedUsdc: number;
  lossPassedThroughUsdc: number;
};

const usdc = (v: bigint) => Number(v) / 1e6;

/**
 * How well a vault is covered. By default only Stepwells on the factory's standard terms count,
 * so nobody can make a vault look covered by opening one with odd parameters. Empty array: no cover.
 */
export async function coverageFor(
  client: PublicClient, factory: Address, vault: Address, opts: { includeNonStandard?: boolean } = {},
): Promise<Coverage[]> {
  let list: readonly Address[];
  let cov: readonly { coveredAssets: bigint; settlingAssets: bigint; coverAssets: bigint; coverUnderNotice: bigint; coverBps: bigint; premiumBps: bigint; lossAbsorbed: bigint; lossPassedThrough: bigint }[];
  if (opts.includeNonStandard) {
    [list, cov] = await Promise.all([
      client.readContract({ address: factory, abi: factoryAbi, functionName: "stepwellsFor", args: [vault] }),
      client.readContract({ address: factory, abi: factoryAbi, functionName: "coverageFor", args: [vault] }),
    ]);
  } else {
    [list, cov] = await client.readContract({ address: factory, abi: factoryAbi, functionName: "standardCoverageFor", args: [vault] });
  }
  return list.map((stepwell, i) => ({
    stepwell,
    coveredUsdc: usdc(cov[i].coveredAssets),
    settlingUsdc: usdc(cov[i].settlingAssets),
    coverUsdc: usdc(cov[i].coverAssets),
    coverUnderNoticeUsdc: usdc(cov[i].coverUnderNotice),
    coverPct: Number(cov[i].coverBps) / 100,
    premiumPct: Number(cov[i].premiumBps) / 100,
    lossAbsorbedUsdc: usdc(cov[i].lossAbsorbed),
    lossPassedThroughUsdc: usdc(cov[i].lossPassedThrough),
  }));
}

/**
 * The calls for a covered deposit (or for putting up cover) in one transaction from an ordinary
 * wallet: approve, then the deposit routed through Arc's Memo contract with your app's reference.
 * Send them with Multicall3From, which keeps the user as the sender of every call.
 *
 * A covered deposit starts as a request and warms up for a day before cover applies. After that,
 * anyone can call settle(user) to turn it into covered shares; see settleCall.
 */
export function coveredDepositCalls(opts: {
  stepwell: Address; user: Address; amount: bigint; appRef: string; asCover?: boolean;
}) {
  const inner = opts.asCover
    ? encodeFunctionData({ abi: stepwellAbi, functionName: "depositCover", args: [opts.amount, opts.user] })
    : encodeFunctionData({ abi: stepwellAbi, functionName: "requestDeposit", args: [opts.amount, opts.user, opts.user] });
  return [
    { target: ARC.usdc, allowFailure: false, callData: encodeFunctionData({ abi: erc20, functionName: "approve", args: [opts.stepwell, opts.amount] }) },
    { target: ARC.memo, allowFailure: false, callData: encodeFunctionData({ abi: memoAbi, functionName: "memo", args: [opts.stepwell, inner, keccak256(toHex(opts.appRef)), toHex(opts.appRef)] }) },
  ] as const;
}

/** Whether a user's request has warmed up, and the call that settles it (anyone may send it). */
export async function settleCall(client: PublicClient, stepwell: Address, user: Address) {
  const ready = await client.readContract({ address: stepwell, abi: stepwellAbi, functionName: "claimableDepositRequest", args: [0n, user] });
  return { ready: ready > 0n, call: { address: stepwell, abi: stepwellAbi, functionName: "settle" as const, args: [user] as const } };
}

/*
Example:

  const calls = coveredDepositCalls({ stepwell, user, amount: 5_000_000n, appRef: "my-wallet" });
  await wallet.writeContract({ address: ARC.multicall3From, abi: multicall3FromAbi, functionName: "aggregate3", args: [calls] });

  // a day later
  const { ready, call } = await settleCall(client, stepwell, user);
  if (ready) await wallet.writeContract(call);
*/
