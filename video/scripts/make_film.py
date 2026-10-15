"""Writes src/films/stepwell.json and voice.json. Scene lengths come from the measured voice lines."""
import json, re, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
mark = re.search(r"MARK_SVG = '(.*?)';", (ROOT / 'src/screens/stepwell/index.tsx').read_text()).group(1)

def card(id, screen, lw, lh, w, x=0, y=40, z=0, frm=None, to=None, props=None, enter='rise', chrome='card', radius=30):
    w = round(w * 0.86)  # calm frames: cards float in plenty of space
    p = {'id': id, 'screen': screen, 'chrome': chrome, 'x': x, 'y': y, 'z': z, 'w': w, 'h': round(w * lh / lw), 'lw': lw, 'lh': lh, 'radius': radius, 'enter': enter, 'props': props or {}}
    if frm is not None: p['from'] = frm
    if to is not None: p['to'] = to
    return p
def cap(at, until, text, **k): return {'at': at, 'until': until, 'text': text, 'pos': [0.5, 0.09], 'size': 44, 'weight': 650, **k}
def J(id, beats, panels, shots, captions=(), music='full', tin='blur', events=None, cues=None, tone=None, blooms=None):
    s = {'id': id, 'type': 'Journey', 'beats': beats, 'in': tin, 'music': music, 'props': {'look': 'soft', 'panels': panels, 'shots': shots, 'captions': list(captions)}}
    if tone: s['tone'] = tone
    if blooms: s['props']['blooms'] = blooms
    if events: s['events'] = events
    if cues: s['addCues'] = cues
    return s

