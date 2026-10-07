#!/usr/bin/env python3
"""Generate the web icon font, or verify its checked-in inputs without FontTools.

python3 -m pip install fonttools   # regeneration only; use a virtual environment
python3 build/tools/subset-web-icons.py
python3 build/tools/subset-web-icons.py --check

Keeps every icon exposed by the SDK, rather than a particular app's subset.
The full upstream font remains available to native apps.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'sdk/Sources/FluentSystemIcons/Resources/FluentSystemIcons-Regular.ttf'
API = ROOT / 'sdk/Sources/FluentSystemIcons/FluentSystemIcons.swift'
OUTPUT = ROOT / 'web/fonts/FluentSystemIcons-Regular.ttf'
RECORD = OUTPUT.with_suffix('.json')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    points = sorted({int(value, 16) for value in
                     re.findall(r'IconData\((0x[0-9a-fA-F]+)', API.read_text())})
    assert points, 'No icon codepoints found'
    inputs = {'source_sha256': digest(SOURCE), 'codepoints': points}
    if sys.argv[1:] == ['--check']:
        record = json.loads(RECORD.read_text())
        if record != {**inputs, 'output_sha256': digest(OUTPUT)}:
            raise SystemExit('Web icon font is stale. Regenerate with build/tools/subset-web-icons.py')
        print(f'Web icon font: {len(points)} codepoints verified')
        return
    if sys.argv[1:]:
        raise SystemExit('Usage: subset-web-icons.py [--check]')
    from fontTools import subset
    from fontTools.ttLib import TTFont

    original = TTFont(SOURCE)
    original_cmap = original.getBestCmap()
    assert set(points) <= original_cmap.keys(), 'SDK references absent glyphs'
    font = TTFont(SOURCE)
    options = subset.Options()
    options.recalc_timestamp = False
    options.name_IDs = ['*']  # retain the font's copyright and license metadata
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=points)
    subsetter.subset(font)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUTPUT)
    # Check the saved font preserves every public icon's geometry and metrics.
    result = TTFont(OUTPUT)
    cmap = result.getBestCmap()
    for point in points:
        before, after = original_cmap[point], cmap[point]
        assert original['hmtx'][before] == result['hmtx'][after]
        assert original['glyf'][before].getCoordinates(original['glyf']) == result['glyf'][after].getCoordinates(result['glyf'])
    RECORD.write_text(json.dumps({**inputs, 'output_sha256': digest(OUTPUT)}, indent=2) + '\n')
    print(f'{len(points)} icons: {SOURCE.stat().st_size:,} → {OUTPUT.stat().st_size:,} bytes')


if __name__ == '__main__':
    main()
