#!/usr/bin/env python3
"""Word controls for small pictures beside larger text on a line grid.

Each size has twelve pages: five image heights with/without a grid, then two
picture-only safeguards. Word's text-dominant baselines and all following-line
positions are checked. The existing larger-picture baseline residual at 24pt
is deliberately not made a golden position for future corrections to preserve.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED
import zlib

CASES = [(grid, height, 'AB') for grid in (True, False)
         for height in (0, 10, 20, 35, 50)] + [(True, 20, ''), (True, 50, '')]
# (AB baseline, following paragraph baseline), Word 16.113.3 for Mac.
EXPECTED = {
    24: [(96.48, 114.48), (96.48, 114.48), (96.48, 114.48),
         (None, 130.08), (None, 145.68), (94.56, 110.88),
         (94.56, 110.88), (94.56, 110.88), (107.04, 123.36),
         (122.16, 138.48), (None, 114.48), (None, 145.68)],
    48: [(120.72, 145.68), (120.72, 145.68), (120.72, 145.68),
         (120.72, 145.68), (123.12, 145.68), (117.12, 138.48),
         (117.12, 138.48), (117.12, 138.48), (117.12, 138.48),
         (122.16, 143.52), (None, 114.48), (None, 145.68)],
}


def fixture(path, size):
    spec = importlib.util.spec_from_file_location(
        'seed', Path(__file__).with_name('office-grid-band.py'))
    seed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(seed)
    buffer = io.BytesIO()
    seed.fixture(buffer)
    with ZipFile(buffer) as package:
        parts = {name: package.read(name) for name in package.namelist()}
    w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    a = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    wp = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
    pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture'
    rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

    def chunk(name, data):
        return (struct.pack('>I', len(data)) + name + data
                + struct.pack('>I', zlib.crc32(name + data) & 0xffffffff))

    parts['word/media/probe.png'] = (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(b'\0\x40\x80\xc0')) + chunk(b'IEND', b''))
    parts['[Content_Types].xml'] = parts['[Content_Types].xml'].decode().replace(
        '</Types>', '<Default Extension="png" ContentType="image/png"/></Types>')
    parts['word/_rels/document.xml.rels'] = parts['word/_rels/document.xml.rels'].decode().replace(
        '</Relationships>', f'<Relationship Id="rIdProbe" Type="{rel}/image" '
        'Target="media/probe.png"/></Relationships>')
    section = ('<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="12240" w:h="15840"/>'
               '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/>'
               '<w:docGrid w:type="lines" w:linePitch="312"/></w:sectPr>')
    body = []
    for index, (grid, height, text) in enumerate(CASES):
        image = ''
        if height:
            image = (
                '<w:r><w:rPr><w:sz w:val="24"/></w:rPr><w:drawing><wp:inline>'
                f'<wp:extent cx="254000" cy="{height*12700}"/>'
                f'<wp:docPr id="{index+1}" name="probe"/><a:graphic>'
                f'<a:graphicData uri="{pic}"><pic:pic><pic:nvPicPr>'
                f'<pic:cNvPr id="{index+1}" name="probe"/><pic:cNvPicPr/></pic:nvPicPr>'
                '<pic:blipFill><a:blip r:embed="rIdProbe"/><a:stretch><a:fillRect/>'
                '</a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/>'
                f'<a:ext cx="254000" cy="{height*12700}"/></a:xfrm>'
                '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
                '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')
        run = (f'<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
               f'<w:sz w:val="{size*2}"/></w:rPr><w:t>{text}</w:t></w:r>') if text else ''
        off = '' if grid else '<w:snapToGrid w:val="0"/>'
        body.append('<w:p><w:pPr><w:spacing w:line="240" w:lineRule="atLeast"/>'
                    + off + '</w:pPr>' + image + run + '</w:p>')
        body.append('<w:p><w:pPr><w:snapToGrid w:val="0"/>'
                    + (section if index < len(CASES) - 1 else '')
                    + '</w:pPr><w:r><w:t>AFTER</w:t></w:r></w:p>')
    body.append(section)
    parts['word/document.xml'] = (
        f'<w:document xmlns:w="{w}" xmlns:wp="{wp}" xmlns:a="{a}" '
        f'xmlns:pic="{pic}" xmlns:r="{rel}"><w:body>'
        + ''.join(body) + '</w:body></w:document>')
    with ZipFile(path, 'w', ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path, size):
    import pymupdf
    with pymupdf.open(path) as document:
        assert len(document) == len(CASES), f'{path}: expected twelve pages'
        for index, (page, case, expected) in enumerate(zip(document, CASES, EXPECTED[size]), 1):
            spans = [span for block in page.get_text('dict')['blocks']
                     for line in block.get('lines', []) for span in line['spans']]
            for text, target in [('AB', expected[0]), ('AFTER', expected[1])]:
                positions = [span['origin'][1] for span in spans if span['text'].strip() == text]
                if text == 'AB' and not case[2]:
                    assert not positions, (index, text, positions)
                    continue
                assert len(positions) == 1, (index, text, positions)
                if target is not None:
                    assert abs(positions[0] - target) <= .5, (
                        f'page {index} {text}: expected {target}, got {positions[0]}')
    print(f'  ✔ Grid pictures with {size}pt text: twelve Word controls pass')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--fixture', type=Path)
    group.add_argument('--pdf', type=Path)
    group.add_argument('--binary', type=Path)
    parser.add_argument('--size', type=int, choices=(24, 48), default=24)
    args = parser.parse_args()
    if args.fixture:
        fixture(args.fixture, args.size)
    elif args.pdf:
        check(args.pdf, args.size)
    else:
        with tempfile.TemporaryDirectory(prefix='office-picture-text-grid-') as directory:
            for size in (24, 48):
                doc = Path(directory) / f'picture-text-{size}.docx'
                fixture(doc, size)
                for mode in ('windows', 'mac'):
                    pdf = Path(directory) / f'{size}-{mode}.pdf'
                    env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': mode}
                    subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)],
                                   env=env, check=True)
                    check(pdf, size)


if __name__ == '__main__':
    main()
