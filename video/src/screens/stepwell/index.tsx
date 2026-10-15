// Stepwell's screens, rebuilt from the live site (stepwell-one.vercel.app) so every number can move.
// Figures match the README and the tests; the savings card and receipts are illustrative.
import React from 'react';
import {EASE, tween, clamp01, keys, ms} from '../../lib/motion';
import {ScreenProps} from '../types';
import {Marker} from '../../components/Type';
import {Cursor, Check} from '../../components/UI';

export const C = {
  bg: '#FAF6EF', surface: '#FFFEFC', ink: '#17150F', ink2: '#423C33', muted: '#6D6459', faint: '#857B6E',
  line: '#EBE3D7', line2: '#DDD2C2', well: '#1E5B4F', water: '#7FB3A2', stone: '#E9DCC4', red: '#A1411F',
  wash: '#E3ECE4', sunk: '#F3ECE1', code: '#1B1916', darkInk: '#F3ECE1',
};
const D = 'Plus Jakarta Sans', M = 'Geist Mono', S = 'Eczar';

type At = string | number | undefined;
const atF = (p: ScreenProps, a: At, fb = 0) => (a === undefined ? p.b(fb) : typeof a === 'string' ? p.ev(a, fb) : p.b(a));
const usd = (n: number, d = 2) => n.toLocaleString('en-US', {minimumFractionDigits: d, maximumFractionDigits: d});
const fadeUp = (f: number, f0: number, fps: number, dy = 18): React.CSSProperties => {
  const t = tween(f, f0, f0 + ms(fps, 520), 0, 1, EASE.premium);
  return {opacity: t, transform: `translateY(${(1 - t) * dy}px)`};
};
const eyebrow: React.CSSProperties = {fontFamily: D, fontSize: 19, fontWeight: 650, letterSpacing: '0.11em', textTransform: 'uppercase', color: C.muted};
const box: React.CSSProperties = {width: '100%', height: '100%', background: C.surface, fontFamily: D, color: C.ink, position: 'relative', overflow: 'hidden'};