scenes = [
  J('savings', 30, [card('sv', 'SwSavings', 900, 560, 1240, y=60, props={'drop': 19})],
    [{'at': 0, 'zoom': 1.6, 'x': -60, 'y': 30}, {'at': 0.6, 'zoom': 1.0, 'x': 0, 'y': 60, 'ms': 2600, 'ease': 'premium'}, {'at': 6, 'zoom': 1.05, 'ms': 6000, 'ease': 'sine'},
     {'at': 18.7, 'zoom': 1.3, 'x': -110, 'y': 30, 'ms': 450, 'ease': 'enter'}, {'at': 21, 'zoom': 1.08, 'x': 0, 'y': 60, 'ms': 2200, 'ease': 'camera'}],
    music='sparse', tin='cut', cues=[{'at': 19, 'sfx': 'drop', 'gain': 2}, {'at': 18.6, 'sfx': 'riser', 'beats': 0.4}],
    blooms=[{'at': 19, 'color': '#C2542A'}]),
  J('scale', 17, [card('vw', 'SwVaults', 1500, 760, 1560, y=70, chrome='none', props={'count': 0.6, 'mark': 10.5})],
    [{'at': 0, 'zoom': 0.94}, {'at': 0.5, 'zoom': 1.02, 'ms': 8000, 'ease': 'sine'}],
    music='build', tin='whip', tone='dark', cues=[{'at': 0.6, 'sfx': 'count', 'beats': 3}, {'at': 3.8, 'sfx': 'hit', 'gain': -2}, {'at': 10.5, 'sfx': 'tick'}]),
  J('ask', 15, [card('q', 'SwQuote', 1240, 430, 1500, y=60, props={'m1': 5.8, 'm2': 10.2})],
    [{'at': 0, 'zoom': 1.12, 'x': -60}, {'at': 0.3, 'zoom': 1.0, 'x': 0, 'ms': 1400, 'ease': 'premium'}, {'at': 3.5, 'zoom': 1.06, 'ms': 5500, 'ease': 'sine'}],
    music='build', tin='push', cues=[{'at': 5.8, 'sfx': 'swish', 'gain': -4}, {'at': 10.2, 'sfx': 'swish', 'gain': -4}]),
  {'id': 'reveal', 'type': 'Reveal', 'beats': 5, 'in': {'type': 'flood', 'color': '#1E5B4F'}, 'music': 'build',
   'props': {'name': 'Stepwell', 'tagline': 'First-loss cover for Morpho vaults on Arc.', 'markSvg': mark}},
  J('mechanism', 51, [
      card('well', 'SwWell', 1100, 680, 1060, x=-520, y=70, props={'keys': [[0, 850, 150], [26.5, 850, 70], [41, 850, 150]], 'callout': [27.5, 38.5, 'takes the', 'first loss']}),
      card('split', 'SwSplit', 1100, 520, 920, x=520, y=70, frm=11.8, to=23.2, props={'split': 15.6}, enter='pop'),
      card('table', 'SwTable', 1000, 560, 880, x=520, y=70, frm=33.6, props={'loss': 26.5, 'back': 41}, enter='pop'),
    ],
    [{'at': 0, 'focus': 'well', 'zoom': 2.0, 'y': -40}, {'at': 0.3, 'focus': 'well', 'zoom': 1.32, 'ms': 2200, 'ease': 'premium'}, {'at': 5, 'zoom': 1.38, 'ms': 5000, 'ease': 'sine'},
     {'at': 11.6, 'x': -45, 'y': 70, 'zoom': 0.84, 'ms': 1200, 'ease': 'camera'}, {'at': 24, 'x': -380, 'y': 40, 'zoom': 1.12, 'ms': 1300, 'ease': 'camera'},
     {'at': 34, 'x': -45, 'y': 70, 'zoom': 0.86, 'ms': 1300, 'ease': 'camera'}, {'at': 38, 'zoom': 0.88, 'ms': 5000, 'ease': 'sine'}],
    tin='zoom', cues=[{'at': 26.5, 'sfx': 'drop', 'gain': 1}, {'at': 41, 'sfx': 'shimmer'}, {'at': 15.6, 'sfx': 'swish'}, {'at': 11.8, 'sfx': 'pop'}, {'at': 23.2, 'sfx': 'pop'}]),
  J('guards', 20, [card('g', 'SwGuards', 1100, 440, 1480, y=70, chrome='none', props={'g1': 0.8, 'g2': 9.6})],
    [{'at': 0, 'zoom': 1.08, 'x': -240}, {'at': 0.6, 'zoom': 1.0, 'x': 0, 'ms': 1200, 'ease': 'premium'}, {'at': 8.8, 'zoom': 1.1, 'x': 240, 'ms': 1100, 'ease': 'camera'}, {'at': 16, 'zoom': 1.0, 'x': 0, 'ms': 1400, 'ease': 'camera'}],
    tin='push', cues=[{'at': 0.8, 'sfx': 'pop'}, {'at': 9.6, 'sfx': 'pop', 'pitch': 3}]),
  J('sign', 15, [card('s', 'SwSign', 1240, 600, 1500, y=70, chrome='none', props={'click': 4.4, 'code': 8.4})],
    [{'at': 0, 'zoom': 1.1, 'x': -200}, {'at': 0.5, 'zoom': 1.06, 'x': -180, 'ms': 1000, 'ease': 'premium'}, {'at': 7.6, 'zoom': 1.0, 'x': 0, 'ms': 1200, 'ease': 'camera'}],
    tin={'type': 'wipe', 'dir': 'up'}, cues=[{'at': 4.4, 'sfx': 'click'}, {'at': 8.4, 'sfx': 'type', 'beats': 3}]),
  J('fork', 15, [card('t', 'SwFork', 1150, 500, 1460, y=70, chrome='none', props={'at': 0})],
    [{'at': 0, 'zoom': 0.96}, {'at': 0.5, 'zoom': 1.06, 'ms': 6500, 'ease': 'sine'}],
    tin='iris', tone='dark', cues=[{'at': 2, 'sfx': 'type', 'beats': 1.5}, {'at': 4, 'sfx': 'chime'}]),
  J('tests', 11, [card('ts', 'SwTests', 1300, 520, 1500, y=70, props={'at': 1})],
    [{'at': 0, 'zoom': 1.1, 'y': 70}, {'at': 0.3, 'zoom': 1.0, 'y': 70, 'ms': 2600, 'ease': 'premium'}],
    tin='push', cues=[{'at': 1, 'sfx': 'count', 'beats': 4}, {'at': 5.2, 'sfx': 'chime'}]),
  J('live', 12, [card('l', 'SwLive', 1400, 700, 1500, y=70, chrome='none', props={'click': 4})],
    [{'at': 0, 'zoom': 1.08, 'x': -120}, {'at': 0.4, 'zoom': 1.04, 'x': -100, 'ms': 1000, 'ease': 'premium'}, {'at': 5.2, 'zoom': 1.0, 'x': 0, 'ms': 1200, 'ease': 'camera'}],
    tin='zoom', cues=[{'at': 4, 'sfx': 'click'}, {'at': 5.2, 'sfx': 'drop'}]),
  {'id': 'outro', 'type': 'Outro', 'beats': 10, 'in': {'type': 'flood', 'color': '#1E5B4F'}, 'music': 'out',
   'props': {'name': 'Stepwell', 'markSvg': mark, 'line': 'First-loss cover for Morpho vaults on Arc.', 'url': 'stepwell-one.vercel.app', 'look': 'soft', 'qr': 'qr.svg', 'qrLabel': 'Try it on your phone'}},
]

