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

const factoryAbi = parseAbi([
  "struct Coverage { address underlying; uint256 coveredAssets; uint256 coverAssets; uint256 coverBps; uint256 premiumBps; uint256 floorBps; uint256 noticeSeconds; uint256 lossAbsorbed; uint256 lossPassedThrough; uint256 interestToCover; }",
  "function coverageFor(address vault) view returns (Coverage[])",
  "function stepwellsFor(address vault) view returns (address[])",
]);
const stepwellAbi = parseAbi([
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function depositCover(uint256 assets, address receiver) returns (uint256)",
  "function maxDeposit(address) view returns (uint256)",
]);
const erc20 = parseAbi(["function approve(address spender, uint256 amount) returns (bool)"]);
const memoAbi = parseAbi(["function memo(address target, bytes data, bytes32 memoId, bytes memoData)"]);
export const multicall3FromAbi = parseAbi([
  "function aggregate3((address target, bool allowFailure, bytes callData)[] calls) payable returns ((bool success, bytes returnData)[])",
]);

export type Coverage = {
  stepwell: Address; coveredUsdc: number; coverUsdc: number; coverPct: number; premiumPct: number; lossAbsorbedUsdc: number;
};

/** How well a vault is covered, across every Stepwell on it. Empty array: no cover. */
export async function coverageFor(client: PublicClient, factory: Address, vault: Address): Promise<Coverage[]> {
  const [list, cov] = await Promise.all([
    client.readContract({ address: factory, abi: factoryAbi, functionName: "stepwellsFor", args: [vault] }),
    client.readContract({ address: factory, abi: factoryAbi, functionName: "coverageFor", args: [vault] }),
  ]);
  return list.map((stepwell, i) => ({
    stepwell,
    coveredUsdc: Number(cov[i].coveredAssets) / 1e6,
    coverUsdc: Number(cov[i].coverAssets) / 1e6,
    coverPct: Number(cov[i].coverBps) / 100,
    premiumPct: Number(cov[i].premiumBps) / 100,
    lossAbsorbedUsdc: Number(cov[i].lossAbsorbed) / 1e6,
  }));
}

/**
 * The calls for a covered deposit (or for putting up cover) in one transaction from an ordinary
 * wallet: approve, then the deposit routed through Arc's Memo contract with your app's reference.
 * Send them with Multicall3From, which keeps the user as the sender of every call.
 */
export function coveredDepositCalls(opts: {
  stepwell: Address; user: Address; amount: bigint; appRef: string; asCover?: boolean;
}) {
  const inner = encodeFunctionData({
    abi: stepwellAbi,
    functionName: opts.asCover ? "depositCover" : "deposit",
    args: [opts.amount, opts.user],
  });
  return [
    { target: ARC.usdc, allowFailure: false, callData: encodeFunctionData({ abi: erc20, functionName: "approve", args: [opts.stepwell, opts.amount] }) },
    { target: ARC.memo, allowFailure: false, callData: encodeFunctionData({ abi: memoAbi, functionName: "memo", args: [opts.stepwell, inner, keccak256(toHex(opts.appRef)), toHex(opts.appRef)] }) },
  ] as const;
}

/*
Example:

  const calls = coveredDepositCalls({ stepwell, user, amount: 5_000_000n, appRef: "my-wallet" });
  await wallet.writeContract({ address: ARC.multicall3From, abi: multicall3FromAbi, functionName: "aggregate3", args: [calls] });
*/