/** A savings balance in a vault, which drops when bad debt is booked. lw 900 × lh 560. */
export const SwSavings: React.FC<ScreenProps & {drop?: At}> = (p) => {
  const d = atF(p, p.drop, 99);
  const v = tween(p.f, d, d + ms(p.fps, 900), 1000, 920, EASE.premium);
  const hit = tween(p.f, d, d + ms(p.fps, 300), 0, 1, EASE.premium);
  return (
    <div style={{...box, padding: '54px 60px'}}>
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
        <div style={eyebrow}>Earn · Morpho vault on Arc</div>
        <div style={{fontFamily: M, fontSize: 20, color: C.muted}}>3.1% a year</div>
      </div>
      <div style={{marginTop: 60, fontSize: 24, color: C.muted, fontWeight: 600}}>Your balance</div>
      <div style={{display: 'flex', alignItems: 'baseline', gap: 22, marginTop: 6}}>
        <div style={{fontSize: 132, fontWeight: 750, letterSpacing: '-0.045em', fontVariantNumeric: 'tabular-nums', color: hit > 0.5 ? C.red : C.ink, lineHeight: 1}}>
          {usd(v)}
        </div>
        <div style={{fontSize: 34, fontWeight: 700, color: C.muted}}>USDC</div>
      </div>
      <div style={{position: 'absolute', left: 60, right: 60, bottom: 54, display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
        <div style={{fontSize: 22, color: C.ink2, opacity: hit, display: 'flex', alignItems: 'center', gap: 12}}>
          <span style={{width: 12, height: 12, borderRadius: 6, background: C.red}} />Vault booked bad debt
        </div>
        <div style={{opacity: hit, transform: `scale(${0.8 + 0.2 * hit})`, padding: '10px 20px', borderRadius: 99, background: '#F6E3DA', color: C.red, fontWeight: 750, fontSize: 26}}>−8.00%</div>
      </div>
    </div>
  );
};

// ---------- the stepwell section, frame-driven ----------
const W = 760, H = 470, G = 92, WALL = 632, FLOOR = 440, X0 = 96, TREAD = 42, RISER = 32, STEPS = 8;
const SHAFT_X = X0 + TREAD * STEPS, SHAFT_TOP = G + RISER * STEPS;
const leftAt = (y: number) => (y >= SHAFT_TOP ? SHAFT_X : X0 + TREAD * Math.max(0, Math.floor((y - G) / RISER)));
const areaBelow = (y: number) => { let a = 0; for (let d = y; d < FLOOR; d += 1) a += WALL - leftAt(d); return a; };
const band = (yTop: number, yBot: number) => {
  const pts: [number, number][] = [[WALL, yTop], [leftAt(yTop), yTop]];
  for (let i = 0; i <= STEPS; i++) { const d = G + RISER * i; if (d > yTop && d < yBot) { pts.push([leftAt(d - 0.01), d], [leftAt(d + 0.01), d]); } }
  pts.push([leftAt(yBot - 0.01), yBot], [WALL, yBot]);
  return pts.map((q) => q[0].toFixed(1) + ',' + q[1].toFixed(1)).join(' ');
};
const PIT = (() => {
  const q: [number, number][] = [[X0, G]];
  for (let i = 0; i < STEPS; i++) q.push([X0 + TREAD * i, G + RISER * (i + 1)], [X0 + TREAD * (i + 1), G + RISER * (i + 1)]);
  q.push([SHAFT_X, FLOOR], [WALL, FLOOR], [WALL, G]);
  return q.map((r) => r.join(',')).join(' ');
})();
const A190 = areaBelow(190); // the drawing's scale: `scale` dollars fill the well to y=190
const levelFor = (dollars: number, scale: number) => { const per = A190 / scale; let lo = G + 2, hi = FLOOR; for (let i = 0; i < 26; i++) { const m = (lo + hi) / 2; if (areaBelow(m) > dollars * per) lo = m; else hi = m; } return (lo + hi) / 2; };

/** The section drawing. keys: [[at, covered, cover], ...] eased between. lw 1100 × lh 680. */
export const SwWell: React.FC<ScreenProps & {keys: Array<[string | number, number, number]>; labels?: boolean; scale?: number; callout?: [At, At, string, string]}> = (p) => {
  const sc = p.scale ?? 1000;
  const ks = p.keys.map(([a, s, j]) => [atF(p, a), s, j] as [number, number, number]);
  const dur = ms(p.fps, 1100);
  let s = ks[0][1], j = ks[0][2], drain = 0, rain = 0;
  for (let i = 1; i < ks.length; i++) {
    const t = tween(p.f, ks[i][0], ks[i][0] + dur, 0, 1, EASE.move);
    if (t > 0) { s = ks[i - 1][1] + (ks[i][1] - ks[i - 1][1]) * t; j = ks[i - 1][2] + (ks[i][2] - ks[i - 1][2]) * t; }
    const win = tween(p.f, ks[i][0] - ms(p.fps, 150), ks[i][0] + dur + ms(p.fps, 500), 0, 1, EASE.linear);
    const bell = win > 0 && win < 1 ? Math.sin(Math.PI * win) : 0;
    if (ks[i][2] < ks[i - 1][2]) drain = Math.max(drain, bell);
    if (ks[i][2] > ks[i - 1][2]) rain = Math.max(rain, bell);
  }
  const yS = levelFor(s, sc), yT = levelFor(s + j, sc);
  let wave = '';
  for (let x = leftAt(yT); x <= WALL; x += 8) wave += (wave ? 'L' : 'M') + x.toFixed(1) + ' ' + (yT + Math.sin(x / 21 + p.f * 0.06) * 1.3).toFixed(2);
  const hasJ = j > 0.5;
  const lbl: React.CSSProperties = {font: `600 13px ${M}`, letterSpacing: '0.08em', textTransform: 'uppercase', fill: C.muted};
  const val: React.CSSProperties = {font: `700 24px ${D}`, letterSpacing: '-0.02em', fill: C.ink};
  return (
    <div style={{...box, background: C.surface, display: 'grid', placeItems: 'center'}}>
      <svg viewBox={`0 0 ${W} ${H}`} style={{width: '94%', height: 'auto', maxHeight: '94%'}}>
        <defs>
          <pattern id="sw-hatch" width="9" height="9" patternUnits="userSpaceOnUse" patternTransform="rotate(42)">
            <line x1="0" y1="0" x2="0" y2="9" stroke={C.ink} strokeWidth="0.9" opacity="0.26" />
          </pattern>
        </defs>
        <rect x="0" y={G} width={W} height={H - G} fill={C.stone} />
        <rect x="0" y={G} width={W} height={H - G} fill="url(#sw-hatch)" />
        <polygon points={PIT} fill={C.surface} />
        <polygon points={band(yS, FLOOR)} fill={C.well} />
        {hasJ && <polygon points={band(yT, yS)} fill={C.water} />}
        {hasJ && drain > 0 && <polygon points={band(yT, yS)} fill="#C2542A" opacity={0.75 * drain} />}
        {rain > 0 && Array.from({length: 16}, (_, k) => {
          const x = SHAFT_X - 150 + ((k * 53) % 300), ph = ((p.f * 9 + k * 41) % 170);
          return <line key={k} x1={x} x2={x - 3} y1={G - 70 + ph} y2={G - 56 + ph} stroke={C.well} strokeWidth="2" strokeLinecap="round" opacity={rain * (ph < 150 ? 0.7 : 0)} />;
        })}
        {hasJ && <line x1={leftAt(yS)} x2={WALL} y1={yS} y2={yS} stroke="#fff" strokeWidth="1.2" strokeDasharray="7 5" opacity="0.85" />}
        <path d={wave} fill="none" stroke={C.ink} strokeWidth="1.3" />
        <g fill="none" stroke={C.ink} strokeLinejoin="round" strokeLinecap="round">
          <polyline points={`0,${G} ${PIT.split(' ').slice(0, -1).join(' ')} ${WALL},${G} ${W},${G}`} strokeWidth="2.1" />
          {[0, 1, 2, 3, 4].map((k) => { const px = SHAFT_X + 34, pw = WALL - px + 10, cx = px + k * (pw / 4); return <path key={k} d={`M${cx - 3} ${G}V${G - 44}M${cx + 3} ${G}V${G - 44}`} strokeWidth="1.3" />; })}
          <path d={`M${SHAFT_X + 24} ${G - 44}H${WALL + 54}M${SHAFT_X + 18} ${G - 50}H${WALL + 60}M${SHAFT_X + 42} ${G - 50}v-7h${WALL - SHAFT_X - 6}v7`} strokeWidth="1.5" />
          <path d={`M${(SHAFT_X + WALL) / 2 + 2} ${G - 57}q26 -24 52 0`} strokeWidth="1.5" />
        </g>
        {p.callout && (() => {
          const [ca, cu, l1, l2] = p.callout;
          const o = Math.min(tween(p.f, atF(p, ca), atF(p, ca) + ms(p.fps, 400), 0, 1, EASE.premium), tween(p.f, atF(p, cu) - ms(p.fps, 250), atF(p, cu), 1, 0, EASE.exit));
          if (o <= 0 || !hasJ) return null;
          const ym = (yT + yS) / 2;
          return (
            <g opacity={o}>
              <path d={`M${WALL + 8} ${yT + 1}h10V${yS - 1}h-10`} stroke={C.red} strokeWidth="2" fill="none" />
              <text style={{font: `700 15px ${D}`, fill: C.red}} x={WALL + 26} y={ym - 3}>{l1}</text>
              <text style={{font: `700 15px ${D}`, fill: C.red}} x={WALL + 26} y={ym + 15}>{l2}</text>
            </g>
          );
        })()}
        {p.labels !== false && (
          <g>
            <text style={lbl} x="238" y="122">First-loss cover</text>
            <text style={val} x="238" y="148">${usd(j)}</text>
            <path d={`M242 156V${hasJ ? (yT + yS) / 2 : yT}`} stroke={C.ink} strokeWidth="0.9" fill="none" />
            <circle cx="242" cy={hasJ ? (yT + yS) / 2 : yT} r="3" fill={C.ink} />
            <text style={lbl} x="420" y="122">Covered deposits</text>
            <text style={val} x="420" y="148">${usd(s)}</text>
            <path d={`M424 156V${Math.min(FLOOR - 14, yS + 34)}`} stroke={C.ink} strokeWidth="0.9" fill="none" />
            <circle cx="424" cy={Math.min(FLOOR - 14, yS + 34)} r="3" fill="#fff" stroke={C.ink} strokeWidth="0.8" />
          </g>
        )}
      </svg>
    </div>
  );
};

/** Arc's request for builders, with the matching phrases highlighted. lw 1240 × lh 560. */
export const SwQuote: React.FC<ScreenProps & {m1?: At; m2?: At}> = (p) => {
  const m1 = atF(p, p.m1, 3), m2 = atF(p, p.m2, 6);
  const hl = 'rgba(127,179,162,0.45)';
  return (
    <div style={{...box, padding: '64px 72px'}}>
      <div style={eyebrow}>Arc · Request for builders</div>
      <div style={{marginTop: 34, fontSize: 46, lineHeight: 1.32, fontWeight: 600, letterSpacing: '-0.02em', color: C.ink2}}>
        “Bundle smart-contract, <Marker f={p.f} at={m1} color={hl}><b style={{color: C.ink}}>vault-loss</b></Marker> or collateral-risk <Marker f={p.f} at={m1 + 6} color={hl}><b style={{color: C.ink}}>protection</b></Marker> directly into USDC <Marker f={p.f} at={m1 + 12} color={hl}><b style={{color: C.ink}}>deposit</b></Marker> and lending flows, with <Marker f={p.f} at={m2} color={hl}><b style={{color: C.ink}}>premiums netted from yield</b></Marker>…”
      </div>
    </div>
  );
};

/** Where the interest goes: 3.12% splits into 2.34% kept and 0.78% to cover. lw 1100 × lh 520. */
export const SwSplit: React.FC<ScreenProps & {split?: At}> = (p) => {
  const t = tween(p.f, atF(p, p.split, 2), atF(p, p.split, 2) + ms(p.fps, 900), 0, 1, EASE.move);
  const keep = 1 - 0.25 * t;
  return (
    <div style={{...box, padding: '58px 64px'}}>
      <div style={eyebrow}>Where the interest goes · 15% cover</div>
      <div style={{marginTop: 40, display: 'flex', height: 120, borderRadius: 20, overflow: 'hidden', boxShadow: `inset 0 0 0 1px ${C.line2}`}}>
        <div style={{width: `${keep * 100}%`, background: C.well, color: '#fff', display: 'flex', alignItems: 'center', padding: '0 30px', fontSize: 34, fontWeight: 700}}>
          {t < 0.5 ? 'The vault pays 3.12%' : 'You keep 2.34%'}
        </div>
        <div style={{flex: 1, background: C.water, color: C.ink, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 30, fontWeight: 700, opacity: t}}>0.78%</div>
      </div>
      <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 26, fontSize: 25, color: C.ink2, ...fadeUp(p.f, atF(p, p.split, 2) + ms(p.fps, 700), p.fps, 10)}}>
        <span>Depositors keep most of it</span><span>A quarter buys the cover</span>
      </div>
      <div style={{position: 'absolute', left: 64, bottom: 54, fontSize: 28, fontWeight: 700, color: C.well, ...fadeUp(p.f, atF(p, p.split, 2) + ms(p.fps, 1200), p.fps)}}>
        Nothing paid out of pocket.
      </div>
    </div>
  );
};

