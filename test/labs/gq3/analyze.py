#!/usr/bin/env python3
"""analyze.py PDF [INDEX.tsv] > gq3.tsv -- per variant the characters (blanks not counted) on line 1 at R = 0..8pt and the first line's text at R=0."""
import sys, os, fitz, collections
pdf = sys.argv[1]
idx = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gq3-index.tsv')
rows = [l.rstrip('\n').split('\t') for l in open(idx)][1:]
doc = fitz.open(pdf); res = collections.OrderedDict(); first = {}
for i, pg in enumerate(doc):
    if i >= len(rows): break
    lines = []
    for b in pg.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).replace(' ', '').replace('　', '')
            if t: lines.append((round(l['bbox'][1], 1), t))
    lines.sort(); t = lines[0][1] if lines else ''
    v, r = rows[i][1], int(rows[i][2]); res.setdefault(v, []).append(len(t))
    if r == 0: first[v] = t
print('# variant  chars on line 1 at R = 0..8pt   | line 1 at R=0')
for v, ns in res.items(): print('%s\t%s\t| %s' % (v, ' '.join(map(str, ns)), first.get(v, '')))
