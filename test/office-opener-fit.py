#!/usr/bin/env python3
"""Guard Mac Word's kinsoku-off compression of a line-final opening mark.

Fresh Word controls at 14pt keep an opener 10pt over after Han, but only
4pt over after a paired mark. Breaking a pair restores its shared blank
half, reducing the alternative line's stretch room. Test both sides of
those boundaries, with and without a character grid; use an explicit
embedded face so native and browser can render identical bytes.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

CASES = [(before, over, taken) for before, limits in
         [('甲', (10, 12)), ('「', (4, 6)), ('）', (4, 6))]
         for over, taken in zip(limits, (True, False))]
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'


def fixture(path):
    blocks = []
    def section(grid):
        return ('<w:sectPr><w:type w:val="nextPage"/>'
                '<w:pgSz w:w="12240" w:h="15840"/>'
                '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/>'
                + ('<w:docGrid w:type="linesAndChars" w:linePitch="400" w:charSpace="4096"/>' if grid else '')
                + '</w:sectPr>')
    for grid in (0, 1):
        for i, (before, over, _) in enumerate(CASES):
            if i:
                blocks.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
            text = '甲' * 8 + '，' + '甲' * 8 + '，' + '甲' * 9 + before + '（' + '乙' * 8
            width = 29 * (14 + grid) - over - ((14 + grid) / 2 if before != '甲' else 0)
            blocks.append('<w:p><w:pPr><w:spacing w:line="400" w:lineRule="exact"/>'
                          f'<w:ind w:left="0" w:firstLine="0" w:right="{round((468-width)*20)}"/>'
                          '<w:jc w:val="both"/><w:kinsoku w:val="0"/>'
                          '<w:autoSpaceDE w:val="0"/><w:autoSpaceDN w:val="0"/>'
                          f'</w:pPr><w:r><w:t>{text}</w:t></w:r></w:p>')
        if not grid:
            blocks.append('<w:p><w:pPr>' + section(0) + '</w:pPr></w:p>')
    document = f'<w:document xmlns:w="{W}"><w:body>' + ''.join(blocks) + section(1) + '</w:body></w:document>'
    styles = (f'<w:styles xmlns:w="{W}"><w:docDefaults><w:rPrDefault><w:rPr>'
              '<w:rFonts w:ascii="Starling Opener CJK Test" w:hAnsi="Starling Opener CJK Test" w:eastAsia="Starling Opener CJK Test"/>'
              '<w:sz w:val="28"/><w:lang w:val="en-US" w:eastAsia="zh-TW"/>'
              '</w:rPr></w:rPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
              '<w:rPr><w:sz w:val="28"/></w:rPr></w:style></w:styles>')
    settings = (f'<w:settings xmlns:w="{W}"><w:characterSpacingControl w:val="compressPunctuation"/>'
                '<w:compat><w:useFELayout/><w:compatSetting w:name="compatibilityMode" '
                'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
    types = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
    for name, kind in [('document', 'document.main'), ('styles', 'styles'), ('settings', 'settings'), ('fontTable', 'fontTable')]:
        types += f'<Override PartName="/word/{name}.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.{kind}+xml"/>'
    types += '<Default Extension="odttf" ContentType="application/vnd.openxmlformats-officedocument.obfuscatedFont"/></Types>'
    rel_ns = 'http://schemas.openxmlformats.org/package/2006/relationships'
    rel_type = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
    root_rels = f'<Relationships xmlns="{rel_ns}"><Relationship Id="rId1" Type="{rel_type}officeDocument" Target="word/document.xml"/></Relationships>'
    doc_rels = f'<Relationships xmlns="{rel_ns}">' + ''.join(
        f'<Relationship Id="rId{i}" Type="{rel_type}{name}" Target="{name}.xml"/>'
        for i, name in enumerate(['styles', 'settings', 'fontTable'], 1)) + '</Relationships>'
    key = 'C2E49068-46C1-47FC-A059-0E4DA203B525'
    font_table = (f'<w:fonts xmlns:w="{W}" xmlns:r="{rel_type[:-1]}">'
                  '<w:font w:name="Starling Opener CJK Test"><w:charset w:val="86"/>'
                  '<w:family w:val="swiss"/>'
                  f'<w:embedRegular r:id="rIdFont" w:fontKey="{{{key}}}"/>'
                  '</w:font></w:fonts>')
    font_rels = (f'<Relationships xmlns="{rel_ns}"><Relationship Id="rIdFont" '
                 f'Type="{rel_type}font" Target="fonts/opener.odttf"/></Relationships>')
    font = bytearray((Path(__file__).parent / 'fonts' / 'StarlingOpenerCJKTest.ttf').read_bytes())
    mask = bytes.fromhex(key.replace('-', ''))[::-1]
    for i in range(32):
        font[i] ^= mask[i % 16]
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as out:
        out.writestr('word/fonts/opener.odttf', font)
        for name, text in {'[Content_Types].xml': types, '_rels/.rels': root_rels,
                           'word/document.xml': document, 'word/styles.xml': styles,
                           'word/settings.xml': settings, 'word/_rels/document.xml.rels': doc_rels,
                           'word/fontTable.xml': font_table, 'word/_rels/fontTable.xml.rels': font_rels}.items():
            out.writestr(name, '<?xml version="1.0" encoding="UTF-8"?>' + text)


def check(path):
    import pymupdf
    with pymupdf.open(path) as pdf:
        assert len(pdf) == 2 * len(CASES), f'{path}: expected 12 pages, got {len(pdf)}'
        for n, page in enumerate(pdf):
            before, over, taken = CASES[n % len(CASES)]
            lines = [''.join(s['text'] for s in line['spans'])
                     for block in page.get_text('dict')['blocks'] for line in block.get('lines', [])]
            # Word may export an empty section paragraph as a NUL-only span.
            lines = [''.join(t.split()) for t in lines if t.strip(' \t\r\n\x00')]
            expected = '甲' * 8 + '，' + '甲' * 8 + '，' + '甲' * 9 + before
            assert len(lines) == 2, f'page {n+1}: expected two text lines, got {lines}'
            assert lines[0] == expected + ('（' if taken else ''), f'page {n+1}: wrong break: {lines}'
            assert lines[1] == ('' if taken else '（') + '乙' * 8, f'page {n+1}: text lost or duplicated: {lines}'
    print('  ✔ opening-mark compression: 12 Word boundary controls pass')


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
        with tempfile.TemporaryDirectory(prefix='office-opener-fit-') as directory:
            doc, pdf = (Path(directory) / name for name in ('openers.docx', 'openers.pdf'))
            fixture(doc)
            env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': 'mac'}
            subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], env=env, check=True)
            check(pdf)


if __name__ == '__main__':
    main()
