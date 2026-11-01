#!/usr/bin/env python3
"""analyze.py PDF [fr2-index.tsv] > table: per page: variant, R twips, the test paragraph's lines (1 = 'b' on the first line, 2 = wrapped),
the first line's right edge in pt.  Then the flip per variant: first R at which 'b' wraps; wrap limit = 90.0 + R_flip (pt from the text's left)."""
import sys, os
import pymupdf as fitz
pdf = sys.argv[1]; idx = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(pdf)), 'fr2-index.tsv')
rows = [l.rstrip('\n').split('\t') for l in open(idx)][1:]
d = fitz.open(pdf); flips = {}
print('page\tvariant\tR_twips\tlines\tline1_right_pt\tline1_text')
for i, p in enumerate(d):
    if i >= len(rows): break
    lines = []
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans'])
            if l['bbox'][0] < 100 and (t.strip().startswith('aaaa') or t.strip() == 'b'): lines.append((l['bbox'][1], l['bbox'][2], t.strip()))
    lines.sort()
    n = len(lines); v, r = rows[i][1], int(rows[i][2])
    print('%s\t%s\t%d\t%d\t%.1f\t%s' % (rows[i][0], v, r, n, lines[0][1] if lines else -1, lines[0][2] if lines else ''))
    if n >= 2 and v not in flips: flips[v] = r
print('\nflip (first R, twips, at which b wraps) per variant; wrap limit pt from text left = 90.0 + R/20:')
for v, r in flips.items(): print('%s\t%d\t%.2f' % (v, r, 90.0 + r / 20))
