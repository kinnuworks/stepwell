// One caption at a time, plain type in its own band at the top: the voice's own words, each
// appearing as it is said (times in seconds from captions.json), one word set in italic serif.
// Each caption holds until the next one takes its place, with a quick fade between them. Light ink over the dark scenes.
import React from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {EASE, tween} from '../lib/motion';

export type Caption = {tokens: Array<{text: string; t: number; em?: boolean}>; end: number};

export const CaptionTrack: React.FC<{track: Caption[]; font: string; serif: string; ink: string; darkInk: string; dark: Array<[number, number]>}> = ({track, font, serif, ink, darkInk, dark}) => {
  const frame = useCurrentFrame();
  const {fps, width} = useVideoConfig();
  const t = frame / fps;
  const c = track.find((x) => t >= x.tokens[0].t - 0.05 && t < x.end);
  if (!c) return null;
  const s = width / 1920;
  const onDark = dark.some(([a, b]) => t >= a && t < b);
  const out = tween(t, c.end - 0.22, c.end, 1, 0, EASE.exit);
  return (
    <div style={{position: 'absolute', left: 0, right: 0, top: 46 * s, display: 'flex', justifyContent: 'center', zIndex: 80, opacity: out}}>
      <div style={{display: 'flex', gap: `0 ${11 * s}px`, alignItems: 'baseline', fontFamily: font, fontSize: 44 * s, fontWeight: 600, letterSpacing: '-0.025em', color: onDark ? darkInk : ink, lineHeight: 1.2}}>
        {c.tokens.map((w, i) => {
          const p = tween(t, w.t - 0.06, w.t + 0.3, 0, 1, EASE.premium);
          const st: React.CSSProperties = w.em ? {fontFamily: serif, fontStyle: 'italic', fontWeight: 400, fontSize: 52 * s, letterSpacing: '-0.01em'} : {};
          // each word rises from behind a mask as it is said
          return (
            <span key={i} style={{display: 'inline-block', overflow: 'hidden', paddingBottom: 6 * s, marginBottom: -6 * s, verticalAlign: 'bottom'}}>
              <span style={{...st, display: 'inline-block', opacity: 0.35 + 0.65 * p, transform: `translateY(${(1 - p) * 105}%)`}}>{w.text}</span>
            </span>
          );
        })}
      </div>
    </div>
  );
};
