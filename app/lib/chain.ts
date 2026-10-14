import { createPublicClient, http, formatUnits, type Address } from "viem";
import { arc, RPC_URL } from "./config";
import { stepwellAbi } from "./abi";

export const publicClient = createPublicClient({ chain: arc, transport: http(RPC_URL) });

export type Revision = { time: number; block: bigint; kind: number; amount: number; deep: number; cover: number };
export type WellState = {
  address: Address;
  covered: number;
  cover: number;
  settling: number;
  coverUnderNotice: number;
  coverDeficit: number;
  warmupSeconds: number;
  coverBps: number;
  premiumBps: number;
  floorBps: number;
  noticeSeconds: number;
  lossAbsorbed: number;
  lossPassedThrough: number;
  interestToCover: number;
  block: bigint;
  revisions: Revision[];
};

const usd = (v: bigint) => Number(formatUnits(v, 6));

export async function readWell(address: Address): Promise<WellState> {
  const [c, revs, block] = await Promise.all([
    publicClient.readContract({ address, abi: stepwellAbi, functionName: "coverage" }),
    publicClient.readContract({ address, abi: stepwellAbi, functionName: "revisions", args: [12n] }),
    publicClient.getBlockNumber(),
  ]);
  return {
    address,
    covered: usd(c.coveredAssets),
    cover: usd(c.coverAssets),
    settling: usd(c.settlingAssets),
    coverUnderNotice: usd(c.coverUnderNotice),
    coverDeficit: usd(c.coverDeficit),
    warmupSeconds: Number(c.warmupSeconds),
    coverBps: Number(c.coverBps),
    premiumBps: Number(c.premiumBps),
    floorBps: Number(c.floorBps),
    noticeSeconds: Number(c.noticeSeconds),
    lossAbsorbed: usd(c.lossAbsorbed),
    lossPassedThrough: usd(c.lossPassedThrough),
    interestToCover: usd(c.interestToCover),
    block,
    revisions: revs.map((r) => ({
      time: Number(r.time),
      block: r.blockNumber,
      kind: r.kind,
      amount: usd(r.amount),
      deep: usd(r.deep),
      cover: usd(r.cover),
    })),
  };
}

export const KIND_LABEL: Record<number, string> = {
  1: "Deposit requested, warming up",
  2: "Depositor left",
  3: "Underwriter put up cover",
  4: "Underwriter gave notice",
  5: "Underwriter left",
  6: "Interest booked, premium passed up",
  7: "Loss in the vault",
  8: "Cover used up and restarted",
  9: "Depositor left with vault shares",
  10: "Deposit warmed up, now covered",
  11: "Deposit request cancelled",
};