film = {
  'meta': {'title': 'Stepwell — first-loss cover on Arc', 'fps': 30, 'bpm': 120, 'beatsPerBar': 4, 'tailBeats': 2, 'chords': ['Dmaj7', 'Bm7', 'Gmaj7', 'A'], 'target': 101},
  'brand': {'bg': '#FAF6EF', 'surface': '#FFFEFC', 'ink': '#17150F', 'muted': '#6D6459', 'line': '#EBE3D7', 'accent': '#1E5B4F', 'accentInk': '#FFFFFF',
            'dark': '#17150F', 'darkInk': '#F3ECE1', 'fontDisplay': 'Plus Jakarta Sans', 'fontText': 'Plus Jakarta Sans', 'fontMono': 'Geist Mono', 'fontSerif': 'Eczar',
            'emphasis': 'accent', 'tracking': -0.035, 'weight': 750, 'look': 'soft', 'aurora': ['#F2E2CE', '#E3ECE4', '#F7E6D6', '#DCE9E1', '#FFFFFF'], 'auroraStrength': 0.35,
            'panel': '#FFFEFC', 'panelBorder': 'rgba(23,21,15,0.06)'},
  'grain': 0.03,
  'scenes': scenes,
  'captionDark': [],
  'captionTrack': json.loads((ROOT / 'captions.json').read_text()) if (ROOT / 'captions.json').exists() else [],
}
_t = 0
for _s in scenes:
    if _s.get('tone') == 'dark': film['captionDark'].append([_t * 0.5, (_t + _s['beats']) * 0.5])
    _t += _s['beats']
(ROOT / 'src/films/stepwell.json').write_text(json.dumps(film, indent=1))

# voice placement in beats from the start of the film
starts, t = {}, 0
for s in scenes: starts[s['id']] = t; t += s['beats']
voice = [('savings', 0.4), ('savings', 14), ('scale', 0.6), ('ask', 0.6), ('reveal', 0.6), ('mechanism', 0.6), ('mechanism', 12.5), ('mechanism', 23.5),
         ('mechanism', 39.5), ('guards', 0.6), ('sign', 0.6), ('fork', 0.6), ('tests', 0.6), ('live', 0.6), ('outro', 1.5)]
(ROOT / 'voice.json').write_text(json.dumps([{'file': f'public/voice/l{i+1:02d}.mp3', 'sec': (starts[sc] + b) * 0.5} for i, (sc, b) in enumerate(voice)], indent=1))
print('total beats', t, '=', t * 0.5, 's')
