#!/usr/bin/env python3
"""Lab gcap (for amd-opus): how much the marks before a character give on a character grid, in
Word for Windows. Ours caps them, two or more together, at 0.823 of a grid cell (lab tg:
zh-3c055c9b, 16pt on its 17pt cells). zh-7a16a243 (same grid: linesAndChars, charSpace 4127,
mode 15, compressPunctuation, 新細明體) takes "予" onto its cell line "的公益性、對價性、適法性下，可以給
予" 11.04pt over, its three marks setting 3.7pt narrower each (12pt text, 13pt cells), and its 10pt
footnote takes "財" 9.10 over with eight marks — both past the cap.
Each row: that paragraph from "的公益性" on, in a one-cell fixed table (the document's table style),
the cell width stepped by STEP twips over 16 widths so "予" runs from about 1.0 cell over down to
about 0.6 (BASE and STEP per row below).
  a  12pt (as the document)            d  16pt (w:sz 32)
  b  10pt (w:sz 20)                    e  12pt, in the body (no table; right indent stepped)
  c  14pt (w:sz 28)                    f  12pt, the first "、" written "之": two marks before 予, not three
Read: for each row, line 1's last characters (does it end at "予"); and for the first width of
each row that ends at "予", line 1's per-character x origins.
usage: gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, 'zh-7a16a243*.docx'))[0])
doc = z.read('word/document.xml').decode('utf-8')
TEXT = '的公益性、對價性、適法性下，可以給予容積獎勵。第一個還是回到適法性，適法性怎麼去解釋?'
RPR = '<w:rPr><w:color w:val="000000" w:themeColor="text1"/><w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr>'
def para(text, hp=24, right=None):
    ind = '' if right is None else '<w:ind w:right="%d"/>' % right
    return '<w:p><w:pPr><w:snapToGrid w:val="0"/>%s%s</w:pPr><w:r>%s<w:t>%s</w:t></w:r></w:p>' % (ind, RPR % (hp, hp), RPR % (hp, hp), text)
GAP = '<w:p><w:pPr><w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>'
TBLPR = re.search(r'<w:tblPr>.*?</w:tblPr>', doc[doc.rfind('<w:tbl>', 0, doc.find('以給予容積獎勵')):], flags=re.S).group(0)
def table(w, p):
    tp = re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="%d" w:type="dxa"/>' % w, TBLPR).replace('</w:tblPr>', '<w:tblLayout w:type="fixed"/></w:tblPr>')
    return '<w:tbl>%s<w:tblGrid><w:gridCol w:w="%d"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>%s' % (tp, w, w, p, GAP)
sect = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc, flags=re.S).group(0)
pg = re.search(r'<w:pgSz w:w="(\d+)"', sect).group(1); mar = re.search(r'<w:pgMar [^>]*/>', sect).group(0)
TEXT_W = int(pg) - int(re.search(r'w:left="(\d+)"', mar).group(1)) - int(re.search(r'w:right="(\d+)"', mar).group(1)) - int(re.search(r'w:gutter="(\d+)"', mar).group(1))
ROWS = {  # row: (half-points, text, BASE, STEP, body)
    'a': (24, TEXT, 4638, 7, False),
    'b': (20, TEXT, 3958, 6, False),
    'c': (28, TEXT, 5318, 8, False),
    'd': (32, TEXT, 5998, 9, False),
    'e': (24, TEXT, 4638, 7, True),
    'f': (24, TEXT.replace('、', '之', 1), 4638, 7, False),
}
body = ''
for k, (hp, text, base, step, inbody) in ROWS.items():
    for w in range(base, base + 16 * step, step):
        body += para(text, hp, right=TEXT_W - (w - 216)) + GAP if inbody else table(w, para(text, hp))
own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', sect)
out = re.sub(r'(<w:body>).*(</w:body>)', lambda m: m.group(1) + body + own, doc, count=1, flags=re.S)
with zipfile.ZipFile(os.path.join(outdir, 'gcap.docx'), 'w', zipfile.ZIP_DEFLATED) as zo:
    for n in z.namelist():
        zo.writestr(n, out.encode('utf-8') if n == 'word/document.xml' else z.read(n))
print('gcap', TEXT_W)
