#!/usr/bin/env python3
"""Word's page-foot clearance for ordinary and vertically merged table rows.

Fresh Mac Word prints of these mode-12 controls require the full closing
border, including with no top border or a heavier top border. Windows mode
retains its separately measured legacy rule; these controls do not certify
a Windows-native build or replace the full corpus pair.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

CASES = [(border, border, room, merge) for border, rooms in [(.5, [20.65, 20.85, 21.05]), (1.5, [22.1, 22.5, 23.1])]
         for room in rooms for merge in [False, True]]
CASES += [(top, .5, room, merge) for top, rooms in [(0, [20.35, 20.6]), (1.5, [21.85, 22.1])]
          for room in rooms for merge in [False, True]]
# Page-one presence of the marked row, read from the fresh Word PDFs.
WORD_FIRST = [False, False, False, False, True, True, False, False, False, False, True, True,
              False, False, True, True, False, False, True, True]
# Preserve the accepted Windows-mode result, not a new Windows Word oracle.
WINDOWS_FIRST = [False, False, True, True, True, True, False, False, True, True, True, True,
                 True, True, True, True, True, True, True, True]


def label(index):
    return f'ROW{index:02d}'


def fixture(path):
    spec = importlib.util.spec_from_file_location('seed', Path(__file__).with_name('office-simhei-lines.py'))
    seed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(seed)
    buf = io.BytesIO()
    seed.fixture(buf)
    with ZipFile(buf) as z:
        parts = {name: z.read(name) for name in z.namelist()}
    ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    section = ('<w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="12240" w:h="15840"/>'
               '<w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr>')

    def paragraph(text):
        return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="200" w:lineRule="exact"/>'
                '<w:widowControl w:val="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
                '<w:sz w:val="20"/></w:rPr><w:t>' + text + '</w:t></w:r></w:p>')

    body = []
    for index, (top, border, room, merged) in enumerate(CASES):
        body.append('<w:p><w:pPr><w:spacing w:before="0" w:after="0" '
                    f'w:line="{round((648-room)*20)}" w:lineRule="exact"/>'
                    '<w:widowControl w:val="0"/></w:pPr></w:p>')
        rules = ''.join(f'<w:{side} w:val="{"nil" if side=="top" and top==0 else "single"}" '
                        f'w:sz="{int((top if side=="top" else border)*8)}"/>'
                        for side in ['top', 'bottom', 'left', 'right', 'insideH', 'insideV'])
        table = ('<w:tbl><w:tblPr><w:tblW w:type="dxa" w:w="6000"/><w:tblLayout w:type="fixed"/>'
                 '<w:tblBorders>' + rules + '</w:tblBorders><w:tblCellMar><w:top w:w="0" w:type="dxa"/>'
                 '<w:bottom w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
                 '<w:tblGrid><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/></w:tblGrid>')
        for row in [0, 1]:
            table += '<w:tr><w:trPr><w:trHeight w:val="400" w:hRule="atLeast"/></w:trPr>'
            for column in [0, 1]:
                merge = ('<w:vMerge w:val="restart"/>' if row==0 else '<w:vMerge/>') if merged and column==0 else ''
                text = ('M' if row==0 or not merged else '') if column==0 else label(index)+('A' if row==0 else 'B')
                table += '<w:tc><w:tcPr><w:tcW w:type="dxa" w:w="3000"/>'+merge+'</w:tcPr>'+paragraph(text)+'</w:tc>'
            table += '</w:tr>'
        body.append(table+'</w:tbl>')
        body.append('<w:p><w:pPr><w:spacing w:line="20" w:lineRule="exact"/>'
                    + (section if index<len(CASES)-1 else '') + '</w:pPr></w:p>')
    parts['word/document.xml'] = (f'<w:document xmlns:w="{ns}"><w:body>'+''.join(body)+section+'</w:body></w:document>').encode()
    with ZipFile(path, 'w', ZIP_DEFLATED) as z:
        for name, data in parts.items():
            z.writestr(name, data)


def check(pdf, mode='mac'):
    import pymupdf
    with pymupdf.open(pdf) as doc:
        assert len(doc)==40, f'{mode}: {len(doc)} pages instead of 40'
        text = [page.get_text() for page in doc]
    expected = WORD_FIRST if mode=='mac' else WINDOWS_FIRST
    for index, first in enumerate(expected):
        pages = [n+1 for n, content in enumerate(text) if label(index)+'A' in content]
        want = 2*index+(1 if first else 2)
        assert pages==[want], f'{mode} {CASES[index]}: first row on {pages}, expected {[want]}'
        last = [n+1 for n, content in enumerate(text) if label(index)+'B' in content]
        assert last==[2*index+2], f'{mode} {CASES[index]}: later row moved or disappeared: {last}'
    print(f'  ✔ Row closing borders {mode}: 20 ordinary/merged controls, 40 pages')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--generate', type=Path)
    p.add_argument('--pdf', type=Path)
    p.add_argument('--mode', choices=['mac', 'windows'], default='mac')
    p.add_argument('--binary', type=Path)
    args = p.parse_args()
    if args.generate:
        fixture(args.generate)
    elif args.pdf:
        check(args.pdf, args.mode)
    elif args.binary:
        with tempfile.TemporaryDirectory(prefix='office-row-border-') as work:
            doc = Path(work)/'row-border.docx'
            fixture(doc)
            for mode in ['mac', 'windows']:
                pdf = Path(work)/(mode+'.pdf')
                subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(pdf)], check=True,
                               env=os.environ | {'OFFICE_WORD_FONTS': mode, 'OFFICE_FONT_SOURCE': 'bundled'},
                               stdout=subprocess.DEVNULL)
                check(pdf, mode)
    else:
        p.error('pass --generate, --pdf, or --binary')


if __name__=='__main__':
    main()