/** The worked table from the README. lw 1000 × lh 560. */
export const SwTable: React.FC<ScreenProps & {loss?: At; back?: At}> = (p) => {
  const rows: Array<[string, string, string, number, boolean]> = [
    ['Start', '850.00', '150.00', p.b(0), false],
    ['Vault loses 8%', '850.00', '70.00', atF(p, p.loss, 2), true],
    ['Money comes back', '850.00', '150.00', atF(p, p.back, 6), false],
  ];
  return (
    <div style={{...box, padding: '50px 56px'}}>
      <div style={{display: 'grid', gridTemplateColumns: '1.5fr 1fr 1fr', fontFamily: M, fontSize: 17, letterSpacing: '0.08em', textTransform: 'uppercase', color: C.muted, paddingBottom: 18, borderBottom: `1.5px solid ${C.line2}`}}>
        <span /> <span style={{textAlign: 'right'}}>Covered</span><span style={{textAlign: 'right'}}>Cover</span>
      </div>
      {rows.map(([k, a, c, f0, bad], i) => (
        <div key={i} style={{display: 'grid', gridTemplateColumns: '1.5fr 1fr 1fr', alignItems: 'center', padding: '30px 0', borderBottom: `1px solid ${C.line}`, fontSize: 34, fontVariantNumeric: 'tabular-nums', ...fadeUp(p.f, f0, p.fps, 14)}}>
          <span style={{fontSize: 28, color: C.ink2, fontWeight: 600}}>{k}</span>
          <span style={{textAlign: 'right', fontWeight: 700, color: i === 0 ? C.ink : C.well}}>{a}</span>
          <span style={{textAlign: 'right', fontWeight: 700, color: bad ? C.red : C.ink}}>{c}</span>
        </div>
      ))}
    </div>
  );
};

