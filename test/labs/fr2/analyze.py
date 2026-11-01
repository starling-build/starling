#!/usr/bin/env python3
"""analyze.py PDF [fr2-index.tsv] > table.  Each page: a 30-'a' word, Courier New 10pt (glyph 6.0pt), character spacing K twips (pitch p = 6 + K/20 pt),
set beside the frame.  Line 1 holds n characters: character i (0-based) ends at x0 + i*p + 6, and it fits iff that is <= the limit L, so
  x0 + (n-1)*p + 6 <= L < x0 + n*p + 6.
Per page that bracket; per variant the intersection over its pages (max of lows, min of highs) is Word's limit L in pt from the page's left edge."""
import sys, os
import pymupdf as fitz
pdf = sys.argv[1]; idx = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(pdf)), 'fr2-index.tsv')
rows = [l.rstrip('\n').split('\t') for l in open(idx)][1:]
d = fitz.open(pdf); br = {}
print('page\tvariant\tK_twips\tn_line1\tx0\tlow\thigh')
for i, p in enumerate(d):
    if i >= len(rows): break
    best = None
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            if l['bbox'][0] < 100 and t.startswith('aaaa') and (best is None or l['bbox'][1] < best[0]): best = (l['bbox'][1], l['bbox'][0], t)
    v, k = rows[i][1], int(rows[i][2])
    if not best: print('%d\t%s\t%d\t-\t-\t-\t-' % (i + 1, v, k)); continue
    n = len(best[2])
    if n >= 30: print('%d\t%s\t%d\tall\t-\t-\t-' % (i + 1, v, k)); continue
    pitch = 6 + k / 20; x0 = best[1]
    lo = x0 + (n - 1) * pitch + 6; hi = x0 + n * pitch + 6
    print('%d\t%s\t%d\t%d\t%.1f\t%.1f\t%.1f' % (i + 1, v, k, n, x0, lo, hi))
    a = br.setdefault(v, [0, 1e9]); a[0] = max(a[0], lo); a[1] = min(a[1], hi)
print('\nlimit L (pt from the page left) per variant: low <= L < high')
for v, (lo, hi) in br.items(): print('%s\t%.1f\t%.1f' % (v, lo, hi))
