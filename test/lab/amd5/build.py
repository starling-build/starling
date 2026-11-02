#!/usr/bin/env python3
"""Lab amd5 (Windows 01QbbApP, for amd-5): variants of two real corpus docs, made by string edits of word/document.xml (namespaces kept).
usage: build.py SRCDIR OUTDIR   SRCDIR holds lo-28f9b886.docx (lab A, from lo-28f9b88606c18b24) and lo-8ab44df5.docx (lab B, from lo-8ab44df57b3960fe).
Marker flavour 'm' puts the character M (same run props as the paragraph mark = none) in the paragraph whose y is wanted, so the PDF shows it.
 A: a1 real | a1m marker in the final empty paragraph | a2m final para sz2/spacing 0/line exact 20 + marker | a3 final paragraph removed | a4c/a4n sectPr type continuous/nextPage (a1m base)
    ar<k>m : last k rows of the table removed (a1m base)
 B: b1 real | b1m marker in the first paragraph after the table | b2m single non-merged cell (one row, auto height) | b2x same with trHeight exact 1020 |
    b3_<0|6|12|200>m: the merged cell's last (empty numbered) paragraph gets spacing after N | b4m paragraph after the table removed (marker goes on the first empty one)"""
import sys, os, re, zipfile
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
def load(n):
    z = zipfile.ZipFile(os.path.join(src, n)); return [(i.filename, z.read(i.filename)) for i in z.infolist() if not i.filename.endswith('/')]
def save(name, files, doc):
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        for fn, b in files: z.writestr(fn, doc.encode('utf8') if fn == 'word/document.xml' else b)
def get(files): return re.sub(r'>\s*[\r\n]\s*<', '><', dict(files)['word/document.xml'].decode('utf8'))
M = '<w:r><w:t>M</w:t></w:r>'
# ---------- lab A
FA = load('lo-28f9b886.docx'); A = get(FA)
LASTP = re.search(r'<w:p [^>]*><w:pPr><w:jc w:val="both"/></w:pPr></w:p>(?=<w:sectPr)', A).group(0)
assert A.count(LASTP) == 1, 'final paragraph not unique'
def mark(p, r=M): return p[:-len('</w:p>')] + r + '</w:p>'
a1m = A.replace(LASTP, mark(LASTP))
save('a1', FA, A); save('a1m', FA, a1m)
p2 = LASTP.replace('<w:pPr><w:jc w:val="both"/></w:pPr>', '<w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/><w:jc w:val="both"/><w:rPr><w:sz w:val="2"/><w:szCs w:val="2"/></w:rPr></w:pPr>')
save('a2m', FA, A.replace(LASTP, mark(p2, '<w:r><w:rPr><w:sz w:val="2"/><w:szCs w:val="2"/></w:rPr><w:t>M</w:t></w:r>')))
save('a3', FA, A.replace(LASTP, ''))
save('a4c', FA, a1m.replace('<w:sectPr w:rsidR="0043406E">', '<w:sectPr w:rsidR="0043406E"><w:type w:val="continuous"/>'))
save('a4n', FA, a1m.replace('<w:sectPr w:rsidR="0043406E">', '<w:sectPr w:rsidR="0043406E"><w:type w:val="nextPage"/>'))
rows = [m.span() for m in re.finditer(r'<w:tr[ >].*?</w:tr>', a1m, re.S)]
print('A rows', len(rows))
for k in (1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 35, 40, 45, 50):
    cut = a1m[:rows[-k][0]] + a1m[rows[-1][1]:]
    save('ar%dm' % k, FA, cut)
save('ahm', FA, a1m.replace('<w:tblHeader/>', ''))   # no repeated header rows
save('atm', FA, re.sub(r'<w:trHeight [^>]*/>', '', a1m))   # no tall rows
# ---------- lab B
FB = load('lo-8ab44df5.docx'); B = get(FB)
t0 = B.index('<w:tbl>'); t1 = B.index('</w:tbl>') + len('</w:tbl>')
tbl = B[t0:t1]; after = B[t1:]
first = re.match(r'<w:p [^>]*>.*?</w:p>|<w:p [^>]*/>', after, re.S).group(0)
CELL_LAST = re.search(r'<w:p [^>]*><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="4"/></w:numPr><w:jc w:val="both"/><w:rPr>.*?</w:rPr></w:pPr></w:p></w:tc>', tbl, re.S).group(0)
mfirst = first.replace('</w:pPr></w:p>', '</w:pPr>' + M + '</w:p>') if '</w:pPr></w:p>' in first else first
save('b1', FB, B); save('b1m', FB, B[:t1] + after.replace(first, mfirst, 1))
tc1 = re.search(r'<w:tc>.*?</w:tc>', tbl, re.S).group(0)
cell = re.sub(r'<w:tcW [^>]*/>', '<w:tcW w:w="9356" w:type="dxa"/>', tc1); cell = re.sub(r'<w:vMerge[^>]*/>', '', cell)
def single(trpr): return ('<w:tbl><w:tblPr><w:tblW w:w="9356" w:type="dxa"/><w:tblInd w:w="-459" w:type="dxa"/><w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="9356"/></w:tblGrid>'
                          f'<w:tr>{trpr}{cell}</w:tr></w:tbl>')
save('b2m', FB, B[:t0] + single('') + after.replace(first, mfirst, 1))
save('b2x', FB, B[:t0] + single('<w:trPr><w:trHeight w:hRule="exact" w:val="1020"/></w:trPr>') + after.replace(first, mfirst, 1))
for n in (0, 6, 12, 200):
    c2 = CELL_LAST.replace('</w:numPr><w:jc', f'</w:numPr><w:spacing w:after="{n}"/><w:jc', 1)
    t2 = tbl.replace(CELL_LAST, c2); assert t2 != tbl
    save(f'b3_{n}m', FB, B[:t0] + t2 + after.replace(first, mfirst, 1))
nxt = re.match(r'<w:p [^>]*/>', after[len(first):]).group(0)
save('b4m', FB, B[:t1] + after[len(first):].replace(nxt, nxt[:-2] + '>' + M + '</w:p>', 1) if False else B[:t1] + re.sub(r'<w:p ([^>]*)/>', lambda m: '<w:p %s>%s</w:p>' % (m.group(1), M), after[len(first):], 1))
print('done', sorted(os.listdir(out)))