/** Two guards against gaming. lw 1300 × lh 560. */
export const SwGuards: React.FC<ScreenProps & {g1?: At; g2?: At}> = (p) => {
  const g1 = atF(p, p.g1, 2), g2 = atF(p, p.g2, 6);
  const card = (f0: number, kicker: string, title: string, rows: Array<[string, string]>, bar: number) => (
    <div style={{flex: 1, background: C.surface, borderRadius: 26, boxShadow: `0 0 0 1px ${C.line}, 0 24px 60px -24px rgba(23,16,14,0.25)`, padding: '40px 42px', ...fadeUp(p.f, f0, p.fps, 30)}}>
      <div style={eyebrow}>{kicker}</div>
      <div style={{marginTop: 14, fontSize: 46, fontWeight: 750, letterSpacing: '-0.035em'}}>{title}</div>
      <div style={{marginTop: 26, height: 12, borderRadius: 6, background: C.sunk, overflow: 'hidden'}}>
        <div style={{height: '100%', width: `${bar * 100}%`, background: C.well, borderRadius: 6}} />
      </div>
      {rows.map(([k, v], i) => (
        <div key={i} style={{display: 'flex', justifyContent: 'space-between', marginTop: 20, fontSize: 25, color: C.ink2, ...fadeUp(p.f, f0 + ms(p.fps, 500 + i * 260), p.fps, 8)}}>
          <span>{k}</span><b style={{color: v.startsWith('Still') ? C.red : C.ink}}>{v}</b>
        </div>
      ))}
    </div>
  );
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', gap: 36, alignItems: 'center', fontFamily: D, color: C.ink}}>
      {card(g1, 'Depositors', 'One-day warm-up', [['Covered from', 'Day 2'], ['Buying cover after bad news', 'Too late']], tween(p.f, g1, g1 + ms(p.fps, 1600), 0, 1, EASE.camera))}
      {card(g2, 'Underwriters', "Three days' notice", [['Earning while leaving', 'Stopped'], ['Losses while leaving', 'Still carried']], tween(p.f, g2, g2 + ms(p.fps, 1600), 0, 0.66, EASE.camera))}
    </div>
  );
};

