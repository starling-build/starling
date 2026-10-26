#!/usr/bin/env python3
"""Recompress staged .gz assets with Zopfli without changing their contents.

Optional release step: install zopfli in a build-only Python environment, then
run this with that Python before packaging/deploying the web app. Browsers use
their existing gzip decoder; no runtime dependency or new browser API needed.
"""
import argparse
import gzip
from pathlib import Path


def optimize(path):
    import zopfli.gzip

    original = path.read_bytes()
    raw = gzip.decompress(original)
    compressed = zopfli.gzip.compress(raw, numiterations=5)
    if gzip.decompress(compressed) != raw:
        raise ValueError(f'Compression changed the contents: {path}')
    if len(compressed) < len(original):
        path.write_bytes(compressed)
    print(f'{path}: {len(original):,} → {min(len(original), len(compressed)):,} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', type=Path, nargs='+')
    args = parser.parse_args()
    for path in args.files:
        optimize(path)
