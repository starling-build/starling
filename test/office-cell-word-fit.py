#!/usr/bin/env python3
"""Check Mac Word's attached versus space-separated Latin words in legacy cells.

Eight freshly Word-printed controls hold the prefix advance fixed while moving
one ordinary space. Mode 14, centered cells, an embedded OFL font, and no
automatic East Asian spacing isolate the word's fitting rule. Windows uses
its separately measured rule; the native invocation deliberately selects Mac.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

def fixture(path):
    spec = importlib.util.spec_from_file_location(
        'opener_fit', Path(__file__).with_name('office-opener-fit.py'))
    opener = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(opener)
    seed = io.BytesIO()
    opener.fixture(seed)
    with zipfile.ZipFile(seed) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    for name in ('word/styles.xml', 'word/fontTable.xml'):
        parts[name] = parts[name].replace(
            b'Starling Opener CJK Test', b'Starling Cell Space CJK Test').replace(
            b'w:val="28"', b'w:val="24"')
    parts['word/settings.xml'] = parts['word/settings.xml'].replace(b'w:val="15"', b'w:val="14"')
    font = bytearray((Path(__file__).parent / 'fonts/StarlingCellSpaceTest.ttf').read_bytes())
    # This font has its own GUID, distinct from the opener fixture's subset.
    parts['word/fontTable.xml'] = parts['word/fontTable.xml'].replace(
        b'C2E49068-46C1-47FC-A059-0E4DA203B525', b'40792631-7B15-45A6-983A-C386BFD9408E')
    mask = bytes.fromhex('407926317B1545A6983AC386BFD9408E')[::-1]
    for i in range(32):
        font[i] ^= mask[i % 16]
    parts['word/fonts/opener.odttf'] = font
    cases = [('（      ）甲（    ）AA', 93.35), ('（     ） 甲（    ）AA', 93.35),
             ('（      ）甲（   ） AA', 93.35), ('（      ）甲（   ） AA', 92.85),
             ('（      ）甲（    ）A', 93.35), ('（      ）甲（   ） A', 93.35),
             ('（      ）甲（    ）A、', 93.35), ('（      ）甲（    ）A、', 95.85)]
    body = []
    for i, (text, width) in enumerate(cases):
        if i:
            body.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
        twips = round(width * 20)
        # Use Arial for ordinary spaces/letters and the embedded face for CJK.
        # This exercises fitting, independently of embedded Latin substitution.
        runs = []
        for piece in re.findall(r'[A ]+|[^A ]+', text):
            family = 'Arial' if piece.isascii() else 'Starling Cell Space CJK Test'
            runs.append(f'<w:r><w:rPr><w:rFonts w:ascii="{family}" w:hAnsi="{family}" '
                        f'w:eastAsia="{family}" w:hint="default"/></w:rPr>'
                        f'<w:t xml:space="preserve">{piece}</w:t></w:r>')
        body.append(
            f'<w:tbl><w:tblPr><w:tblW w:w="{twips}" w:type="dxa"/>'
            '<w:tblLayout w:type="fixed"/><w:tblCellMar>'
            '<w:top w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/>'
            '<w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/>'
            '</w:tblCellMar></w:tblPr>'
            f'<w:tblGrid><w:gridCol w:w="{twips}"/></w:tblGrid><w:tr><w:tc><w:tcPr>'
            f'<w:tcW w:w="{twips}" w:type="dxa"/></w:tcPr><w:p><w:pPr>'
            '<w:jc w:val="center"/>'
            '<w:spacing w:before="0" w:after="0" w:line="400" w:lineRule="exact"/>'
            '<w:autoSpaceDE w:val="0"/><w:autoSpaceDN w:val="0"/></w:pPr>'
            + ''.join(runs) + '</w:p></w:tc></w:tr></w:tbl>')
    body.append('<w:p/>')
    body.append('<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
                '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr>')
    parts['word/document.xml'] = (f'<w:document xmlns:w="{opener.W}"><w:body>'
                                 + ''.join(body) + '</w:body></w:document>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path):
    import pymupdf
    expected = [['（）甲（）', 'AA'], ['（）甲（）', 'AA'],
                ['（）甲（）AA'], ['（）甲（）AA'], ['（）甲（）', 'A'], ['（）甲（）A'],
                ['（）甲（）', 'A、'], ['（）甲（）A、']]
    with pymupdf.open(path) as pdf:
        assert len(pdf) == len(expected), f'{path}: expected 8 pages, got {len(pdf)}'
        for n, (page, want) in enumerate(zip(pdf, expected), 1):
            assert any('StarlingCellSpaceCJKTest' in font[3] for font in page.get_fonts()), (
                f'page {n}: embedded CJK test font missing; fallback would hide the error')
            lines = [''.join(span['text'] for span in line['spans'])
                     for block in page.get_text('dict')['blocks'] for line in block.get('lines', [])]
            lines = [''.join(text.split()) for text in lines if text.strip(' \t\r\n\x00')]
            assert lines == want, f'page {n}: expected {want}, got {lines}'
    print('  ✔ Legacy cell words: 8 Word cell-word controls pass')

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
        with tempfile.TemporaryDirectory(prefix='office-cell-word-fit-') as directory:
            doc, pdf = (Path(directory) / name for name in ('cell-word-fit.docx', 'cell-word-fit.pdf'))
            fixture(doc)
            env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': 'mac'}
            subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], env=env, check=True)
            check(pdf)


if __name__ == '__main__':
    main()
