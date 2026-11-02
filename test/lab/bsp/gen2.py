#!/usr/bin/env python3
"""Lab bsp2 (for amd-opus), after bsp: in bsp every copy of zh-6c447317's "第三十八条 …" took its line's last character
about 1.3pt (bold space) to 1.5pt (regular space) further than ours, but the document's own "第四条 就业补助资金…"
(regular space, the same paragraph properties and runs) is refused 9.04pt over with one "、" in Word's print, where
bsp's g took to 9.4. The bsp copies all carry a right indent (the paragraphs say w:adjustRightInd). Here:
  h  "第四条 …" as it is, the right indent stepped (as bsp)
  i  "第四条 …" as it is, no right indent: the PAGE's right margin stepped instead, one continuous section per paragraph
  j  "第三十八条 …" as it is (bsp's f), the page's right margin stepped
T = 7.0 .. 11.0 by 0.2 (21 paragraphs each), T from ours at right 0 (over0.tsv: h, i, j).
Read: as bsp, the last characters of each paragraph's first line (meas2.py).
gen2.py SRC.docx OUTDIR OVER.tsv"""
import sys, re, zipfile, os
src, outdir, overf = sys.argv[1], sys.argv[2], sys.argv[3]
over0 = {l.split('\t')[0]: float(l.split('\t')[1]) for l in open(overf) if '\t' in l}
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
paras = [m.group(0) for m in re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S)]
def find(start):
    p = [p for p in paras if text(p).startswith(start)][0]
    m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)(.*)</w:p>$', p, flags=re.S)
    return m.group(2), m.group(3)
own = re.search(r'<w:sectPr[ >].*?</w:sectPr>', doc, flags=re.S).group(0)
right0 = int(re.search(r'<w:pgMar [^>]*w:right="(\d+)"', own).group(1))
steps = [round(7.0 + 0.2 * i, 2) for i in range(21)]
for name, start, how in (('h', '第四条', 'indent'), ('i', '第四条', 'margin'), ('j', '第三十八条', 'margin')):
    ppr, body = find(start)
    ps = []
    for T in steps:
        d = round((T - over0.get(name, 0.0)) * 20)
        if how == 'indent':
            p = re.sub(r'<w:ind ([^>]*?)/>', lambda k: '<w:ind w:right="%d" ' % d + k.group(1) + '/>', ppr, count=1)
            ps.append('<w:p>%s%s</w:p>' % (p, body))
        else:
            # (This paragraph ends a continuous section whose right margin is the page's plus d.)
            s = re.sub(r'(<w:pgMar [^>]*w:right=")\d+(")', lambda k: k.group(1) + str(right0 + d) + k.group(2), own, count=1)
            s = re.sub(r'<w:type [^>]*/>', '', s)
            s = re.sub(r'(<w:sectPr[^>]*>)', r'\1<w:type w:val="continuous"/>', s, count=1)
            s = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', s)
            p = ppr.replace('</w:pPr>', s + '</w:pPr>', 1)
            ps.append('<w:p>%s%s</w:p>' % (p, body))
    out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + ''.join(ps) + own + k.group(2), doc, count=1, flags=re.S)
    path = os.path.join(outdir, 'bsp-%s.docx' % name)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            zo.writestr(n, out.encode('utf-8') if n == 'word/document.xml' else z.read(n))
    print(name, len(ps), 'paragraphs ->', path)
