#!/usr/bin/env python3
"""Add verified Brotli alternatives to a staged font manifest. Requires brotli.

The originals and all family/fallback/lazy metadata are retained. Decoding the
compressed transport restores the original font bytes, including PDF data.
"""
import argparse
import json
from pathlib import Path
import subprocess
from urllib.parse import urlsplit


def compress(stage):
    stage = stage.resolve()
    manifest = stage / 'fonts/manifest.json'
    entries = json.loads(manifest.read_text())
    originals = compressed = 0
    for entry in entries:
        url = urlsplit(entry['url'])
        source = (stage / url.path).resolve()
        if (url.scheme or url.netloc or url.query or url.fragment
                or url.path.startswith('/') or not source.is_relative_to(stage)):
            raise ValueError(f'Expected a local font URL: {entry["url"]}')
        target = source.with_name(source.name + '.br')
        subprocess.run(['brotli', '-q', '11', '-f', '-o', str(target), str(source)], check=True)
        raw = source.read_bytes()
        if subprocess.check_output(['brotli', '-d', '-c', str(target)]) != raw:
            raise ValueError(f'Compressed font failed verification: {source}')
        entry['brotli'] = target.relative_to(stage).as_posix()
        originals += len(raw)
        compressed += target.stat().st_size
    # A partial conversion must not leave the manifest pointing at missing files.
    manifest.write_text(json.dumps(entries, indent=2) + '\n')
    print(f'{len(entries)} fonts verified: {originals:,} raw bytes → {compressed:,} Brotli bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    compress(parser.parse_args().stage)
