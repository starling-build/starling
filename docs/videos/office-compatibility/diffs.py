#!/usr/bin/env python3
"""Run the repository comparator, preserving its unmodified images and output."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts/office-compatibility'
records = []
for app, versions in [('slides', ['before', 'current']),
                      ('writer', ['before', 'after']),
                      ('sheets', ['before', 'current'])]:
    for version in versions:
        key = f'{app}-{version}'
        dest = OUT / 'diffs' / key
        dest.mkdir(parents=True, exist_ok=True)
        for stale in dest.glob('pair-*.png'):
            stale.unlink()
        args = ['test/pdf-diff.py', str(OUT / 'assets' / f'{app}-reference.pdf'),
                str(OUT / 'assets' / f'{key}.pdf'), str(dest), '2']
        result = subprocess.run([sys.executable, *args], cwd=ROOT,
                                capture_output=True, text=True, check=True)
        (dest / 'output.txt').write_text(result.stdout)
        print(key, result.stdout, flush=True)
        records.append({'id': key, 'command': ['python', *args],
                        'stdout': result.stdout,
                        'images': [str(p.relative_to(OUT)) for p in sorted(dest.glob('*.png'))]})
(OUT / 'diffs/manifest.json').write_text(json.dumps({
    'scale': 2, 'dpi': 144, 'threshold': 32,
    'tool_sha256': hashlib.sha256((ROOT / 'test/pdf-diff.py').read_bytes()).hexdigest(),
    'comparisons': records}, indent=2))
