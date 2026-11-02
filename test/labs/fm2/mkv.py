#!/usr/bin/env python3
"""Lab fm2 (Windows 01QbbApP, for amd-2): lo-20f5d558 floattable-multi-col.
usage: mkv.py ORIG.docx OUTDIR  -> writes fm-<variant>.docx
a: as is | b: cols num=1 | c: tblpY=1 | d: tblpXSpec removed (tblpX=0) | e12,e10,e8,e6: empties | f: row 3 as one paragraph"""
import sys, os, re, zipfile

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
parts = {n: z.read(n) for n in z.namelist()}
doc = parts['word/document.xml'].decode('utf8')
EMPTY = '<w:p w:rsidR="00C7581B" w:rsidRDefault="00C7581B"/>'
assert doc.count(EMPTY) == 14, doc.count(EMPTY)


def save(name, d):
    p = dict(parts)
    p['word/document.xml'] = d.encode('utf8')
    with zipfile.ZipFile(os.path.join(out, 'fm-%s.docx' % name), 'w', zipfile.ZIP_DEFLATED) as o:
        for n, v in p.items():
            o.write if False else o.writestr(n, v)
    print(name)


def nempty(d, n):
    first = d.find(EMPTY)
    return d.replace(EMPTY * 1, '', 14 - n) if False else re.sub('(' + re.escape(EMPTY) + r'\s*){%d}' % 14, lambda m: (EMPTY + '\n    ') * n, d, count=1)


save('a', doc)
save('b', doc.replace('<w:cols w:num="2" w:space="720"/>', '<w:cols w:num="1" w:space="720"/>'))
save('c', doc.replace('w:tblpY="472"', 'w:tblpY="1"'))
save('d', doc.replace(' w:tblpXSpec="right"', ' w:tblpX="0"'))
for n in (12, 10, 8, 6):
    save('e%d' % n, nempty(doc, n))
# f: row 3 first cell four paragraphs of "4" -> one paragraph
four = re.search(r'(<w:p [^>]*>\s*<w:r>\s*<w:t>4</w:t>\s*</w:r>\s*</w:p>\s*){4}', doc)
assert four
one = four.group(0).split('</w:p>')[0] + '</w:p>'
save('f', doc[:four.start()] + one + doc[four.end():])
# g: boundary — 12 empties (anchor top 139.5 in column 2), tblpY stepped
e12 = nempty(doc, 12)
for y in (600, 630, 650, 700):
    save('g%d' % y, e12.replace('w:tblpY="472"', 'w:tblpY="%d"' % y))
