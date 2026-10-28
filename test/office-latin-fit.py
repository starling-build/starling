#!/usr/bin/env python3
"""Check Word's choice between compressing and wrapping a Mac body Latin word.

The automatic space before a word disappears when it wraps; internal spaces
remain available for stretching. These Word-printed controls distinguish the
two cases, using the embedded CJK test font and bundled Arial substitute.
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

FEW = ('甲' * 8 + '，') * 3 + '甲'
MANY = '甲' * 8 + '，' + '甲1甲' + '甲' * 7 + '，' + '甲1甲' + '甲' * 8
CASES = [(FEW, '92', 3, True), (FEW, 'AB', 3, True),
         (FEW, '92', -2, False), (MANY, '109', 2, False), (FEW, '92', 9, True)]


def fixture(path):
    spec = importlib.util.spec_from_file_location('opener_fit', Path(__file__).with_name('office-opener-fit.py'))
    opener = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(opener)
    seed = io.BytesIO()
    opener.fixture(seed)
    with zipfile.ZipFile(seed) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    blocks = []
    for prefix, word, inside, _ in CASES:
        digits = sum(char.isascii() for char in prefix)
        gaps = sum(a.isascii() != b.isascii() for a, b in zip(prefix, prefix[1:])) + 1
        # Arial's digit advance is 1139/2048 em; each automatic gap is 1/4 em.
        width = (len(prefix) - digits) * 14 + digits * 14 * 1139 / 2048 + gaps * 3.5 + inside
        def run(text):
            family = 'Arial' if text.isascii() else 'Starling Opener CJK Test'
            return (f'<w:r><w:rPr><w:rFonts w:ascii="{family}" w:hAnsi="{family}" '
                    f'w:eastAsia="{family}" w:hint="default"/><w:sz w:val="28"/>'
                    f'<w:spacing w:val="0"/></w:rPr><w:t>{text}</w:t></w:r>')
        paragraph = ('<w:p><w:pPr><w:spacing w:line="400" w:lineRule="exact"/>'
                     f'<w:ind w:left="0" w:firstLine="0" w:right="{round((468-width)*20)}"/>'
                     '<w:jc w:val="both"/><w:kinsoku w:val="0"/><w:autoSpaceDE/><w:autoSpaceDN/>'
                     '</w:pPr>' + ''.join(run(text) for text in re.findall(
                         r'[A-Za-z0-9]+|[^A-Za-z0-9]+', prefix + word + '乙' * 8)) + '</w:p>')
        if blocks:
            blocks.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
        blocks.append(paragraph)
    section = ('<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
               '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr>')
    parts['word/document.xml'] = re.sub(
        r'<w:body>.*?</w:body>', '<w:body>' + ''.join(blocks) + section + '</w:body>',
        parts['word/document.xml'].decode(), flags=re.S).encode()
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path):
    import pymupdf
    with pymupdf.open(path) as pdf:
        assert len(pdf) == len(CASES), f'{path}: expected 5 pages, got {len(pdf)}'
        for n, (page, case) in enumerate(zip(pdf, CASES), 1):
            prefix, word, _, taken = case
            lines = [''.join(span['text'] for span in line['spans'])
                     for block in page.get_text('dict')['blocks'] for line in block.get('lines', [])]
            # Ignore only empty paragraph markers, including Word's NUL-only spans.
            lines = [''.join(text.split()) for text in lines if text.strip(' \t\r\n\x00')]
            expected = [prefix + (word if taken else ''), ('' if taken else word) + '乙' * 8]
            assert lines == expected, f'page {n}: expected {expected}, got {lines}'
    print('  ✔ Latin-word fitting: 5 Word compression/stretch controls pass')


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
        with tempfile.TemporaryDirectory(prefix='office-latin-fit-') as directory:
            doc, pdf = (Path(directory) / name for name in ('latin-fit.docx', 'latin-fit.pdf'))
            fixture(doc)
            env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': 'mac'}
            subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], env=env, check=True)
            check(pdf)


if __name__ == '__main__':
    main()
