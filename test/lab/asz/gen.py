#!/usr/bin/env python3
"""Lab asz (for amd-opus): how wide Word for Windows sets the automatic space beside digits when
the digits and the ideographs are not the same size — a quarter of the East Asian face's em, of
the Latin face's, or of the line's (paragraph mark's)? Lab asp's lines were all 12pt, so the
three could not be told apart. Same package as lab asp (zh-147bdae0: mode 15, doNotCompress,
標楷體, autoSpaceDN on through table style af0), each line left-aligned in a wide one-cell table
so nothing squeezes or stretches: the spaces stand at their natural width.
Text: "檢討，102年11月29日已頒訂" (five automatic spaces: 討|，no; ，|1 none after a mark?; 2|年,
年|1, 1|月, 月|2, 9|日 — read them off the x origins).
  a  all 12pt, digits Times New Roman (lab asp's row a)
  b  digits 9pt (w:sz 18), ideographs 12
  c  digits 16pt, ideographs 12
  d  ideographs 16pt, digits 12
  e  ideographs 9pt, digits 12
  f  all 12pt, the paragraph mark 16pt (w:pPr/w:rPr w:sz 32)
  g  all 12pt, digits in 標楷體 (w:ascii/w:hAnsi 標楷體)
  h  all 16pt
  i  as a, in the body (no table)
Read: for each row, line 1's per-character x origin and x1 (every character).
usage: gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, 'zh-147bdae0*.docx'))[0])
doc = z.read('word/document.xml').decode('utf-8')
TIMES = '<w:rFonts w:ascii="Times New Roman" w:eastAsia="標楷體" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'
KAI = '<w:rFonts w:ascii="標楷體" w:eastAsia="標楷體" w:hAnsi="標楷體" w:cs="Times New Roman"/>'
PPR = '<w:pPr><w:autoSpaceDN/><w:snapToGrid w:val="0"/><w:spacing w:line="400" w:lineRule="exact"/><w:jc w:val="left"/>%s</w:pPr>'
TEXT = '檢討，102年11月29日已頒訂'
def para(digits=None, ideos=None, fonts=TIMES, mark=None):
    runs = ''
    for piece in re.findall(r'[0-9]+|[^0-9]+', TEXT):
        dig = piece[0].isdigit()
        hint = '' if dig else ' w:hint="eastAsia"'
        size = digits if dig else ideos
        sz = '' if size is None else '<w:sz w:val="%d"/>' % size
        runs += '<w:r><w:rPr>%s%s<w:szCs w:val="24"/></w:rPr><w:t>%s</w:t></w:r>' % (fonts.replace('/>', hint + '/>'), sz, piece)
    mk = '' if mark is None else '<w:rPr><w:sz w:val="%d"/></w:rPr>' % mark
    return '<w:p>%s%s</w:p>' % (PPR % mk, runs)
GAP = '<w:p><w:pPr><w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>'
BORDERS = '<w:tblBorders>' + ''.join('<w:%s w:val="single" w:sz="4" w:space="0" w:color="auto"/>' % s for s in ('top', 'left', 'bottom', 'right')) + '</w:tblBorders>'
W = 7800
def table(p):
    return ('<w:tbl><w:tblPr><w:tblStyle w:val="af0"/><w:tblW w:w="%d" w:type="dxa"/>%s<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="%d"/></w:tblGrid>'
            '<w:tr><w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>%s') % (W, BORDERS, W, W, p, GAP)
rows = [
    ('a', table(para())),
    ('b', table(para(digits=18))),
    ('c', table(para(digits=32))),
    ('d', table(para(ideos=32))),
    ('e', table(para(ideos=18))),
    ('f', table(para(mark=32))),
    ('g', table(para(fonts=KAI))),
    ('h', table(para(digits=32, ideos=32))),
    ('i', para() + GAP),
]
own = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc, flags=re.S).group(0)
own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', own)
body = ''.join(x for _, x in rows)
out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + body + own, doc, count=1, flags=re.S)
with zipfile.ZipFile(os.path.join(outdir, 'asz.docx'), 'w', zipfile.ZIP_DEFLATED) as zo:
    for n in z.namelist():
        zo.writestr(n, out.encode('utf-8') if n == 'word/document.xml' else z.read(n))
print('asz', ' '.join(k for k, _ in rows))
