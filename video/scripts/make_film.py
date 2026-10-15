"""Writes src/films/stepwell.json and voice.json. Scene lengths come from the measured voice lines."""
import json, re, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
mark = re.search(r"MARK_SVG = '(.*?)';", (ROOT / 'src/screens/stepwell/index.tsx').read_text()).group(1)

def card(id, screen, lw, lh, w, x=0, y=40, z=0, frm=None, to=None, props=None, enter='rise', chrome='card', radius=30):
    p = {'id': id, 'screen': screen, 'chrome': chrome, 'x': x, 'y': y, 'z': z, 'w': w, 'h': round(w * lh / lw), 'lw': lw, 'lh': lh, 'radius': radius, 'enter': enter, 'props': props or {}}
    if frm is not None: p['from'] = frm
    if to is not None: p['to'] = to
    return p
def cap(at, until, text, **k): return {'at': at, 'until': until, 'text': text, 'pos': [0.5, 0.09], 'size': 44, 'weight': 650, **k}
def J(id, beats, panels, shots, captions=(), music='full', tin='blur', events=None, cues=None):
    s = {'id': id, 'type': 'Journey', 'beats': beats, 'in': tin, 'music': music, 'props': {'look': 'soft', 'panels': panels, 'shots': shots, 'captions': list(captions)}}
    if events: s['events'] = events
    if cues: s['addCues'] = cues
    return s

scenes = [
  J('savings', 30, [card('sv', 'SwSavings', 900, 560, 1240, y=50, props={'drop': 19})],
    [{'at': 0, 'zoom': 0.96}, {'at': 1, 'zoom': 1.02, 'ms': 7000, 'ease': 'sine'}, {'at': 18.6, 'zoom': 1.16, 'y': 70, 'ms': 800, 'ease': 'premium'}, {'at': 22, 'zoom': 1.0, 'y': 50, 'ms': 2600, 'ease': 'camera'}],
    [cap(-1, 13.2, 'A vault on Arc pays *3.1%*.'), cap(14.2, 28.6, 'Then it books *bad debt*.')], music='sparse', tin='cut',
    cues=[{'at': 19, 'sfx': 'drop', 'gain': 0}]),
  {'id': 'scale', 'type': 'Stat', 'beats': 17, 'in': 'zoom', 'music': 'build', 'tone': 'dark',
   'props': {'value': 170, 'from': 0, 'prefix': '$', 'suffix': 'M', 'label': 'in Morpho vaults on Arc.', 'sub': 'Nothing on Arc pays any of it back.'}},
  J('ask', 15, [card('q', 'SwQuote', 1240, 430, 1500, y=50, props={'m1': 5.8, 'm2': 10.2})],
    [{'at': 0, 'zoom': 0.98}, {'at': 0.5, 'zoom': 1.05, 'ms': 7000, 'ease': 'sine'}], music='build'),
  {'id': 'reveal', 'type': 'Reveal', 'beats': 5, 'in': 'iris', 'music': 'build',
   'props': {'name': 'Stepwell', 'tagline': 'First-loss cover for Morpho vaults on Arc.', 'markSvg': mark}},
  J('mechanism', 51, [
      card('well', 'SwWell', 1100, 680, 1060, x=-520, y=50, props={'keys': [[0, 850, 150], [26.5, 850, 70], [41, 850, 150]]}),
      card('split', 'SwSplit', 1100, 520, 920, x=520, y=50, frm=11.8, to=23.2, props={'split': 15.6}),
      card('table', 'SwTable', 1000, 560, 880, x=520, y=50, frm=23.2, props={'loss': 26.5, 'back': 41}),
    ],
    [{'at': 0, 'focus': 'well', 'zoom': 1.3}, {'at': 0.5, 'zoom': 1.36, 'ms': 5000, 'ease': 'sine'}, {'at': 11.6, 'x': -45, 'y': 50, 'zoom': 0.84, 'ms': 1200, 'ease': 'camera'},
     {'at': 24, 'zoom': 0.86, 'ms': 6000, 'ease': 'sine'}, {'at': 39, 'zoom': 0.87, 'ms': 5000, 'ease': 'sine'}],
    [cap(0.6, 11.3, 'Cover sits *on top*.'), cap(12.5, 22.8, 'Paid from *interest*.'), cap(23.6, 38.6, 'Cover takes the *first* loss.'), cap(39.6, 50.2, 'Refills depositors *first*.')],
    cues=[{'at': 26.5, 'sfx': 'drop'}, {'at': 41, 'sfx': 'shimmer'}, {'at': 15.6, 'sfx': 'swish'}]),
  J('guards', 20, [card('g', 'SwGuards', 1100, 440, 1480, y=60, chrome='none', props={'g1': 0.8, 'g2': 9.6})],
    [{'at': 0, 'zoom': 1.0}, {'at': 0.5, 'zoom': 1.04, 'ms': 9000, 'ease': 'sine'}],
    [cap(0.6, 19.2, 'Built to be hard to *game*.')], cues=[{'at': 0.8, 'sfx': 'pop'}, {'at': 9.6, 'sfx': 'pop', 'pitch': 3}]),
  J('sign', 15, [card('s', 'SwSign', 1240, 600, 1500, y=60, chrome='none', props={'click': 4.4, 'code': 8.4})],
    [{'at': 0, 'zoom': 1.0}, {'at': 0.5, 'zoom': 1.03, 'ms': 6500, 'ease': 'sine'}],
    [cap(0.6, 14.2, 'One signature. *One read.*')], cues=[{'at': 4.4, 'sfx': 'click'}, {'at': 8.4, 'sfx': 'type', 'beats': 3}]),
  J('fork', 15, [card('t', 'SwFork', 1150, 500, 1460, y=60, chrome='none', props={'at': 0})],
    [{'at': 0, 'zoom': 0.98}, {'at': 0.5, 'zoom': 1.05, 'ms': 6500, 'ease': 'sine'}],
    [cap(0.6, 14.2, 'Real bad debt, *real vault*.')], cues=[{'at': 4, 'sfx': 'chime'}]),
  J('tests', 11, [card('ts', 'SwTests', 1300, 520, 1500, y=60, props={'at': 1})],
    [{'at': 0, 'zoom': 1.0}, {'at': 0.5, 'zoom': 1.04, 'ms': 4800, 'ease': 'sine'}],
    [cap(0.6, 10.2, '35 tests. 4 proofs. *Every push.*')], cues=[{'at': 1, 'sfx': 'count', 'beats': 4}]),
  J('live', 12, [card('l', 'SwLive', 1400, 700, 1500, y=60, chrome='none', props={'click': 4})],
    [{'at': 0, 'zoom': 1.0}, {'at': 0.5, 'zoom': 1.03, 'ms': 5200, 'ease': 'sine'}],
    [cap(0.6, 11.4, "It's *live*. Press one button.")], cues=[{'at': 4, 'sfx': 'click'}, {'at': 5.2, 'sfx': 'drop'}]),
  {'id': 'outro', 'type': 'Outro', 'beats': 10, 'in': 'blur', 'music': 'out',
   'props': {'name': 'Stepwell', 'markSvg': mark, 'line': 'Keep the deep water.', 'url': 'stepwell-one.vercel.app', 'look': 'soft'}},
]