/** One signature in a wallet, and one read for any app. lw 1400 × lh 640. */
export const SwSign: React.FC<ScreenProps & {click?: At; code?: At}> = (p) => {
  const click = atF(p, p.click, 3), code = atF(p, p.code, 7);
  const done = p.f >= click + 4;
  const steps = ['Approve 5.00 USDC', 'Request a covered deposit', 'Tag it: ref = your-app'];
  const codeLines: Array<[string, string]> = [
    ['k', 'factory.standardCoverageFor(vault)'],
    ['c', '// → for every Stepwell on that vault'],
    ['s', 'cover          15.0%'],
    ['s', 'covered        $4.25'],
    ['s', 'cover leaving  $0.00'],
  ];
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', gap: 40, alignItems: 'center', fontFamily: D, color: C.ink}}>
      <div style={{width: 560, background: C.surface, borderRadius: 28, boxShadow: `0 0 0 1px ${C.line}, 0 30px 70px -26px rgba(23,16,14,0.3)`, padding: '38px 40px', position: 'relative'}}>
        <div style={eyebrow}>Wallet · Arc</div>
        <div style={{marginTop: 12, fontSize: 40, fontWeight: 750, letterSpacing: '-0.035em'}}>Confirm 1 transaction</div>
        {steps.map((s, i) => (
          <div key={i} style={{display: 'flex', gap: 16, alignItems: 'center', marginTop: 22, fontSize: 24, color: C.ink2}}>
            <span style={{width: 34, height: 34, borderRadius: 17, background: C.wash, color: C.well, display: 'grid', placeItems: 'center', fontWeight: 750, fontSize: 18}}>{i + 1}</span>{s}
          </div>
        ))}
        <div style={{marginTop: 34, height: 64, borderRadius: 32, background: done ? C.well : C.ink, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12, fontSize: 24, fontWeight: 700}}>
          {done ? <><Check f={p.f} at={click + 4} size={30} bg="transparent" />Signed once</> : 'Confirm'}
        </div>
        <Cursor f={p.f} path={[[click - ms(p.fps, 900), 520, 470], [click, 300, 420]]} clicks={[click]} showFrom={click - ms(p.fps, 900)} size={34} />
      </div>
      <div style={{flex: 1, background: C.code, borderRadius: 28, padding: '40px 42px', fontFamily: M, fontSize: 25, lineHeight: 1.75, ...fadeUp(p.f, code, p.fps, 24)}}>
        {codeLines.map(([k, t], i) => (
          <div key={i} style={{color: k === 'k' ? '#f0c58a' : k === 'c' ? '#8d8576' : '#a8d5c2', opacity: clamp01(tween(p.f, code + ms(p.fps, 200 + i * 220), code + ms(p.fps, 420 + i * 220)))}}>{t}</div>
        ))}
      </div>
    </div>
  );
};

