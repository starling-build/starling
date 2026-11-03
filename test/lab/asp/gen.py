#!/usr/bin/env python3
"""Lab asp (for amd-opus): how far Word for Windows squeezes the automatic spaces beside digits
to take a character. zh-147bdae0 (mode 15, doNotCompress, 標楷體 12, a cell) takes "保" onto
"地之檢討，102年11月29日已頒訂「都市計畫公共設施保" (p64), its five spaces set 1.8 .. 2.3 in Word's
print, the line about 3.7pt over; the same document's body line "…截至109年9月，政府資料開放平臺
累計開" (four spaces, digits in 標楷體 not Times) is refused 3.25 over. Ours caps the spaces'
give at a quarter em (3.0) and refuses both.
Each row: one paragraph (p64's properties and runs, no indent), in a one-cell fixed table, the
cell width stepped by 8 twips over 16 widths so the line runs past "保" by about 6 .. 0pt
(first widths: a, c, f 6236; b 6280; d 6544; e 6370).
  a  p64's text from "地之檢討" as is: digits in Times New Roman
  b  the digits in 標楷體 (w:ascii/w:hAnsi 標楷體), as the refused line has them
  c  "「" written "之" (no mark on the line before 保)
  d  "102年" written "一○二年": four automatic spaces, not five
  e  "102年11月29日" written "102年11月二十九日": three
  f  as a, in the body (no table), the right indent stepped instead
Read: for each row, line 1's last characters (does it end at "保"); and for the first width of
each row that ends at "保", line 1's per-character x origins.
usage: gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, 'zh-147bdae0*.docx'))[0])
doc = z.read('word/document.xml').decode('utf-8')
TIMES = '<w:rFonts w:ascii="Times New Roman" w:eastAsia="標楷體" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'
KAI = '<w:rFonts w:ascii="標楷體" w:eastAsia="標楷體" w:hAnsi="標楷體" w:cs="Times New Roman"/>'
PPR = '<w:pPr><w:autoSpaceDN/><w:snapToGrid w:val="0"/><w:spacing w:line="400" w:lineRule="exact"/><w:jc w:val="both"/></w:pPr>'
TAIL = '留地檢討變更作業原則」，其中配套措施明定，檢討不必要之公共設施用地變更為可建築土地。'
def para(text, fonts=TIMES, right=None):
    runs = ''
    for piece in re.findall(r'[0-9]+|[^0-9]+', text):
        hint = '' if piece[0].isdigit() else ' w:hint="eastAsia"'
        f = fonts.replace('/>', hint + '/>')
        runs += '<w:r><w:rPr>%s<w:szCs w:val="24"/></w:rPr><w:t>%s</w:t></w:r>' % (f, piece)
    ppr = PPR if right is None else PPR.replace('<w:jc', '<w:ind w:right="%d"/><w:jc' % right)
    return '<w:p>%s%s</w:p>' % (ppr, runs)
GAP = '<w:p><w:pPr><w:spacing w:after="0" w:line="120" w:lineRule="exact"/></w:pPr></w:p>'
BORDERS = '<w:tblBorders>' + ''.join('<w:%s w:val="single" w:sz="4" w:space="0" w:color="auto"/>' % s for s in ('top', 'left', 'bottom', 'right')) + '</w:tblBorders>'
def table(w, p):
    return ('<w:tbl><w:tblPr><w:tblStyle w:val="af0"/><w:tblW w:w="%d" w:type="dxa"/>%s<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="%d"/></w:tblGrid>'
            '<w:tr><w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>%s') % (w, BORDERS, w, w, p, GAP)
A = '地之檢討，102年11月29日已頒訂「都市計畫公共設施保' + TAIL
BASE = 6236  # first cell width (twips): the line about 6pt past "保"
def steps(extra): return range(BASE + extra, BASE + extra + 16 * 8, 8)
rows = {
    'a': lambda: ''.join(table(w, para(A)) for w in steps(0)),
    'b': lambda: ''.join(table(w, para(A, KAI)) for w in steps(44)),
    'c': lambda: ''.join(table(w, para(A.replace('「', '之', 1))) for w in steps(0)),
    'd': lambda: ''.join(table(w, para(A.replace('102年', '一○二年', 1))) for w in steps(308)),
    'e': lambda: ''.join(table(w, para(A.replace('29日', '二十九日', 1))) for w in steps(134)),
}
TEXT_W = 11906 - 1800 - 1800  # the document's last section: portrait A4
def body_rows():
    # The body line as wide as the cell's text: (w - 216) twips.
    return ''.join(para(A, right=TEXT_W - (w - 216)) + GAP for w in steps(0))
own = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc, flags=re.S).group(0)
own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', own)
body = ''.join(rows[k]() for k in 'abcde') + body_rows()
out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + body + own, doc, count=1, flags=re.S)
with zipfile.ZipFile(os.path.join(outdir, 'asp.docx'), 'w', zipfile.ZIP_DEFLATED) as zo:
    for n in z.namelist():
        zo.writestr(n, out.encode('utf-8') if n == 'word/document.xml' else z.read(n))
print('asp')