film = {
  'meta': {'title': 'Stepwell — first-loss cover on Arc', 'fps': 30, 'bpm': 120, 'beatsPerBar': 4, 'tailBeats': 2, 'chords': ['Dmaj7', 'Bm7', 'Gmaj7', 'A'], 'target': 101},
  'brand': {'bg': '#FAF6EF', 'surface': '#FFFEFC', 'ink': '#17150F', 'muted': '#6D6459', 'line': '#EBE3D7', 'accent': '#1E5B4F', 'accentInk': '#FFFFFF',
            'dark': '#17150F', 'darkInk': '#F3ECE1', 'fontDisplay': 'Plus Jakarta Sans', 'fontText': 'Plus Jakarta Sans', 'fontMono': 'Geist Mono', 'fontSerif': 'Eczar',
            'emphasis': 'accent', 'tracking': -0.035, 'weight': 750, 'look': 'soft', 'aurora': ['#F2E2CE', '#E3ECE4', '#F7E6D6', '#DCE9E1', '#FFFFFF'], 'auroraStrength': 0.35,
            'panel': '#FFFEFC', 'panelBorder': 'rgba(23,21,15,0.06)'},
  'grain': 0.03,
  'scenes': scenes,
}
(ROOT / 'src/films/stepwell.json').write_text(json.dumps(film, indent=1))

# voice placement in beats from the start of the film
starts, t = {}, 0
for s in scenes: starts[s['id']] = t; t += s['beats']
voice = [('savings', 0.4), ('savings', 14), ('scale', 0.6), ('ask', 0.6), ('reveal', 0.6), ('mechanism', 0.6), ('mechanism', 12.5), ('mechanism', 23.5),
         ('mechanism', 39.5), ('guards', 0.6), ('sign', 0.6), ('fork', 0.6), ('tests', 0.6), ('live', 0.6), ('outro', 1.5)]
(ROOT / 'voice.json').write_text(json.dumps([{'file': f'public/voice/l{i+1:02d}.mp3', 'sec': (starts[sc] + b) * 0.5} for i, (sc, b) in enumerate(voice)], indent=1))
print('total beats', t, '=', t * 0.5, 's')
