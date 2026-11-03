#!/usr/bin/env python3
"""Lab prt: a closing mark the line parts from the opening one after it, where
marks are compressed (zh-7a16a243's package: mode 15, compressPunctuation,
標楷體 16pt, docGrid charSpace 4127 = 17.0076pt cells). Word for Windows sends
zh-7a16a243 p26's "積」" (before "（") down 0.52pt over with "」" at half and a
"「" to give 8.5; zh-6d1afa56's cell keeps "、" before "《" at a line's end.
Each paragraph: "「" + 20 ideographs + "積" + X + F + more text, body, left
indent 1361 twips, no first-line indent. The room is set so the line before
"積X" is 21 cells and "積X" is 4pt over with X at half an em; row k widens the
line k points more (k = 0..14).
  X in 」 ） 〉 、 ，      F = "（" (pair) or "如" (control, nothing to close up with)
Readings, first line's last characters per row:
  takes "積X" from k=0     X counts half (or whole, and gives its half too)
  from k=4                 X counts whole and gives nothing; "「" gives 8.5
  from k=13                nothing gives
  prt-grid.docx   on the document's grid;  prt-nogrid.docx  docGrid removed (16pt cells)
usage: gen.py zh-7a16a243.docx OUTDIR"""
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
HAN = '公民社會團體私部門工作國家發展委員區域離島處長代理'
FILL = '如加計免計容積部分之樓地板面積經推估恐達三萬三千九百三十六平方公尺二者之間已然處於失衡狀態'
BASE_WIDTH = 374.15          # the line at right indent 0 (left 1361 twips)
def paras(cell):
    over0 = 4.0
    width0 = 21 * cell + cell + cell / 2 - over0
    out = []
    for x in '」）〉、，':
        for f in '（如':
            for k in range(15):
                right = round((BASE_WIDTH - width0 - k) * 20)
                text = '「' + HAN[:20] + '積' + x + f + FILL
                out.append('<w:p><w:pPr><w:pStyle w:val="2"/><w:numPr><w:ilvl w:val="1"/><w:numId w:val="0"/></w:numPr>'
                           f'<w:ind w:left="1361" w:right="{right}" w:firstLine="0"/><w:rPr><w:b w:val="0"/></w:rPr></w:pPr>'
                           f'<w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t>{text}</w:t></w:r></w:p>')
    return ''.join(out)
body_s = doc.index('<w:body>') + len('<w:body>')
sect = doc[doc.rindex('<w:sectPr'):doc.rindex('</w:body>')]
tail = doc[doc.rindex('</w:body>'):]
os.makedirs(out, exist_ok=True)
for name, cell, strip in [('grid', 17.0076, False), ('nogrid', 16.0, True)]:
    s = sect if not strip else re.sub(r'<w:docGrid [^>]*/>', '', sect)
    d = doc[:body_s] + paras(cell) + s + tail
    with zipfile.ZipFile(os.path.join(out, f'prt-{name}.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for n in z.namelist():
            o.writestr(n, d if n == 'word/document.xml' else z.read(n))
