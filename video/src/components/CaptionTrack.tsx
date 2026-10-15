// One caption at a time in its own band at the top: the voice's own words, each appearing as it
// is said (times in seconds from captions.json), the whole phrase gone before the next begins.
import React from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {EASE, tween} from '../lib/motion';

export type Caption = {tokens: Array<{text: string; t: number}>; end: number};

export const CaptionTrack: React.FC<{track: Caption[]; font: string; ink: string; band: string}> = ({track, font, ink, band}) => {
  const frame = useCurrentFrame();
  const {fps, width} = useVideoConfig();
  const t = frame / fps;
  const c = track.find((x) => t >= x.tokens[0].t - 0.05 && t < x.end);
  if (!c) return null;
  const s = width / 1920;
  const out = tween(t, c.end - 0.22, c.end, 1, 0, EASE.exit);
  const inn = tween(t, c.tokens[0].t - 0.05, c.tokens[0].t + 0.15, 0, 1, EASE.premium);
  return (
    <div style={{position: 'absolute', left: 0, right: 0, top: 44 * s, display: 'flex', justifyContent: 'center', zIndex: 80, opacity: Math.min(out, inn)}}>
      <div style={{padding: `${14 * s}px ${30 * s}px`, borderRadius: 999, background: band, boxShadow: `0 0 0 ${1 * s}px rgba(23,21,15,0.08), 0 ${10 * s}px ${30 * s}px -${14 * s}px rgba(23,16,14,0.35)`, display: 'flex', gap: `0 ${13 * s}px`, fontFamily: font, fontSize: 50 * s, fontWeight: 700, letterSpacing: '-0.025em', color: ink, lineHeight: 1.15}}>
        {c.tokens.filter((w) => t >= w.t - 0.04).map((w, i) => {
          const p = tween(t, w.t - 0.04, w.t + 0.16, 0, 1, EASE.premium);
          return <span key={i} style={{opacity: p, transform: `translateY(${(1 - p) * 10 * s}px)`, display: 'inline-block'}}>{w.text}</span>;
        })}
      </div>
    </div>
  );
};
