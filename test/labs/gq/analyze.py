#!/usr/bin/env python3
"""analyze.py PDF [INDEX.tsv] > gq.tsv -- per page, how many characters line 1 holds; per (family, variant) the chars of line 1 for R = 0..20pt and the R (pt) at which it first drops.  PyMuPDF.  For the table family the page's first text line is the cell's."""
import sys, os, fitz, collections
pdf = sys.argv[1]
idx = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "gq-index.tsv")
rows = [l.rstrip('\n').split('\t') for l in open(idx)][1:]
doc = fitz.open(pdf)
res = collections.OrderedDict()
print('page\tfamily\tvariant\tR_twips\tchars_line1')
for i, pg in enumerate(doc):
    if i >= len(rows): break
    lines = []
    for b in pg.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).replace(' ', '').replace('　', '')
            if t: lines.append((round(l['bbox'][1], 1), t))
    lines.sort()
    n = len(lines[0][1]) if lines else -1
    fam, var, r = rows[i][1], rows[i][2], int(rows[i][3])
    print('%d\t%s\t%s\t%d\t%d' % (i + 1, fam, var, r, n))
    res.setdefault((fam, var), []).append((r, n))
print('\n# family variant  chars on line 1 at R = 0,1,2..20 pt   |  R (pt) at which the count first drops')
for (fam, var), v in res.items():
    v.sort(); ns = [n for r, n in v]
    drops = [v[i][0] // 20 for i in range(1, len(v)) if ns[i] < ns[i - 1]]
    print('%s\t%s\t%s\t| drops at %s' % (fam, var, ' '.join(map(str, ns)), drops))
