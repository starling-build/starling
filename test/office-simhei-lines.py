#!/usr/bin/env python3
"""Mac Word's automatic SimHei line advances, measured at five sizes.

The same 24 lines occur as separate paragraphs and as forced breaks. Both
Chinese and English font names are tested. The oracle is a fresh Mac Word
print of this generated package; it does not assert Windows-host fidelity.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

SIZES = [10, 10.5, 12, 14, 18]
CASES = [(face, size, kind) for face in ['黑体', 'SimHei']
         for size in SIZES for kind in ['paragraphs', 'breaks']]


def fixture(path):
    w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    section = ('<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="11906" w:h="16838"/>'
               '<w:pgMar w:top="1440" w:bottom="1440" w:left="1800" w:right="1800"/></w:sectPr>')
    body = []
    for index, (face, size, kind) in enumerate(CASES):
        char = (f'<w:rPr><w:rFonts w:ascii="{face}" w:hAnsi="{face}" w:eastAsia="{face}"/>'
                f'<w:sz w:val="{int(size*2)}"/><w:szCs w:val="{int(size*2)}"/>'
                '<w:lang w:val="zh-CN" w:eastAsia="zh-CN"/></w:rPr>')
        para = ('<w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
                '<w:snapToGrid w:val="0"/><w:widowControl w:val="0"/>' + char + '</w:pPr>')
        runs = [f'<w:r>{char}<w:t>甲乙丙丁{n+1}</w:t></w:r>' for n in range(24)]
        body.append(''.join('<w:p>'+para+run+'</w:p>' for run in runs) if kind == 'paragraphs'
                    else '<w:p>'+para+f'<w:r>{char}<w:br/></w:r>'.join(runs)+'</w:p>')
        body.append('<w:p><w:pPr><w:spacing w:line="20" w:lineRule="exact"/>'
                    + (section if index < len(CASES)-1 else '') + '</w:pPr></w:p>')
    parts = {
        '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
            '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
            '</Types>',
        '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
        'word/_rels/document.xml.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>',
        'word/document.xml': f'<w:document xmlns:w="{w}"><w:body>'+''.join(body)+section+'</w:body></w:document>',
        'word/settings.xml': f'<w:settings xmlns:w="{w}"><w:compat><w:compatSetting w:name="compatibilityMode" '
            'w:uri="http://schemas.microsoft.com/office/word" w:val="12"/></w:compat></w:settings>',
    }
    with ZipFile(path, 'w', ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def positions(pdf):
    import pymupdf
    with pymupdf.open(pdf) as document:
        return [[line['spans'][0]['origin'][1]
                 for block in page.get_text('dict')['blocks'] for line in block.get('lines', [])
                 if ''.join(span['text'] for span in line['spans']).startswith('甲乙丙丁')]
                for page in document]


def check(pdf, mode):
    import json
    pages = positions(pdf)
    oracle = json.loads(Path(__file__).with_name('office-simhei-lines-word.json').read_text())
    assert len(pages) == len(CASES), f'{mode}: {len(pages)} pages, expected {len(CASES)}'
    for index, (ys, case) in enumerate(zip(pages, CASES)):
        assert len(ys) == 24, f'{mode} {case}: {len(ys)} lines, expected 24'
        relative = [y-ys[0] for y in ys]
        if mode == 'mac':
            expected = [y-oracle[index][0] for y in oracle[index]]
            error = max(abs(a-b) for a,b in zip(relative, expected))
            assert error <= 0.25, f'{mode} {case}: line advance differs from Word by {error:.4f}pt'
        else:
            # Preserve the pre-change Windows-mode metric. This is not a
            # fresh Word-for-Windows oracle or a Windows-native receipt.
            error = max(abs(y-n*case[1]*1.3) for n,y in enumerate(relative))
            assert error <= 0.01, f'{mode} {case}: existing metric moved by {error:.4f}pt'
        if index % 2:
            previous = [y-pages[index-1][0] for y in pages[index-1]]
            assert max(abs(a-b) for a,b in zip(relative, previous)) < 0.01, f'{mode} {case}: break/paragraph advances differ'
    print(f'  ✔ SimHei {mode}: 20 pages, five sizes, both names and both paragraph forms')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate', type=Path)
    parser.add_argument('--binary', type=Path)
    args = parser.parse_args()
    if args.generate:
        fixture(args.generate)
        return
    if not args.binary:
        parser.error('pass --generate or --binary')
    with tempfile.TemporaryDirectory(prefix='office-simhei-lines-') as tmp:
        doc = Path(tmp)/'simhei-lines.docx'
        fixture(doc)
        for mode in ['mac', 'windows']:
            pdf = Path(tmp)/(mode+'.pdf')
            subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], check=True,
                           env=os.environ | {'OFFICE_WORD_FONTS': mode, 'OFFICE_FONT_SOURCE': 'bundled'},
                           stdout=subprocess.DEVNULL)
            check(pdf, mode)


if __name__ == '__main__':
    main()
