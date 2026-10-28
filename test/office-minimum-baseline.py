#!/usr/bin/env python3
"""Word baselines for mixed Latin sizes under minimum and exact line heights.

Twelve Word-printed Arial controls cover a small leading letter or space,
minimum heights below/above the text's natural line, exact heights, and the
unchanged automatic-height path, both on and off a 30pt line grid.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

CASES = [(grid, mode, height, lead) for grid in (False, True)
         for mode, height, lead in (
             ('atLeast', 12, 'A'), ('atLeast', 12, ' '),
             ('atLeast', 36, 'A'), ('exact', 12, 'A'),
             ('exact', 36, 'A'), ('auto', 12, 'A'))]
# Word 16 for Mac, 2026-10-28: B's baseline and the following paragraph's.
EXPECTED = [(94.56, 110.88), (94.56, 110.88), (102.96, 119.28),
            (81.60, 95.28), (100.80, 119.28), (94.56, 110.88),
            (95.76, 113.28), (95.76, 113.28), (101.76, 119.28),
            (81.60, 95.28), (100.80, 119.28), (95.76, 113.28)]


def fixture(path):
    spec = importlib.util.spec_from_file_location(
        'grid_seed', Path(__file__).with_name('office-grid-band.py'))
    seed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(seed)
    buffer = io.BytesIO()
    seed.fixture(buffer)
    with ZipFile(buffer) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    namespace = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

    def run(text, size):
        return (f'<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
                f'<w:sz w:val="{size*2}"/></w:rPr>'
                f'<w:t xml:space="preserve">{text}</w:t></w:r>')

    section = ('<w:sectPr><w:type w:val="nextPage"/>'
               '<w:pgSz w:w="12240" w:h="15840"/>'
               '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/>'
               '<w:docGrid w:type="lines" w:linePitch="600"/></w:sectPr>')
    body = []
    for index, (grid, mode, height, lead) in enumerate(CASES):
        value = 240 if mode == 'auto' else height * 20
        spacing = (f'<w:spacing w:before="0" w:after="0" w:line="{value}" '
                   f'w:lineRule="{mode}"/>')
        grid_setting = '' if grid else '<w:snapToGrid w:val="0"/>'
        body.append('<w:p><w:pPr>' + spacing + grid_setting + '</w:pPr>'
                    + run(lead, 12) + run('B', 24) + '</w:p>')
        body.append('<w:p><w:pPr><w:snapToGrid w:val="0"/>'
                    + (section if index < len(CASES) - 1 else '')
                    + '</w:pPr>' + run('AFTER', 12) + '</w:p>')
    body.append(section)
    parts['word/document.xml'] = (
        f'<w:document xmlns:w="{namespace}"><w:body>'
        + ''.join(body) + '</w:body></w:document>')
    with ZipFile(path, 'w', ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path):
    import pymupdf
    with pymupdf.open(path) as document:
        assert len(document) == len(EXPECTED), f'{path}: expected 12 pages'
        for index, (page, (baseline, after)) in enumerate(zip(document, EXPECTED), 1):
            spans = [span for block in page.get_text('dict')['blocks']
                     for line in block.get('lines', []) for span in line['spans']]
            for text, expected in [('B', baseline), ('AFTER', after)]:
                actual = [span['origin'][1] for span in spans if span['text'].strip() == text]
                assert len(actual) == 1 and abs(actual[0] - expected) <= 0.5, (
                    f'page {index}, {text}: expected {expected}, got {actual}')
    print('  ✔ Minimum line baselines: all 12 Word controls pass')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--fixture', type=Path)
    group.add_argument('--pdf', type=Path)
    group.add_argument('--binary', type=Path)
    args = parser.parse_args()
    if args.fixture:
        fixture(args.fixture)
    elif args.pdf:
        check(args.pdf)
    else:
        with tempfile.TemporaryDirectory(prefix='office-minimum-baseline-') as directory:
            doc = Path(directory) / 'minimum-baseline.docx'
            fixture(doc)
            for mode in ('windows', 'mac'):
                pdf = Path(directory) / (mode + '.pdf')
                env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': mode}
                subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)],
                               env=env, check=True)
                check(pdf)


if __name__ == '__main__':
    main()
