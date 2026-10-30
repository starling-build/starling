#!/usr/bin/env python3
"""Word for Mac controls for undeclared English GB2312 font names.

Fresh Word resolves these absent names like an unrelated unknown name, while
installed FangSong and KaiTi retain square advances. Check glyph origins and
following-line baselines, not outlines of the bundled substitute fonts.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

FONTS = ['FangSong_GB2312', 'KaiTi_GB2312', 'StarlingMissingProbe', 'FangSong', 'KaiTi']


def fixture(path):
    spec = importlib.util.spec_from_file_location('seed', Path(__file__).with_name('office-grid-band.py'))
    seed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(seed)
    buffer = io.BytesIO()
    seed.fixture(buffer)
    with ZipFile(buffer) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    section = ('<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="12240" w:h="15840"/>'
               '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr>')
    body = []
    for index, name in enumerate(FONTS):
        body.append('<w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/>'
                    '<w:autoSpaceDE w:val="0"/><w:autoSpaceDN w:val="0"/></w:pPr>'
                    f'<w:r><w:rPr><w:rFonts w:ascii="{name}" w:hAnsi="{name}" w:eastAsia="{name}"/>'
                    '<w:sz w:val="32"/></w:rPr><w:t>A.甲“乙” 123</w:t></w:r></w:p>')
        body.append('<w:p><w:pPr>' + (section if index < len(FONTS)-1 else '')
                    + '</w:pPr><w:r><w:t>AFTER</w:t></w:r></w:p>')
    body.append(section)
    parts['word/document.xml'] = (f'<w:document xmlns:w="{w}"><w:body>'
                                  + ''.join(body) + '</w:body></w:document>')
    # No table entries for the tested names, and no embedded fonts.
    parts['word/fontTable.xml'] = f'<w:fonts xmlns:w="{w}"><w:font w:name="Arial"/></w:fonts>'
    with ZipFile(path, 'w', ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path):
    import pymupdf
    # Word for Mac 16.113.3, fresh process: first three pages identical.
    latin = [72, 81.968, 85.250, 101.250, 107.258, 123.258, 132.780, 141.634, 150.488]
    square = [72, 80, 88, 104, 120, 136, 160.007, 168.015, 176.023]
    after = [72, 80.004, 87.334, 94.663, 102.667]
    with pymupdf.open(path) as pdf:
        assert len(pdf) == len(FONTS), f'{path}: expected five pages, got {len(pdf)}'
        for index, page in enumerate(pdf):
            chars = [char for block in page.get_text('rawdict')['blocks']
                     for line in block.get('lines', []) for span in line['spans']
                     for char in span['chars'] if char['c'].strip()]
            assert ''.join(char['c'] for char in chars) == 'A.甲“乙”123AFTER', (index+1, chars)
            positions = [(x, 88.08) for x in (latin if index < 3 else square)]
            positions += [(x, 103.92) for x in after]
            for char, expected in zip(chars, positions):
                # Known faces can paint a narrow substitute quote inside its
                # square advance. The following glyph tests that advance;
                # only the missing-name cases require Latin quote origins.
                if index >= 3 and char['c'] in '“”':
                    continue
                assert all(abs(a-b) < .3 for a, b in zip(char['origin'], expected)), (
                    index+1, FONTS[index], char['c'], char['origin'], expected)
    print('  ✔ Undeclared English GB2312 names: five Mac Word origin controls pass')


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
        with tempfile.TemporaryDirectory(prefix='office-missing-gb-fonts-') as directory:
            doc, pdf = [Path(directory) / name for name in ('names.docx', 'names.pdf')]
            fixture(doc)
            env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': 'mac'}
            subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], env=env, check=True)
            check(pdf)


if __name__ == '__main__':
    main()
