#!/usr/bin/env python3
"""Explicit paragraph kinsoku works with or without the FE-layout switch.

Fresh Word prints give identical line breaks in both packages. Turning kinsoku
off permits a closing mark at a line start and a Chinese opening mark at its
end; turning it on preserves the usual punctuation restrictions.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import re
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

CASES = [(text, off) for text in ['甲乙丙丁，戊己', '甲乙丙丁）戊己',
                                 '甲乙丙（丁戊己', '甲乙丙丁。戊己'] for off in [True, False]]
CASES += [('甲乙丙丁戊己庚辛，壬癸', off) for off in [True, False]]
PORTABLE_CASES = [(text, off) for text in ['甲乙甲乙，甲乙', '甲乙甲乙）甲乙',
                                          '甲乙甲（乙甲乙', '甲乙甲「乙甲乙'] for off in [True, False]]


def fixture(path, fe=False, portable=False):
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
    # The existing FE path has its own mixed-size marker-height gap. Keep
    # its eight break controls unchanged; the new height guard covers only
    # the path introduced here (no FE layout).
    cases = PORTABLE_CASES if portable else CASES[:8] if fe else CASES
    for index, (text, off) in enumerate(cases):
        mixed = index >= 8
        line, right = (322, 7360) if mixed else (240, 8080)
        if mixed:
            runs = ''.join('<w:r><w:rPr><w:rFonts w:ascii="FangSong" w:hAnsi="FangSong" w:eastAsia="FangSong"/>'
                           f'<w:sz w:val="{size}"/><w:lang w:val="zh-CN" w:eastAsia="zh-CN"/></w:rPr>'
                           f'<w:t>{part}</w:t></w:r>' for part, size in [(text[:6], 31), (text[6:], 30)])
        else:
            face = 'Starling Opener CJK Test' if portable else 'SimSun'
            runs = (f'<w:r><w:rPr><w:rFonts w:ascii="{face}" w:hAnsi="{face}" w:eastAsia="{face}"/>'
                    '<w:sz w:val="32"/><w:lang w:val="zh-CN" w:eastAsia="zh-CN"/></w:rPr>'
                    f'<w:t>{text}</w:t></w:r>')
        body.append(f'<w:p><w:pPr><w:spacing w:line="{line}" w:lineRule="auto"/>'
                    f'<w:ind w:right="{right}"/><w:kinsoku w:val="{0 if off else 1}"/>'
                    '<w:overflowPunct w:val="0"/><w:autoSpaceDE w:val="0"/><w:autoSpaceDN w:val="0"/>'
                    '</w:pPr>' + runs + '</w:p>')
        body.append('<w:p><w:pPr>' + (section if index < len(cases)-1 else '')
                    + '</w:pPr><w:r><w:t>AFTER</w:t></w:r></w:p>')
    body.append(section)
    parts['word/document.xml'] = (f'<w:document xmlns:w="{w}"><w:body>'
                                  + ''.join(body) + '</w:body></w:document>')
    settings = re.sub(r'<w:useFELayout\b[^>]*/>', '', parts['word/settings.xml'].decode())
    settings = re.sub(r'<w:characterSpacingControl\b[^>]*/>', '', settings)
    settings = settings.replace('</w:settings>', '<w:characterSpacingControl w:val="doNotCompress"/></w:settings>')
    if fe:
        assert '</w:compat>' in settings
        settings = settings.replace('</w:compat>', '<w:useFELayout/></w:compat>')
    parts['word/settings.xml'] = settings
    if portable:
        # Reuse the licensed, embedded CJK face from the opener controls.
        # Browser tests must not depend on Chinese fonts installed on a Mac.
        spec = importlib.util.spec_from_file_location('opener', Path(__file__).with_name('office-opener-fit.py'))
        opener = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(opener)
        buffer = io.BytesIO()
        opener.fixture(buffer)
        with ZipFile(buffer) as package:
            for name in package.namelist():
                if name.startswith('word/fonts/') or name in ['word/fontTable.xml', 'word/_rels/fontTable.xml.rels']:
                    parts[name] = package.read(name)
        types = parts['[Content_Types].xml'].decode()
        if 'Extension="odttf"' not in types:
            types = types.replace('</Types>', '<Default Extension="odttf" ContentType="application/vnd.openxmlformats-officedocument.obfuscatedFont"/></Types>')
        if '/word/fontTable.xml' not in types:
            types = types.replace('</Types>', '<Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/></Types>')
        parts['[Content_Types].xml'] = types
        rels = parts['word/_rels/document.xml.rels'].decode()
        if '/fontTable"' not in rels:
            rels = rels.replace('</Relationships>', '<Relationship Id="rIdKinsokuFont" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable" Target="fontTable.xml"/></Relationships>')
        parts['word/_rels/document.xml.rels'] = rels
    with ZipFile(path, 'w', ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path, fe=False, portable=False):
    import pymupdf
    cases = PORTABLE_CASES if portable else CASES[:8] if fe else CASES
    with pymupdf.open(path) as pdf:
        assert len(pdf) == len(cases), f'{path}: expected {len(cases)} pages, got {len(pdf)}'
        mixed_origins = None
        for index, (page, (text, off)) in enumerate(zip(pdf, cases)):
            lines = [line for block in page.get_text('dict')['blocks'] for line in block.get('lines', [])]
            actual = [''.join(span['text'] for span in line['spans']).strip() for line in lines]
            split = 6 if index >= 8 else 4 if off else 3
            expected = [text[:split], text[split:], 'AFTER']
            assert actual == expected, (index+1, actual, expected)
            if index >= 8:
                # Word's mixed-size pair has identical line positions. This
                # guards against synthetic breaks adding height; it does not
                # assert the app's unresolved absolute mixed-size baselines.
                origins = [line['spans'][0]['origin'] for line in lines]
                if mixed_origins is not None:
                    assert all(abs(a-b) < .001 for p, q in zip(origins, mixed_origins)
                               for a, b in zip(p, q)), ('break marker changed line height', origins, mixed_origins)
                mixed_origins = origins
                continue
            baselines = [94.08, 124.08, 143.52] if portable else [88.08, 108.72, 124.8]
            for line, y in zip(lines, baselines):
                x_actual, y_actual = line['spans'][0]['origin']
                assert abs(x_actual-72) < .3 and abs(y_actual-y) < .3, (index+1, x_actual, y_actual, y)
    print('  ✔ Explicit kinsoku switch: eight Word breaks' + ('' if fe or portable else ' and mixed-size height guard') + ' pass')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--fixture', type=Path)
    group.add_argument('--pdf', type=Path)
    group.add_argument('--binary', type=Path)
    parser.add_argument('--fe-layout', action='store_true')
    parser.add_argument('--portable', action='store_true', help='embedded CJK face, also usable in a browser')
    args = parser.parse_args()
    if args.fixture:
        fixture(args.fixture, args.fe_layout, args.portable)
    elif args.pdf:
        check(args.pdf, args.fe_layout, args.portable)
    else:
        with tempfile.TemporaryDirectory(prefix='office-kinsoku-switch-') as directory:
            for fe, portable in [(False, False), (True, False), (False, True), (True, True)]:
                doc = Path(directory) / f'kinsoku-{int(fe)}-{int(portable)}.docx'
                fixture(doc, fe, portable)
                for mode in ['mac', 'windows']:
                    pdf = doc.with_suffix('.' + mode + '.pdf')
                    env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': mode}
                    subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], env=env, check=True)
                    check(pdf, fe, portable)


if __name__ == '__main__':
    main()
