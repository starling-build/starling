#!/usr/bin/env python3
"""analyze.py PDF-or-DIR: per test paragraph of a cq1 print, one TSV row:
doc, n (paragraph 1..20), K, R_twips, tail, line1_end (last 3 chars), line1_right_edge_minus_column_right_pt (>0 = past the margin),
line1_len, line2_first (first 3 chars), quote_width_pt (right-left of the first U+201D on line 1 or 2), lines (count in the paragraph).
Column right edge is 2753 twips in from the right of an 11906-twip page: 595.3 - 137.65 = 457.65pt."""
import sys, os, glob, unicodedata
import fitz
KS = (19, 20); RS = (0, -40, -100, -160, -240); TAILS = ('A', 'B')
ORDER = [(k, r, t) for k in KS for r in RS for t in TAILS]
RIGHT = 595.3 - 2753 / 20
def one(path):
    d = fitz.open(path); lines = []
    for pg in d:
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars'] if not c['c'].isspace()]
                if ch: lines.append((pg.number, round(l['bbox'][1], 1), ch))
    lines.sort(key=lambda x: (x[0], x[1])); paras = []; cur = []
    for pn, y, ch in lines:
        t = ''.join(c['c'] for c in ch)
        if t.startswith('==') and t.endswith('=='):
            paras.append(cur); cur = []
        else: cur.append(ch)
    for n, ls in enumerate(paras, 1):
        if not ls: continue
        k, r, t = ORDER[n - 1]; l1 = ls[0]; txt = ''.join(c['c'] for c in l1)
        edge = max(c['bbox'][2] for c in l1) - RIGHT
        l2 = ''.join(c['c'] for c in ls[1])[:3] if len(ls) > 1 else ''
        q = [c for line in ls[:2] for c in line if c['c'] == '”']
        qw = round(q[0]['bbox'][2] - q[0]['bbox'][0], 2) if q else ''
        print('\t'.join(str(x) for x in (os.path.basename(path), n, k, r, t, txt[-3:], round(edge, 2), len(txt), l2, qw, len(ls))))
for a in sys.argv[1:]:
    for p in (sorted(glob.glob(os.path.join(a, '*.pdf'))) if os.path.isdir(a) else [a]): one(p)