/** The fork test on Arc mainnet state. lw 1300 × lh 560. */
export const SwFork: React.FC<ScreenProps & {at?: At}> = (p) => {
  const a = atF(p, p.at, 0.5);
  const lines: Array<[string, string]> = [
    ['#8d8576', '$ FORK=1 arc-forge test --match-contract Fork'],
    ['#e9e4da', 'Steakhouse adapter marks its assets down 2%'],
    ['#a8d5c2', '[PASS] test_fork_morphoBadDebtIsBookedAsLoss()'],
    ['#e9e4da', '  loss absorbed by cover      4.0 USDC'],
    ['#e9e4da', '  loss reaching depositors    0.0 USDC'],
  ];
  return (
    <div style={{width: '100%', height: '100%', background: C.code, borderRadius: 28, padding: '52px 56px', fontFamily: M, fontSize: 30, lineHeight: 1.85, overflow: 'hidden'}}>
      <div style={{display: 'flex', gap: 10, marginBottom: 26}}>{['#e5675b', '#f0b54b', '#5fbf6a'].map((c) => <span key={c} style={{width: 15, height: 15, borderRadius: 8, background: c}} />)}</div>
      {lines.map(([c, t], i) => {
        const f0 = a + ms(p.fps, i * 900);
        const n = Math.floor(tween(p.f, f0, f0 + ms(p.fps, i === 0 ? 900 : 300), 0, t.length, EASE.linear));
        return <div key={i} style={{color: c, whiteSpace: 'pre', fontWeight: i >= 3 ? 600 : 400}}>{t.slice(0, n)}</div>;
      })}
    </div>
  );
};

