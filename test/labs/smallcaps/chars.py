#!/usr/bin/env python3
"""chars.py PDF > SMALLCAPS-CHARS-WORD.tsv: per-glyph table for lines TNR 9, TNR 11, TNR 14, Arial 11 of smallcaps.docx: line, char, pdf font size, origin x, bbox x0, bbox x1, advance to the next glyph's origin (origin[i+1]-origin[i])."""
import sys, pymupdf
WANT = {0: 'TNR9', 2: 'TNR11', 5: 'TNR14', 8: 'Arial11'}
p = pymupdf.open(sys.argv[1])[0]
lines = []
for b in p.get_text('rawdict')['blocks']:
    for l in b.get('lines', []):
        cs = [(c, s) for s in l['spans'] for c in s['chars']]
        if cs: lines.append((l['bbox'][1], cs))
lines.sort(key=lambda t: t[0])
print('# line\tidx\tchar\tpdf_size\torigin_x\tbbox_x0\tbbox_x1\tadvance_to_next_origin')
for i, name in WANT.items():
    cs = lines[i][1]
    for k, (c, s) in enumerate(cs):
        adv = cs[k + 1][0]['origin'][0] - c['origin'][0] if k + 1 < len(cs) else float('nan')
        print('%s\t%d\t%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f' % (name, k, c['c'], s['size'], c['origin'][0], c['bbox'][0], c['bbox'][2], adv))
