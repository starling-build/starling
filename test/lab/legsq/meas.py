#!/usr/bin/env python3
"""meas.py PDF > LEGSQ-WORD.tsv: for every paragraph in order (a paragraph's first line starts with '对年销售收入'): index, variant (A-D, 31 each), indent_pt (0..60 step 2), first line text, x1 of its last char, number of lines of the paragraph."""
import sys, pymupdf
rows = []
for pn, p in enumerate(pymupdf.open(sys.argv[1]), 1):
    ls = []
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            cs = [c for s in l['spans'] for c in s['chars']]
            if cs: ls.append((l['bbox'][1], ''.join(c['c'] for c in cs), cs[-1]['bbox'][2], pn))
    rows += sorted(ls)
paras = []
for y, t, x1, pn in rows:
    if t.startswith('对年销售收入'): paras.append([t, x1, pn, 1])
    elif paras: paras[-1][3] += 1
print('# idx\tvariant\tindent_pt\tpage\tx1_first_line\tlines_in_para\tfirst_line_text')
for i, (t, x1, pn, n) in enumerate(paras):
    print('%d\t%s\t%d\t%d\t%.2f\t%d\t%s' % (i, 'ABCD'[i // 31], (i % 31) * 2, pn, x1, n, t))
print('# paragraphs found', len(paras), file=sys.stderr)