/** One tile per test, flipping green in a wave. lw 1300 × lh 560. */
export const SwTests: React.FC<ScreenProps & {at?: At}> = (p) => {
  const a = atF(p, p.at, 0.5);
  const groups: Array<[string, number]> = [['Unit and fuzz', 27], ['Invariants', 5], ['On Arc mainnet state', 3], ['Symbolic proofs', 4]];
  let k = 0;
  return (
    <div style={{...box, padding: '46px 54px', display: 'flex', flexDirection: 'column', gap: 26}}>
      {groups.map(([name, n]) => (
        <div key={name}>
          <div style={{fontSize: 22, fontWeight: 650, color: C.ink2, marginBottom: 12}}>{name} <span style={{color: C.muted, fontFamily: M}}>· {n}</span></div>
          <div style={{display: 'flex', gap: 10, flexWrap: 'wrap'}}>
            {Array.from({length: n}, () => {
              const f0 = a + ms(p.fps, (k++) * 55);
              const t = tween(p.f, f0, f0 + ms(p.fps, 260), 0, 1, EASE.premium);
              return <span key={k} style={{width: 34, height: 34, borderRadius: 9, background: t > 0.5 ? C.well : C.line, transform: `rotateY(${(1 - t) * 180}deg)`, display: 'grid', placeItems: 'center', color: '#fff', fontSize: 18, fontWeight: 800}}>{t > 0.5 ? '✓' : ''}</span>;
            })}
          </div>
        </div>
      ))}
    </div>
  );
};

/** The live site's "Go on, break it." panel with the well beside it. lw 1400 × lh 700. */
export const SwLive: React.FC<ScreenProps & {click?: At}> = (p) => {
  const click = atF(p, p.click, 3);
  const pressed = p.f >= click;
  const res = tween(p.f, click + ms(p.fps, 500), click + ms(p.fps, 1300), 0, 1, EASE.move);
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', gap: 34, fontFamily: D, color: C.ink}}>
      <div style={{width: 640, background: C.surface, borderRadius: 30, boxShadow: `0 0 0 1px ${C.line}, 0 30px 70px -26px rgba(23,16,14,0.3)`, padding: '44px 44px', position: 'relative'}}>
        <div style={{...eyebrow, fontSize: 17, display: 'flex', alignItems: 'center', gap: 10}}><span style={{width: 8, height: 8, borderRadius: 4, background: C.well}} />Real transactions on Arc</div>
        <div style={{marginTop: 16, fontSize: 52, fontWeight: 750, letterSpacing: '-0.04em'}}>Go on, break it.</div>
        <div style={{marginTop: 14, fontSize: 23, lineHeight: 1.5, color: C.ink2}}>The button makes a small test vault send 8% of its money away, exactly how bad debt looks from outside.</div>
        <div style={{marginTop: 30, display: 'inline-flex', height: 64, padding: '0 30px', alignItems: 'center', borderRadius: 32, background: C.well, color: '#fff', fontSize: 23, fontWeight: 700, transform: `scale(${pressed && p.f < click + 6 ? 0.96 : 1})`}}>Simulate an 8% vault loss</div>
        <div style={{marginTop: 26, padding: '14px 18px', borderRadius: 12, background: C.sunk, fontFamily: M, fontSize: 21, lineHeight: 1.5, color: C.ink2, opacity: res}}>
          <div><b style={{color: C.ink}}>$0.25 lost · $0.25 from cover</b></div><div>tx 0x684d7d…a76f42 · final in 4.63 s</div>
        </div>
        <div style={{position: 'absolute', right: 26, top: 26, padding: '8px 14px', borderRadius: 99, background: C.well, color: '#fff', fontSize: 16, fontWeight: 700, opacity: res, transform: `scale(${0.85 + 0.15 * res})`}}>Real run · Arc mainnet</div>
        <Cursor f={p.f} path={[[click - ms(p.fps, 1000), 520, 620], [click, 240, 372], [click + ms(p.fps, 700), 560, 640]]} clicks={[click]} showFrom={click - ms(p.fps, 1000)} size={34} />
      </div>
      <div style={{flex: 1, borderRadius: 30, overflow: 'hidden', boxShadow: `0 0 0 1px ${C.line}, 0 30px 70px -26px rgba(23,16,14,0.3)`}}>
        <SwWell {...p} scale={3.3} keys={[[0, 2.5, 0.62], [click / (p.b(1) - p.b(0)) + 1, 2.5, 0.37]]} />
      </div>
    </div>
  );
};

import VAULTS from './vaults.json';

