#!/usr/bin/env python3
"""Make a replaceable macOS narration track and sentence-aligned captions."""
import json
import hashlib
from pathlib import Path
import re
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts/office-compatibility'
SCENES = json.loads(Path(__file__).with_name('scenes.json').read_text())
(OUT / 'audio').mkdir(parents=True, exist_ok=True)

def timestamp(seconds):
    ms = round(seconds * 1000)
    return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'

timeline, subtitles, raw = [], [], []
cursor, index = 0.0, 0
params = None
for scene in SCENES:
    scene['start'] = cursor
    scene['captions'] = []
    sentences = re.split(r'(?<=[.!?])\s+', scene['narration'])
    for j, sentence in enumerate(sentences):
        digest = hashlib.sha256(('Samantha|160|48000|' + sentence).encode()).hexdigest()[:12]
        path = OUT / 'audio' / f'{scene["id"]}-{j:02}-{digest}.wav'
        if not path.exists():
            subprocess.run(['say', '-v', 'Samantha', '-r', '160', '-o', str(path),
                            '--data-format=LEI16@48000', sentence], check=True)
        with wave.open(str(path)) as source:
            params = source.getparams()
            assert source.getnchannels() == 1 and source.getframerate() == 48000
            samples = source.readframes(source.getnframes())
            duration = source.getnframes() / source.getframerate()
        index += 1
        end = cursor + duration
        subtitles.append(f'{index}\n{timestamp(cursor)} --> {timestamp(end)}\n{sentence}\n')
        scene['captions'].append({'start': cursor, 'end': end, 'text': sentence})
        raw.append(samples)
        # A short breath between sentences; a longer one between chapters.
        pause = .38 if j == len(sentences) - 1 else .12
        raw.append(b'\0' * round(48000 * pause) * 2)
        cursor = end + pause
    scene['duration'] = cursor - scene['start']
    timeline.append(scene)
    print(scene['id'], round(scene['duration'], 2), flush=True)
with wave.open(str(OUT / 'narration.wav'), 'wb') as dest:
    dest.setnchannels(1); dest.setsampwidth(2); dest.setframerate(48000)
    for samples in raw:
        dest.writeframes(samples)
(OUT / 'captions.srt').write_text('\n'.join(subtitles))
(OUT / 'timeline.json').write_text(json.dumps(timeline, indent=2))
(OUT / 'script.txt').write_text('\n\n'.join(
    f'{timestamp(s["start"])}  {s["title"]}\n{s["narration"]}' for s in timeline) + '\n')
print(f'Total duration: {cursor:.2f} seconds', flush=True)
