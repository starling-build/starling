#!/usr/bin/env python3
"""Tab stops in right-to-left paragraphs: measured from the right margin.

Five paragraphs (A4, 72pt margins, so the start edge is x=523.3): left, right and
centre stops 150pt from the start after a Hebrew word, then right and centre
stops 250pt in after a digit and at the line's start. A stop that sets left puts
the text's start edge at the stop, a right one its end edge, a centred one its
middle (the XML's left/right are start/end in a bidi paragraph — Word's print of
lo tdf129659, whose endnote text starts 35.45pt from the right at a left stop).

    test/office-rtl-tabs.py [path/to/OfficeApp]

Needs pymupdf; exits 1 on a mismatch."""
import os, subprocess, sys, tempfile, zipfile
import pymupdf

CT = ('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/></Relationships>')


def para(stop, text):
    return ('<w:p><w:pPr><w:bidi/><w:tabs>%s</w:tabs></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Times New Roman" '
            'w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/><w:rtl/></w:rPr>%s</w:r></w:p>' % (stop, text))


def t(s):
    return '<w:t xml:space="preserve">%s</w:t>' % s


TAB = '<w:tab/>'
BODY = ''.join([
    para('<w:tab w:val="left" w:pos="3000"/>', t('שלום') + TAB + t('עולם טוב')),
    para('<w:tab w:val="right" w:pos="3000"/>', t('שלום') + TAB + t('עולם טוב')),
    para('<w:tab w:val="center" w:pos="3000"/>', t('שלום') + TAB + t('עולם טוב')),
    para('<w:tab w:val="right" w:pos="5000"/>', t('1') + TAB + t('עולם טוב')),
    para('<w:tab w:val="center" w:pos="5000"/>', TAB + t('עולם טוב')),
])
DOC = ('<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
       '<w:body>%s<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" '
       'w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>' % BODY)

# (line, edge, expected x of that edge) — the text after the tab, "עולם טוב", per line.
EXPECT = [(0, 'right', 373.3), (1, 'left', 373.3), (2, 'middle', 373.3), (3, 'left', 273.3), (4, 'middle', 273.3)]


def main():
    app = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('OFFICE_APP', '.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp')
    with tempfile.TemporaryDirectory() as tmp:
        docx, pdf = os.path.join(tmp, 'a.docx'), os.path.join(tmp, 'a.pdf')
        with zipfile.ZipFile(docx, 'w') as z:
            z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS); z.writestr('word/document.xml', DOC)
        env = dict(os.environ, OFFICE_WORD_FONTS='windows', OFFICE_FONT_SOURCE='bundled')
        subprocess.run([app, '--convert', docx, pdf], env=env, check=True, capture_output=True)
        words = pymupdf.open(pdf)[0].get_text('words')
    lines = {}
    for w in words:
        lines.setdefault(round(w[3]), []).append(w)
    bad = 0
    for (y, ws), (i, edge, want) in zip(sorted(lines.items()), EXPECT):
        # the text after the tab: every word but the first (rightmost) one
        rest = sorted(ws, key=lambda w: -w[2])[1:] if i < 3 else sorted(ws, key=lambda w: -w[2])[(1 if i == 3 else 0):]
        lo, hi = min(w[0] for w in rest), max(w[2] for w in rest)
        got = {'right': hi, 'left': lo, 'middle': (lo + hi) / 2}[edge]
        ok = abs(got - want) < 0.6
        bad += not ok
        print('%s line %d %s edge %.1f (want %.1f)' % ('ok  ' if ok else 'FAIL', i, edge, got, want))
    sys.exit(1 if bad else 0)


main()
