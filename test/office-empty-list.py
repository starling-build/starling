#!/usr/bin/env python3
"""Word controls for explicit mark visibility and empty-list alignment.

Eighteen pages cover left/center/right, normal/hidden paragraph styles, and
explicit visible/hidden or inherited marks. Saved copies must preserve the
visibility overrides. General hidden body runs are outside these controls.
"""
import argparse
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

CASES = [(align, style, mark) for align in ('left', 'center', 'right')
         for style, mark in [('Hidden', 'off'), ('Hidden', 'omit'), ('Hidden', 'on'),
                             ('Normal', 'off'), ('Normal', 'omit'), ('Normal', 'on')]]
# Label x coordinates, Word for Mac 16.113.3; None means no visible label.
LABEL_X = [72, None, None, 72, 72, None, 299.665924, None, None,
           301.332947, 300.330963, None, 526.669922, None, None,
           528.662170, 527.332092, None]


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
    parts['word/styles.xml'] = parts['word/styles.xml'].decode().replace(
        '</w:styles>', '<w:style w:type="paragraph" w:styleId="Hidden"><w:name w:val="Hidden"/>'
        '<w:basedOn w:val="Normal"/><w:rPr><w:vanish/></w:rPr></w:style></w:styles>')
    body, numbers = [], []
    for index, (align, style, mark) in enumerate(CASES):
        number = index + 1
        numbers.append(f'<w:num w:numId="{number}"><w:abstractNumId w:val="0"/></w:num>')
        properties = ('' if mark == 'omit' else
                      f'<w:rPr><w:vanish w:val="{0 if mark == "off" else 1}"/></w:rPr>')
        body.append(f'<w:p><w:pPr><w:pStyle w:val="{style}"/><w:numPr><w:ilvl w:val="0"/>'
                    f'<w:numId w:val="{number}"/></w:numPr><w:jc w:val="{align}"/>'
                    + properties + '</w:pPr></w:p>')
        body.append('<w:p><w:pPr>' + (section if index < len(CASES)-1 else '')
                    + '</w:pPr><w:r><w:t>AFTER</w:t></w:r></w:p>')
    body.append(section)
    parts['word/document.xml'] = (f'<w:document xmlns:w="{w}"><w:body>'
                                  + ''.join(body) + '</w:body></w:document>')
    parts['word/numbering.xml'] = (f'<w:numbering xmlns:w="{w}"><w:abstractNum w:abstractNumId="0">'
        '<w:multiLevelType w:val="singleLevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/>'
        '<w:numFmt w:val="upperLetter"/><w:lvlText w:val="%1"/><w:suff w:val="space"/>'
        '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="420" w:hanging="420"/></w:pPr>'
        '</w:lvl></w:abstractNum>' + ''.join(numbers) + '</w:numbering>')
    rels = parts['word/_rels/document.xml.rels'].decode()
    if '/numbering"' not in rels:
        rels = rels.replace('</Relationships>', '<Relationship Id="rIdNumberProbe" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" '
            'Target="numbering.xml"/></Relationships>')
    parts['word/_rels/document.xml.rels'] = rels
    types = parts['[Content_Types].xml'].decode()
    if '/word/numbering.xml' not in types:
        types = types.replace('</Types>', '<Override PartName="/word/numbering.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>')
    parts['[Content_Types].xml'] = types
    with ZipFile(path, 'w', ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, data)


def check(path):
    import pymupdf
    with pymupdf.open(path) as document:
        assert len(document) == len(CASES), f'{path}: expected eighteen pages'
        for index, (page, x) in enumerate(zip(document, LABEL_X)):
            spans = [(span['text'].strip(), span['origin'])
                     for block in page.get_text('dict')['blocks']
                     for line in block.get('lines', []) for span in line['spans']
                     if span['text'].strip()]
            expected = ([] if x is None else [(chr(65 + index), (x, 83.28))])
            expected.append(('AFTER', (72, 83.28 if x is None else 96.96)))
            assert len(spans) == len(expected), (index+1, spans, expected)
            for (text, point), (want_text, want_point) in zip(spans, expected):
                assert text == want_text and all(abs(a-b) <= .5 for a, b in zip(point, want_point)), (
                    index+1, text, point, want_text, want_point)
    print('  ✔ Empty list numbers: eighteen Word visibility/alignment controls pass')


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
        with tempfile.TemporaryDirectory(prefix='office-empty-list-') as directory:
            work = Path(directory)
            source = work/'empty-list.docx'
            fixture(source)
            for mode in ('windows', 'mac'):
                env = os.environ | {'OFFICE_FONT_SOURCE': 'bundled', 'OFFICE_WORD_FONTS': mode}
                saved = work/f'{mode}-saved.docx'
                def convert(doc, out):
                    subprocess.run([str(args.binary.resolve()), '--convert', str(doc), str(out)],
                                   env=env, check=True)
                convert(source, saved)
                with ZipFile(saved) as package:
                    assert package.read('word/document.xml').count(b'<w:vanish w:val="0"/>') == 6
                for label, doc in [('original', source), ('saved', saved)]:
                    pdf = work/f'{mode}-{label}.pdf'
                    convert(doc, pdf)
                    check(pdf)


if __name__ == '__main__':
    main()
