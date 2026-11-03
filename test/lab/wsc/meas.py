#!/usr/bin/env python3
"""meas.py DIR OUT.tsv: reads DIR/wsc-a.pdf and DIR/wsc-b.pdf (Word's or ours), writes one row per measurement.
  ctl   page-1 lines of the control cell (first and last character and right end of each line)
  a     font size w spacing pitch(pt, first to last of the 12 ideographs / 11) width-of-line
  b     cellwidth, last character of the cell's first line, its right end"""
import sys, collections, pymupdf as fitz
d, out = sys.argv[1], sys.argv[2]
def lines(path):
    res = []
    for pi, p in enumerate(fitz.open(path)):
        L = collections.defaultdict(list)
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                for s in l['spans']:
                    for c in s['chars']:
                        if c['c'].strip(): L[round(c['origin'][1], 1)].append((c['origin'][0], c['c'], c['bbox'][2]))
        merged = []
        for y in sorted(L):
            if merged and abs(y - merged[-1][0]) < 1.5: merged[-1][1].extend(L[y])
            else: merged.append((y, list(L[y])))
        for y, cs in merged: res.append((pi + 1, y, sorted(cs)))
    return res
rows = []
LINE = '行政处罚决定执行完毕执法'
A = lines(d + '/wsc-a.pdf')
ctl = [r for r in A if LINE not in ''.join(c for _, c, _ in r[2])]
for pg, y, cs in ctl[:12]:
    rows.append(('ctl', pg, round(y, 2), ''.join(c for _, c, _ in cs), round(cs[0][0], 2), round(cs[-1][2], 2)))
combos = [(f, sz, w, sp) for f in ('fangsong', 'simsun') for sz in (10.5, 12, 16) for w in (100, 99, 95, 90, 80, 150) for sp in (0, -7)]
ms = [r for r in A if ''.join(c for _, c, _ in r[2]) == LINE]
for k, (pg, y, cs) in zip(combos, ms):
    rows.append(('a',) + k + (round((cs[-1][0] - cs[0][0]) / (len(cs) - 1), 4), round(cs[-1][2] - cs[0][0], 3)))
if len(ms) != len(combos): print('WARNING: %d lines for %d combos' % (len(ms), len(combos)))
B = lines(d + '/wsc-b.pdf')
firsts = [r for r in B if ''.join(c for _, c, _ in r[2]).startswith('一般应有')]
for wd, (pg, y, cs) in zip(range(5870, 6071, 10), firsts[1:]):
    rows.append(('b', wd, ''.join(c for _, c, _ in cs)[-4:], round(cs[-1][2], 2)))
import os
if os.path.exists(d + '/wsc-c.pdf'):
    C = [r for r in lines(d + '/wsc-c.pdf') if ''.join(c for _, c, _ in r[2]) == LINE[:8]]
    cc = [(sz / 2, w) for sz in (18, 20, 21, 28, 36, 44, 56) for w in (99, 95, 90, 80)]
    if len(C) != len(cc): print('WARNING: wsc-c %d lines for %d' % (len(C), len(cc)))
    for k, (pg, y, cs) in zip(cc, C):
        rows.append(('c',) + k + (round((cs[-1][0] - cs[0][0]) / (len(cs) - 1), 4),))
open(out, 'w').write('\n'.join('\t'.join(str(x) for x in r) for r in rows) + '\n')
print(len(rows), 'rows ->', out)