/** Morpho vaults on Arc over $10k, as blocks sized by deposits (Morpho API). lw 1500 × lh 760. */
export const SwVaults: React.FC<ScreenProps & {count?: At; mark?: At}> = (p) => {
  const vs = VAULTS as Array<[string, string, number, number]>;
  const total = vs.reduce((a, v) => a + v[2], 0);
  const c0 = atF(p, p.count, 0.5), mk = atF(p, p.mark, 8);
  const shown = tween(p.f, c0, c0 + ms(p.fps, 1600), 0, total / 1e6, EASE.enter);
  const big = vs.slice(0, 2), rest = vs.slice(2), restSum = rest.reduce((a, v) => a + v[2], 0);
  const tones = [C.well, '#2F7B69', C.water];
  const blocks: Array<[string, number, string, number]> = [[big[0][0], big[0][2], tones[0], 0], [big[1][0], big[1][2], tones[1], 1], [`${rest.length} more`, restSum, tones[2], 2]];
  const W0 = 860, H0 = 600;
  const steak = rest.find((v) => v[0].startsWith('Steakhouse'));
  const mo = tween(p.f, mk, mk + ms(p.fps, 500), 0, 1, EASE.premium);
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', gap: 60, alignItems: 'center', fontFamily: D, color: C.darkInk ?? '#F3ECE1'}}>
      <div style={{width: 520}}>
        <div style={{fontSize: 124, fontWeight: 750, letterSpacing: '-0.05em', lineHeight: 1, color: '#F3ECE1', fontVariantNumeric: 'tabular-nums'}}>${shown.toFixed(1)}M</div>
        <div style={{marginTop: 18, fontSize: 32, fontWeight: 600, color: '#F3ECE1', ...fadeUp(p.f, c0 + ms(p.fps, 1200), p.fps, 10)}}>in Morpho vaults on Arc</div>
        <div style={{marginTop: 10, fontSize: 22, color: 'rgba(243,236,225,0.6)', fontFamily: M, ...fadeUp(p.f, c0 + ms(p.fps, 1500), p.fps, 10)}}>{vs.length} vaults over $10k · Morpho API</div>
      </div>
      <div style={{position: 'relative', width: W0, height: H0, display: 'flex', gap: 8, alignItems: 'flex-end'}}>
        {blocks.map(([name, v, col, i]) => {
          const g = tween(p.f, c0 + ms(p.fps, 220 * i), c0 + ms(p.fps, 220 * i + 900), 0, 1, EASE.premium);
          const w = Math.max(70, (W0 - 16) * (v / total));
          return (
            <div key={name} style={{width: w, height: H0, background: col, borderRadius: 18, transformOrigin: 'bottom', transform: `scaleY(${g})`, padding: i < 2 ? '24px 26px' : 0, color: '#fff', boxSizing: 'border-box', overflow: 'hidden'}}>
              {i < 2 ? <><div style={{fontSize: 26, fontWeight: 700}}>{name}</div><div style={{fontSize: 22, opacity: 0.8, marginTop: 6, fontFamily: M}}>${(v / 1e6).toFixed(1)}M</div></> : null}
            </div>
          );
        })}
        {steak ? (
          <div style={{position: 'absolute', right: -6, bottom: -92, width: 520, textAlign: 'right', opacity: mo, transform: `translateY(${(1 - mo) * 12}px)`}}>
            <div style={{fontSize: 28, fontWeight: 700, color: '#F3ECE1'}}>{steak[0]} · ${(steak[2] / 1e6).toFixed(1)}M</div>
            <div style={{fontSize: 23, color: C.water, marginTop: 6}}>↑ where Stepwell's real well sits</div>
          </div>
        ) : null}
      </div>
    </div>
  );
};

export const MARK_SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96"><rect width="96" height="96" rx="22" fill="#FAF6EF"/><path d="M16 26h12v8h8v8h8v8h8v10" fill="none" stroke="#17150F" stroke-width="6" stroke-linejoin="miter"/><path d="M28 26v48h48V26h10" fill="none" stroke="#17150F" stroke-width="6"/><rect x="31" y="60" width="42" height="11" fill="#1E5B4F"/><rect x="55" y="51" width="18" height="9" fill="#7FB3A2"/></svg>';

export const SCREENS_STEPWELL = {SwVaults, SwSavings, SwWell, SwQuote, SwSplit, SwTable, SwGuards, SwSign, SwFork, SwTests, SwLive};
