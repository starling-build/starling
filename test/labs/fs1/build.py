#!/usr/bin/env python3
"""Lab fs1 (float stacking): builds docx variants from LibreOffice's floattable-tables-lost.docx
(the original: Table 1 floating, tblpY -67, trHeight 1830; Outer table 2 floating, tblpY -2, trHeight 2355,
holding an inner floating table tblpX 4306 tblpY -117 trHeight 946; page 15840x24480).
In Word's print Outer table 2 stands 115.3pt under Table 1's text (Table 1's row is 91.5pt: 23.8 more than
the row), ours 92.5.  Each variant changes one thing; measure the y of the texts "Table 1", "Outer table 2",
"Inner table 2" (PDF text tops).
usage: build.py SRC.docx OUTDIR"""
import re, sys, zipfile, os

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf8')
tbls = [m for m in re.finditer(r'<w:tbl>', doc)]

def parts(d):
    # table 1, table 2 (with the inner one), and the surrounding paragraphs
    t1 = d.index('<w:tbl>')
    t1e = d.index('</w:tbl>', t1) + len('</w:tbl>')
    t2 = t1e
    assert d[t2:].lstrip().startswith('<w:tbl>')
    t2 = d.index('<w:tbl>', t1e)
    depth = 0; i = t2
    for m in re.finditer(r'<w:tbl>|</w:tbl>', d[t2:]):
        depth += 1 if m.group(0) == '<w:tbl>' else -1
        if depth == 0:
            t2e = t2 + m.end(); break
    return d[:t1], d[t1:t1e], d[t1e:t2], d[t2:t2e], d[t2e:]

head, T1, mid, T2, tail = parts(doc)

def inner(t2):
    a = t2.index('<w:tbl>', 5)
    b = t2.index('</w:tbl>', a) + len('</w:tbl>')
    return a, b

variants = {}
variants['v0-original'] = head + T1 + mid + T2 + tail
a, b = inner(T2)
variants['v1-no-inner'] = head + T1 + mid + (T2[:a] + T2[b:]) + tail
variants['v2-inner-not-floating'] = head + T1 + mid + (T2[:a] + re.sub(r'<w:tblpPr[^>]*/>', '', T2[a:b]) + T2[b:]) + tail
variants['v3-no-table1'] = head + mid + T2 + tail
variants['v4-t2-lower'] = head + T1 + mid + T2.replace('w:tblpY="-2"', 'w:tblpY="500"', 1) + tail
variants['v5-t1-shorter'] = head + T1.replace('w:val="1830"', 'w:val="1000"', 1) + mid + T2 + tail
variants['v6-no-inner-t2-short'] = head + T1 + mid + (T2[:a] + T2[b:]).replace('w:val="2355"', 'w:val="600"', 1) + tail
variants['v7-t1-not-floating'] = head + re.sub(r'<w:tblpPr[^>]*/>', '', T1, count=1) + mid + T2 + tail

# second round (the first read-out: Outer table 2 stands at its own offset + Table 1's row + 20.58pt; ours +1.0)
variants['v8-t1-tblpY-0'] = head + T1.replace('w:tblpY="-67"', 'w:tblpY="0"', 1) + mid + T2 + tail
variants['v9-t1-tblpY--400'] = head + T1.replace('w:tblpY="-67"', 'w:tblpY="-400"', 1) + mid + T2 + tail
variants['v10-t1-tblpY-400'] = head + T1.replace('w:tblpY="-67"', 'w:tblpY="400"', 1) + mid + T2 + tail
variants['v11-last-para-big-font'] = head + T1 + mid + T2 + re.sub(r'<w:p\b[^>]*/>', '<w:p><w:r><w:rPr><w:sz w:val="48"/></w:rPr><w:t>Anchor</w:t></w:r></w:p>', tail, count=1)
variants['v12-t1-two-rows'] = head + re.sub(r'</w:tr>\s*</w:tbl>$', '</w:tr><w:tr><w:trPr><w:trHeight w:val="600"/></w:trPr><w:tc><w:tcPr><w:tcW w:w="13068" w:type="dxa"/></w:tcPr><w:p><w:r><w:t>Row two</w:t></w:r></w:p></w:tc></w:tr></w:tbl>', T1.rstrip(), count=1) + mid + T2 + tail
variants['v13-t2-tblOverlap-always'] = head + T1 + mid + T2.replace('<w:tblOverlap w:val="never"/>', '', 1) + tail
variants['v14-no-first-empty-para'] = (head.replace('<w:p w:rsidR="0072252C" w:rsidRDefault="0072252C" w:rsidP="008531A6"> <w:pPr> </w:pPr> </w:p>', '', 1) if False else head) + T1 + mid + T2 + tail

for name, d in variants.items():
    fn = os.path.join(out, 'fs1-%s.docx' % name)
    with zipfile.ZipFile(fn, 'w', zipfile.ZIP_DEFLATED) as o:
        for item in z.infolist():
            data = z.read(item.filename)
            if item.filename == 'word/document.xml':
                data = d.encode('utf8')
            o.writestr(item.filename, data)
    print(fn)
