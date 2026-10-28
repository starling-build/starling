#!/usr/bin/env python3
"""Verify available and absent alternates of missing Mac Word title fonts.

Fresh Word prints pair explicit Arial Unicode MS, SimHei and YaHei with missing
names that choose those faces. Check text, baselines and pair equality, not glyph
outlines: the app deliberately uses bundled stand-ins for proprietary faces.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
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
    fonts = [('Arial Unicode MS', None), ('方正StarlingArialControl', 'Arial Unicode MS'),
             ('黑体', None), ('方正StarlingHeiControl', '黑体'),
             ('微软雅黑', None), ('方正StarlingMissingControl', None)]
    font_xml, body = [], []
    for i, (font, alternate) in enumerate(fonts):
        alt = f'<w:altName w:val="{alternate}"/>' if alternate else ''
        font_xml.append(f'<w:font w:name="{font}"><w:charset w:val="86"/>'
                        f'<w:family w:val="auto"/>{alt}</w:font>')
        for j, text in enumerate(['甲乙丙丁甲乙丙丁', '丙丁甲乙丙丁甲乙', '乙丙丁甲乙丙丁甲']):
            char = (f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:eastAsia="{font}"/>'
                    '<w:sz w:val="36"/>')
            page = '<w:pageBreakBefore/>' if i and j == 0 else ''
            body.append(f'<w:p><w:pPr>{page}<w:spacing w:line="336" w:lineRule="auto"/>'
                        f'<w:rPr>{char}</w:rPr></w:pPr><w:r><w:rPr>{char}</w:rPr>'
                        f'<w:t>{text}</w:t></w:r></w:p>')
    body.append('<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
                '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/>'
                '<w:docGrid w:type="lines" w:linePitch="312"/></w:sectPr>')
    parts['word/document.xml'] = (f'<w:document xmlns:w="{opener.W}"><w:body>'
                                 + ''.join(body) + '</w:body></w:document>')
    parts['word/fontTable.xml'] = f'<w:fonts xmlns:w="{opener.W}">' + ''.join(font_xml) + '</w:fonts>'
    parts['word/settings.xml'] = parts['word/settings.xml'].replace(b'w:val="15"', b'w:val="14"')
    # These controls use Word's installed faces and the app's bundled stand-ins.
    for name in ('word/fonts/opener.odttf', 'word/_rels/fontTable.xml.rels'):
        parts.pop(name, None)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path):
    import pymupdf
    expected_text = ['甲乙丙丁甲乙丙丁', '丙丁甲乙丙丁甲乙', '乙丙丁甲乙丙丁甲']
    word_baselines = [(102.72, 157.44, 212.40), (94.08, 133.20, 172.56),
                      (94.80, 133.92, 173.28)]
    pair_origins = []
    with pymupdf.open(path) as pdf:
        assert len(pdf) == 6, f'{path}: expected 6 pages, got {len(pdf)}'
        for n, page in enumerate(pdf):
            lines = [line for block in page.get_text('dict')['blocks']
                     for line in block.get('lines', [])
                     if any(span['text'].strip(' \t\r\n\x00') for span in line['spans'])]
            text = [''.join(''.join(span['text'] for span in line['spans']).split()) for line in lines]
            assert text == expected_text, f'page {n+1}: expected {expected_text}, got {text}'
            origins = [line['spans'][0]['origin'] for line in lines]
            for origin, expected_y in zip(origins, word_baselines[n // 2]):
                assert abs(origin[0] - 72) < 0.3 and abs(origin[1] - expected_y) < 0.3, (
                    f'page {n+1}: expected baseline (72, {expected_y}), got {origin}')
            if n % 2:
                assert all(abs(a-b) < 0.01 for p, q in zip(pair_origins, origins)
                           for a, b in zip(p, q)), f'page {n+1}: alternate differs from its explicit face'
            else:
                pair_origins = origins
    print('  ✔ Missing-font alternates: 6 Word baseline controls pass')

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
        with tempfile.TemporaryDirectory(prefix='office-font-alternates-') as directory:
            doc, pdf = (Path(directory) / name for name in ('font-alternates.docx', 'font-alternates.pdf'))
            fixture(doc)
            env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': 'mac'}
            subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], env=env, check=True)
            check(pdf)


if __name__ == '__main__':
    main()
