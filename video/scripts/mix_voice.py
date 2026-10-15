"""Mix the recorded voice over the rendered film: each line at its time from voice.json, the
score ducked under the voice, mastered to -14 LUFS / -1 dBTP.
  python3 scripts/mix_voice.py out/stepwell-16x9.mp4 out/stepwell-voiced.mp4"""
import json, subprocess, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
src, dst = sys.argv[1], sys.argv[2]
lines = json.loads((ROOT / 'voice.json').read_text())
cmd = ['ffmpeg', '-v', 'error', '-y', '-i', src]
for l in lines: cmd += ['-i', str(ROOT / l['file'])]
parts = []
for i, l in enumerate(lines, start=1):
    d = int(round(l['sec'] * 1000))
    parts.append(f'[{i}:a]aresample=48000,aformat=channel_layouts=stereo,adelay={d}|{d},volume=1.6[v{i}]')
vin = ''.join(f'[v{i}]' for i in range(1, len(lines) + 1))
parts.append(f'{vin}amix=inputs={len(lines)}:normalize=0:dropout_transition=0[vo]')
parts.append('[vo]asplit[vk][vm]')
parts.append('[0:a]aresample=48000,volume=0.55[bed0]')
parts.append('[bed0][vk]sidechaincompress=threshold=0.02:ratio=8:attack=15:release=350[bed]')
parts.append('[bed][vm]amix=inputs=2:normalize=0:duration=first,loudnorm=I=-14:TP=-1:LRA=11[out]')
cmd += ['-filter_complex', ';'.join(parts), '-map', '0:v', '-map', '[out]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-movflags', '+faststart', dst]
subprocess.run(cmd, check=True)
print('wrote', dst)
