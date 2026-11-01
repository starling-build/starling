#!/usr/bin/env python3
"""Lab fr2: where Word ends the lines beside a bordered frame (tdf154703).  usage: build.py OUTDIR [TEMPLATE.docx]
One document, one page per test.  Every page is the tdf154703 page (8392 x 5954 twips landscape, margins 1440 / 1797) with the
frame of that file -- w=1134 h=2268 exact, hAnchor margin xAlign right, vAnchor text y=1, wrap around -- followed by ONE test paragraph:
Courier New 10pt (every character 6.0pt), text  'a' x13 + ' ' + 'b'  (15 chars = 90.0pt), right indent R.  Word puts 'b' on the first
line when the room beside the frame, less R, is >= 90.0pt, and on a second line when it is not: the R at which that flips is
(room - 90.0), i.e. Word's wrap limit as a number.  R runs 0..14pt in 0.5pt steps (0..280 twips by 10), 29 pages a variant.
Variants (frame border sz in 1/8pt, border space pt, hSpace twips):  v0 no border, hSpace 2552 | v1 sz6 sp7 | v2 sz12 sp7 | v3 sz6 sp14 |
v4 sz6 sp7 hSpace 0 | v5 sz6 sp7 hSpace 1000.  tdf154703 itself is v1."""
import sys, os, re, zipfile, shutil
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
tpl = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../corpus/docx/lo/docs/lo-60fd93680f179e1e.docx')
VARIANTS = [('v0', 0, 0, 2552), ('v1', 6, 7, 2552), ('v2', 12, 7, 2552), ('v3', 6, 14, 2552), ('v4', 6, 7, 0), ('v5', 6, 7, 1000)]
def frame(sz, sp, hs):
    b = '' if not sz else ''.join('<w:%s w:val="single" w:sz="%d" w:space="%d" w:color="000000"/>' % (e, sz, sp) for e in ('top', 'left', 'bottom', 'right'))
    return ('<w:p><w:pPr><w:framePr w:w="1134" w:h="2268" w:hRule="exact" w:hSpace="%d" w:wrap="around" w:vAnchor="text" w:hAnchor="margin" w:xAlign="right" w:y="1"/>%s</w:pPr>'
            '<w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="20"/></w:rPr><w:t>A right aligned frame</w:t></w:r></w:p>') % (hs, '<w:pBdr>%s</w:pBdr>' % b if b else '')
def para(r_tw, first):
    br = '' if first else '<w:pageBreakBefore/>'
    return ('<w:p><w:pPr>%s<w:ind w:right="%d"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="20"/></w:rPr>'
            '<w:t xml:space="preserve">aaaaaaaaaaaaa b</w:t></w:r></w:p>') % (br, r_tw)
src = zipfile.ZipFile(tpl); doc = src.read('word/document.xml').decode('utf8')
head = doc[:doc.index('<w:body>') + 8]; sect = doc[doc.rindex('<w:sectPr'):]
sect = sect.replace('<w:vAlign w:val="center"/>', '')
body = ''; first = True; index = []
for name, sz, sp, hs in VARIANTS:
    for k in range(29):
        r = k * 10
        # the frame paragraph carries the page break (it is the first of the page)
        f = frame(sz, sp, hs)
        if not first: f = f.replace('<w:pPr>', '<w:pPr><w:pageBreakBefore/>', 1)
        body += f + para(r, True); index.append((name, r)); first = False
d = os.path.join(out, 'fr2.docx')
with zipfile.ZipFile(d, 'w', zipfile.ZIP_DEFLATED) as z:
    for item in src.infolist():
        data = src.read(item.filename)
        if item.filename == 'word/document.xml': data = (head + body + sect).encode('utf8')
        z.writestr(item, data)
open(os.path.join(out, 'fr2-index.tsv'), 'w').write('page\tvariant\tR_twips\n' + ''.join('%d\t%s\t%d\n' % (i + 1, n, r) for i, (n, r) in enumerate(index)))
print(d, len(index), 'pages')
