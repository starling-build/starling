#!/usr/bin/env python3
"""Lab bal3 part 2 (Windows 01QbbApP, for lenovo-5): a table cell holding a NumberedList1 list with AlertLabelinList1 'Note' + AlertTextinList1 paragraphs, split over pages; plus the same outside a table.
Uses the styles/numbering/media of lo-a197b7a87126ba68 verbatim (package copied, body replaced).
usage: build2.py a197.docx OUTDIR  -> t1,t2,t3 (in a 1-cell table, Notes after different items) and c1,c2,c3 (same body, no table)"""
import sys, os, re, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
f = {n: z.read(n) for n in z.namelist()}
d = f['word/document.xml'].decode('utf-8')
head = d[:d.index('<w:body>') + 8]
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', d, re.S)[-1]
# the original's label paragraph (picture + 'Note ')
lab = re.search(r'<w:p [^>]*><w:pPr><w:pStyle w:val="AlertLabelinList1"/>.*?</w:p>', d, re.S).group(0)
assert 'drawing' in lab
TXT = "Select the server in the console, review the settings on this page and then click Next to continue with the setup of the component that was chosen earlier"
def item(k, long):
    t = TXT if long else "Click Next"
    return ('<w:p><w:pPr><w:pStyle w:val="NumberedList1"/><w:spacing w:line="260" w:lineRule="exact"/></w:pPr>'
            f'<w:r><w:t xml:space="preserve">Item {k}: {t}.</w:t></w:r></w:p>')
def note(k):
    return lab + ('<w:p><w:pPr><w:pStyle w:val="AlertTextinList1"/></w:pPr><w:r><w:t xml:space="preserve">'
                  f'NOTE-TEXT {k}: Installation requires that the restrictions be enabled. To enable this, select the web server in the manager and then double-click the entry.</w:t></w:r></w:p>')
def body(notes_after, n=70, long_every=2):
    s = ''
    for k in range(1, n + 1):
        s += item(k, k % long_every == 0 or k % 5 == 0)
        if k in notes_after:
            s += note(k)
    return s
CASES = {1: [4, 14, 26, 36, 50, 60], 2: [7, 17, 29, 38, 53, 63], 3: [10, 21, 31, 43, 57, 67]}
def tbl(inner):
    return ('<w:tbl><w:tblPr><w:tblW w:w="8640" w:type="dxa"/><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="8640"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="8640" w:type="dxa"/></w:tcPr>' + inner + '</w:tc></w:tr></w:tbl><w:p/>')
for k, na in CASES.items():
    for pre, wrap in (('t', tbl), ('c', lambda x: x)):
        s = head + wrap(body(na)) + sect + '</w:body></w:document>'
        if pre == 't' and not s.count('<w:tc>'): raise SystemExit('bad')
        g = dict(f); g['word/document.xml'] = s.encode('utf-8')
        with zipfile.ZipFile(os.path.join(out, f'{pre}{k}.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
            for nme, v in g.items(): o.writestr(nme, v)
print('ok')
