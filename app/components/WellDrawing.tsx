"use client";

import { useEffect, useMemo, useRef, useState } from "react";

/** A cross-section of a stepwell. The water's two bands are the two layers of money, and their
 *  areas are drawn to scale: the deep band is covered deposits, the surface band is cover. */

const W = 760, H = 470, G = 92, WALL = 632, FLOOR = 440, X0 = 96, TREAD = 42, RISER = 32, STEPS = 8;
const SHAFT_X = X0 + TREAD * STEPS;
const SHAFT_TOP = G + RISER * STEPS;

function leftAt(y: number) {
  if (y >= SHAFT_TOP) return SHAFT_X;
  const i = Math.floor((y - G) / RISER);
  return X0 + TREAD * Math.max(0, i);
}
function areaBelow(y: number) {
  let a = 0;
  for (let d = y; d < FLOOR; d += 0.5) a += (WALL - leftAt(d)) * 0.5;
  return a;
}
function band(yTop: number, yBot: number) {
  const pts: [number, number][] = [[WALL, yTop], [leftAt(yTop), yTop]];
  for (let i = 0; i <= STEPS; i++) {
    const d = G + RISER * i;
    if (d > yTop && d < yBot) { pts.push([leftAt(d - 0.01), d]); pts.push([leftAt(d + 0.01), d]); }
  }
  pts.push([leftAt(yBot - 0.01), yBot]);
  pts.push([WALL, yBot]);
  return pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ");
}
const PIT = (() => {
  const p: [number, number][] = [[X0, G]];
  for (let i = 0; i < STEPS; i++) { p.push([X0 + TREAD * i, G + RISER * (i + 1)]); p.push([X0 + TREAD * (i + 1), G + RISER * (i + 1)]); }
  p.push([SHAFT_X, FLOOR], [WALL, FLOOR], [WALL, G]);
  return p.map((q) => q.join(",")).join(" ");
})();
const money = (n: number) => "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default function WellDrawing({ covered, cover, scaleTotal, startTotal }: {
  covered: number; cover: number; scaleTotal: number; startTotal?: number;
}) {
  // the drawing's scale is fixed by scaleTotal so the water visibly moves when money moves
  const perDollar = useMemo(() => areaBelow(205) / Math.max(scaleTotal, 1e-9), [scaleTotal]);
  const levelFor = (dollars: number) => {
    let lo = G + 2, hi = FLOOR;
    for (let i = 0; i < 30; i++) { const mid = (lo + hi) / 2; if (areaBelow(mid) > dollars * perDollar) lo = mid; else hi = mid; }
    return (lo + hi) / 2;
  };
  const [shown, setShown] = useState({ s: covered, j: cover });
  const [phase, setPhase] = useState(0);
  const target = useRef({ s: covered, j: cover });
  target.current = { s: covered, j: cover };

  useEffect(() => {
    let raf = 0;
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    const tick = () => {
      setShown((st) => ({ s: st.s + (target.current.s - st.s) * 0.12, j: st.j + (target.current.j - st.j) * 0.12 }));
      if (!reduce) setPhase((p) => p + 0.035);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  const yS = levelFor(shown.s);
  const yT = levelFor(shown.s + shown.j);
  let wave = "";
  for (let x = leftAt(yT); x <= WALL; x += 8) wave += (wave ? "L" : "M") + x.toFixed(1) + " " + (yT + Math.sin(x / 21 + phase) * 1.3).toFixed(2);
  const y0 = startTotal ? levelFor(startTotal) : 0;
  const total = covered + cover;
  // a round number of dollars near a tenth of the well, drawn as a square of that area
  const squareDollars = (() => {
    const t = Math.max(scaleTotal / 10, 0.01), p = 10 ** Math.floor(Math.log10(t));
    return [1, 2, 5, 10].map((m) => m * p).reduce((a, b) => (Math.abs(b - t) < Math.abs(a - t) ? b : a));
  })();
  const side = Math.sqrt(squareDollars * perDollar);
  const fx = X0 + TREAD * 2 + 20, fy = G + RISER * 3;

  return (
    <svg className="well-figure" viewBox={`0 0 ${W} ${H}`} role="img"
      aria-label={`Section through a stepwell. Covered deposits ${money(covered)}, first-loss cover ${money(cover)}.`}>
      <defs>
        <pattern id="hatch" width="9" height="9" patternUnits="userSpaceOnUse" patternTransform="rotate(42)">
          <line x1="0" y1="0" x2="0" y2="9" stroke="var(--ink)" strokeWidth="0.9" opacity="0.28" />
        </pattern>
        <pattern id="ripple" width="46" height="15" patternUnits="userSpaceOnUse">
          <path d="M3 5h15M27 12h13" stroke="#fff" strokeWidth="0.9" opacity="0.28" fill="none" />
        </pattern>
        <filter id="rough" x="-2%" y="-2%" width="104%" height="104%">
          <feTurbulence type="fractalNoise" baseFrequency="0.03" numOctaves="2" seed="7" result="n" />
          <feDisplacementMap in="SourceGraphic" in2="n" scale="2.2" />
        </filter>
      </defs>
      <rect x="0" y={G} width={W} height={H - G} fill="var(--stone)" />
      <rect x="0" y={G} width={W} height={H - G} fill="url(#hatch)" />
      <polygon points={PIT} fill="var(--surface)" />
      <polygon points={band(yS, FLOOR)} fill="var(--water-deep)" />
      <polygon points={band(yS, FLOOR)} fill="url(#ripple)" />
      {shown.j > total * 0.002 && <polygon points={band(yT, yS)} fill="var(--water-surface)" />}
      {shown.j > total * 0.002 && <line x1={leftAt(yS)} x2={WALL} y1={yS} y2={yS} stroke="#fff" strokeWidth="1.2" strokeDasharray="7 5" opacity="0.85" />}
      <path d={wave} fill="none" stroke="var(--ink)" strokeWidth="1.3" />
      {startTotal && Math.abs(y0 - yT) > 3 && (
        <g>
          <line x1={leftAt(y0)} x2={WALL} y1={y0} y2={y0} stroke="var(--ink)" strokeWidth="1" strokeDasharray="2 5" opacity="0.55" />
          <text className="lbl" x={leftAt(y0) + 10} y={y0 - 6}>Where the water stood</text>
        </g>
      )}
      <g filter="url(#rough)" fill="none" stroke="var(--ink)" strokeLinejoin="round" strokeLinecap="round">
        <polyline points={`0,${G} ${PIT.split(" ").slice(0, -1).join(" ")} ${WALL},${G} ${W},${G}`} strokeWidth="2.1" />
        {Array.from({ length: Math.floor((FLOOR - G) / 22) }, (_, i) => (
          <line key={i} x1={WALL} y1={G + 22 * (i + 1)} x2={WALL + 9} y2={G + 22 * (i + 1)} strokeWidth="0.9" opacity="0.6" />
        ))}
        {[0, 1, 2, 3, 4].map((k) => {
          const px = SHAFT_X + 34, pw = WALL - px + 10, cx = px + k * (pw / 4);
          return <path key={k} d={`M${cx - 3} ${G}V${G - 44}M${cx + 3} ${G}V${G - 44}`} strokeWidth="1.3" />;
        })}
        <path d={`M${SHAFT_X + 24} ${G - 44}H${WALL + 54}M${SHAFT_X + 18} ${G - 50}H${WALL + 60}M${SHAFT_X + 42} ${G - 50}v-7h${WALL - SHAFT_X - 6}v7`} strokeWidth="1.5" />
        <path d={`M${(SHAFT_X + WALL) / 2 + 2} ${G - 57}q26 -24 52 0`} strokeWidth="1.5" />
        <circle cx={fx} cy={fy - 25} r="3.4" strokeWidth="1.4" />
        <path d={`M${fx} ${fy - 21}v12 M${fx} ${fy - 9}l-4 9 M${fx} ${fy - 9}l4 9 M${fx} ${fy - 18}l7 -6`} strokeWidth="1.4" />
        <path d={`M${fx + 5} ${fy - 33}h7l-1.2 6h-4.6z`} strokeWidth="1.2" />
      </g>
      <text className="lbl" x={X0 - 4} y={G - 14}>Fig. 1 · underwriter, for scale</text>
      <path d={`M${X0 + 66} ${G - 10}L${fx - 3} ${fy - 40}`} stroke="var(--ink)" strokeWidth="0.8" fill="none" opacity="0.7" />
      <text className="lbl" x="16" y="24">Section A–A′</text>

      <rect x="14" y={FLOOR - 64} width="168" height={side + 36} fill="var(--surface)" opacity="0.94" />
      <rect x="24" y={FLOOR - 54} width={side} height={side} fill="var(--water-deep)" stroke="var(--ink)" strokeWidth="1" />
      <text className="lbl" x={24 + side + 9} y={FLOOR - 54 + side / 2 + 4}>This square is {money(squareDollars).replace(/\.00$/, "")}</text>

      <g>
        <text className="lbl" x="250" y="124">First-loss cover</text>
        <text className="val" x="250" y="144">{money(cover)}</text>
        <path d={`M254 151V${shown.j > total * 0.002 ? (yT + yS) / 2 : yT}`} stroke="var(--ink)" strokeWidth="0.9" fill="none" />
        <circle cx="254" cy={shown.j > total * 0.002 ? (yT + yS) / 2 : yT} r="2.6" fill="var(--ink)" />
        <text className="lbl" x="376" y="124">Covered deposits</text>
        <text className="val" x="376" y="144">{money(covered)}</text>
        <path d={`M380 151V${Math.min(FLOOR - 14, yS + 34)}`} stroke="var(--ink)" strokeWidth="0.9" fill="none" />
        <circle cx="380" cy={Math.min(FLOOR - 14, yS + 34)} r="2.6" fill="#fff" />
      </g>
      {shown.j > total * 0.002 && (
        <g>
          <path d={`M${WALL + 79} ${yT}H${WALL + 84}V${yS}H${WALL + 79}`} stroke="var(--water-deep)" strokeWidth="1.6" fill="none" />
          <text className="lbl" x={WALL + 20} y={Math.min(yT, yS) - 9} style={{ fill: "var(--water-deep)" }}>
            Cover {total > 0 ? ((100 * cover) / total).toFixed(1) : "0.0"}%
          </text>
        </g>
      )}
    </svg>
  );
}
