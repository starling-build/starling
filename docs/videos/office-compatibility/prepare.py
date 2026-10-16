#!/usr/bin/env python3
"""Freeze the actual comparison PDFs and record their provenance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts/office-compatibility'
ASSETS = OUT / 'assets'
ASSETS.mkdir(parents=True, exist_ok=True)
SOURCES = {
    'slides-reference': ROOT / 'test/corpus/pptx/powerpoint/lo-tdf149985-orig.pdf',
    'slides-before': Path.home() / 'starling-ppt-check/app27/pdf/lo-tdf149985.pdf',
    'writer-reference': ROOT / 'test/corpus/docx/word/IllustrativeCases-orig.pdf',
    'writer-before': Path.home() / 'starling-doc-check-starling-ios/np17/pdf/IllustrativeCases.pdf',
    'writer-after': Path.home() / 'starling-doc-check-starling-ios/np18/pdf/IllustrativeCases.pdf',
    'sheets-reference': ROOT / 'test/corpus/xlsx/excel/chart-piechart_outside-orig.pdf',
    'sheets-before': Path.home() / 'starling-xls-check/ours0/chart-piechart_outside.pdf',
}
manifest = {'office_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'assets': {}, 'historical_output_note': 'Earlier PDFs are archived test exports, not reconstructed screenshots. The original build SHA is not embedded in those PDFs. Writer np17/np18 is corroborated by s18.log and commit f4cc1940; no exact historical build SHA is asserted.',
            'reference_note': 'Microsoft reference versions, font environment, and test-file origins are documented in test/corpus/{docx,pptx,xlsx}/README.md. These are PDF rendering comparisons, not screen recordings or full feature-compatibility measurements.'}
for name, source in SOURCES.items():
    dest = ASSETS / (name + '.pdf')
    shutil.copy2(source, dest)
    manifest['assets'][name] = {'source': str(source), 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest()}
app = ROOT / 'apps/OfficeApp/.build/release/OfficeApp'
manifest['binary_sha256'] = hashlib.sha256(app.read_bytes()).hexdigest()
for name, flag, source in [
    ('slides-current', '--deck-pdf', 'test/corpus/pptx/decks/lo-tdf149985.pptx'),
    ('writer-current', '--convert', 'test/corpus/docx/docs/IllustrativeCases.docx'),
    ('sheets-current', '--sheet-pdf', 'test/corpus/xlsx/books/chart-piechart_outside.xlsx')]:
    dest = ASSETS / (name + '.pdf')
    env = dict(os.environ, OFFICE_WORD_FONTS='mac')
    subprocess.run([str(app), flag, str(ROOT / source), str(dest)], env=env, check=True)
    manifest['assets'][name] = {'source': source, 'sha256': hashlib.sha256(dest.read_bytes()).hexdigest(),
                                'input_sha256': hashlib.sha256((ROOT / source).read_bytes()).hexdigest(),
                                'command': [str(app), flag, source, str(dest)]}
for name in ['s17.log', 's18.log']:
    shutil.copy2(Path.home() / 'starling-doc-check-starling-ios' / name, ASSETS / ('writer-' + name))
for extension in ['docx', 'pptx', 'xlsx']:
    shutil.copy2(ROOT / f'test/corpus/{extension}/README.md', ASSETS / f'{extension}-sources.md')
(OUT / 'provenance.json').write_text(json.dumps(manifest, indent=2))
print('Frozen', len(manifest['assets']), 'actual PDF exports.')
