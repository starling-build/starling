#!/usr/bin/env python3
"""build/tools/office_web_fonts.py: the browser registers the Traditional
Chinese serif a second time under the engine's "Ink+0.07 " name, the family
OfficeFonts.pmingliuInkFamily draws a Ming name's ideographs in, once only.
And the family OfficeFonts.webChineseSans sends a Chinese name to in the
browser is one the shipped fonts list in a regular and a bold file (not the
variable Noto Sans SC, which the browser draws at its thinnest weight).
And the browser lists Starling FangSong under OfficeFonts.starlingFangSong's
name and marks it loaded, so a 仿宋 name draws in it as natively."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'build' / 'tools'))
import office_web_fonts  # noqa: E402

swift = (Path(__file__).resolve().parent.parent
         / 'apps/OfficeApp/Sources/OfficeApp/OfficeFonts.swift').read_text()
entry = {'url': 'fonts/NotoSerifCJK-Regular.ttc', 'faces': [
    {'index': 2, 'family': 'Noto Serif CJK SC'}, {'index': 3, 'family': 'Noto Serif CJK TC'}]}
out = office_web_fonts.prepare_manifest([entry])
again = office_web_fonts.prepare_manifest(out)
ink = [f for f in again[0]['faces'] if f['family'].startswith('Ink+')]
fails = 0
if ink != [{'index': 3, 'family': 'Ink+0.07 Noto Serif CJK TC'}]:
    print(f'office-web-fonts: expected one Ink face at index 3, got {ink}'); fails += 1
if f'static let pmingliuInkFamily = "{ink[0]["family"] if ink else "?"}"' not in swift:
    print('office-web-fonts: OfficeFonts.pmingliuInkFamily and FACE_ALIASES disagree'); fails += 1
import re  # noqa: E402
m = re.search(r'static let webChineseSans = "([^"]+)"', swift)
tsv = (Path(__file__).resolve().parent.parent
       / 'apps/OfficeApp/Sources/OfficeApp/Resources/fonts/fonts.tsv').read_text().splitlines()
styles = sorted(r.split('\t')[3] for r in tsv if m and len(r.split('\t')) > 3 and r.split('\t')[2] == m.group(1))
if styles != ['Bold', 'Regular']:
    print(f'office-web-fonts: webChineseSans {m.group(1) if m else "?"} has files {styles}, want Bold and Regular'); fails += 1
fs = re.search(r'static let starlingFangSong = "([^"]+)"', swift)
if not fs or office_web_fonts.DEFERRED_FAMILIES.get('StarlingFangSong-Regular.ttf') != fs.group(1):
    print('office-web-fonts: the manifest and OfficeFonts.starlingFangSong disagree'); fails += 1
wasi = swift[swift.find('// The page preloads UI/default faces.'):]
if '_fangSongLoaded = true' not in wasi[:wasi.find('#else')]:
    print('office-web-fonts: the browser never marks Starling FangSong loaded'); fails += 1
print('office-web-fonts: ok' if not fails else 'office-web-fonts: FAILED')
sys.exit(1 if fails else 0)
