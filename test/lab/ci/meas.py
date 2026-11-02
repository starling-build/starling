#!/usr/bin/env python3
"""meas.py ci-orig.pdf > CI-WORD.tsv: per table (label 'T:key' then the cell's lines in y order): key, line no, x of the first glyph, x1, baseline y, text.
Cell content = lines between this label and the next whose x lies inside the table's border box (vertical rules)."""
import sys, pymupdf
import itertools
labs = []; lines = []
for pg in pymupdf.open(sys.argv[1]):
  for b in pg.get_text('rawdict')['blocks']:
    for l in b.get('lines', []):
        ch = [c for s in l['spans'] for c in s['chars']]
        t = ''.join(c['c'] for c in ch)
        if t.startswith('T:'): labs.append((l['bbox'][1] + 1000 * pg.number, t[2:].strip()))
        elif t.strip(): lines.append((l['spans'][0]['origin'][1] + 1000 * pg.number, ch[0]['origin'][0], ch[-1]['bbox'][2], t.strip()))
labs.sort()
print('# key\tline\tx0\tx1\tbaseline\ttext')
for i, (y, k) in enumerate(labs):
    hi = labs[i + 1][0] if i + 1 < len(labs) else 1e9
    n = 0
    for base, x0, x1, t in sorted(lines):
        if y < base < hi:
            n += 1; print('%s\t%d\t%.2f\t%.2f\t%.2f\t%s' % (k, n, x0, x1, base, t))
