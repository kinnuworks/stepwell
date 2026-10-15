"""Caption track: one short phrase per voice line, the voice's exact words, digits for numbers,
each word timed from the recording. Word times map each word's position in the line onto the
voiced parts of the audio (pauses found with ffmpeg silencedetect are skipped), so a word lands
when it is said, give or take a tenth of a second."""
import json, re, subprocess, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent

LINES = [  # (spoken line, exact phrase from it, digits shown for spoken numbers)
 ("You put a thousand dollars of USDC into a vault on Arc. It pays about three percent.", "It pays about three percent", {"three percent": "3%"}),
 ("Then a borrower defaults. The vault books bad debt, and your thousand is now nine hundred and twenty.", "your thousand is now nine hundred and twenty", {"thousand": "1,000", "nine hundred and twenty": "920"}),
 ("Morpho vaults on Arc hold about one hundred and seventy million dollars. Today, nothing pays any of it back.", "nothing pays any of it back", {}),
 ("Arc asked builders for exactly this: loss cover built into deposits, paid for out of yield.", "loss cover built into deposits", {}),
 ("This is Stepwell.", "This is Stepwell", {}),
 ("Underwriters put up a cover layer. When the vault loses money, cover pays first.", "cover pays first", {}),
 ("Depositors pay for it with a slice of their interest. Never out of pocket.", "Never out of pocket", {}),
 ("The same eight percent loss. Covered deposits stay at eight hundred and fifty. The cover layer takes all of it.", "The cover layer takes all of it", {}),
 ("When the money comes back, it refills depositors first, then cover.", "it refills depositors first", {}),
 ("It's built to be hard to game. Deposits wait a day before they're covered. Underwriters give three days' notice, and still carry losses while they wait.", "still carry losses while they wait", {}),
 ("On Arc, a covered deposit is one signature, and any app can read a vault's cover in one call.", "a covered deposit is one signature", {}),
 ("We pushed real bad debt through the Steakhouse vault, on a copy of Arc mainnet. Cover took all of it.", "Cover took all of it", {}),
 ("Thirty-five tests and four symbolic proofs run on every push.", "Thirty-five tests and four symbolic proofs", {"Thirty-five": "35", "four": "4"}),
 ("It's live. Press one button, and watch cover take a real loss.", "watch cover take a real loss", {}),
 ("Stepwell. Keep the deep water.", "Keep the deep water", {}),
]

def voiced(path):
    dur = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path], capture_output=True, text=True).stdout)
    log = subprocess.run(['ffmpeg', '-i', path, '-af', 'silencedetect=noise=-35dB:d=0.1', '-f', 'null', '-'], capture_output=True, text=True).stderr
    st = [float(x) for x in re.findall(r'silence_start: ([\d.]+)', log)]
    en = [float(x) for x in re.findall(r'silence_end: ([\d.]+)', log)]
    sil = list(zip(st, en + [dur] * (len(st) - len(en))))
    segs, t = [], 0.0
    for a, b in sil:
        if a > t: segs.append((t, a))
        t = max(t, b)
    if t < dur: segs.append((t, dur))
    return segs

def at_fraction(segs, x):
    total = sum(b - a for a, b in segs); want = x * total
    for a, b in segs:
        if want <= b - a: return a + want
        want -= b - a
    return segs[-1][1]

voice = json.loads((ROOT / 'voice.json').read_text())
track = []
for i, (line, phrase, digits) in enumerate(LINES):
    assert phrase in line, phrase
    segs = voiced(str(ROOT / voice[i]['file']))
    words = line.split()
    weights = [len(w) + 2 for w in words]
    cum = [sum(weights[:k]) / sum(weights) for k in range(len(words) + 1)]
    pw = phrase.split(); k0 = next(k for k in range(len(words)) if ' '.join(w.strip('.,:') for w in words[k:k + len(pw)]) == phrase)
    toks, k = [], 0
    while k < len(pw):
        for spoken, shown in digits.items():
            n = len(spoken.split())
            if ' '.join(pw[k:k + n]) == spoken:
                toks.append((shown, k)); k += n; break
        else:
            toks.append((pw[k], k)); k += 1
    t0 = voice[i]['sec']
    out = [{'text': s, 't': round(t0 + at_fraction(segs, cum[k0 + j]), 3)} for s, j in toks]
    end = t0 + at_fraction(segs, cum[k0 + len(pw)]) + 0.9
    track.append({'tokens': out, 'end': round(end, 3)})
# one at a time: each caption is fully gone 0.15 s before the next begins
for a, b in zip(track, track[1:]):
    a['end'] = round(min(a['end'], b['tokens'][0]['t'] - 0.15), 3)
(ROOT / 'captions.json').write_text(json.dumps(track, indent=1))
for c in track: print(f"{c['tokens'][0]['t']:7.2f}–{c['end']:7.2f}  " + ' '.join(t['text'] for t in c['tokens']))
