#!/usr/bin/env python3
"""meas.py DIR > DIG-WORD.tsv: per variant (dig-A/B/C-orig.pdf in DIR) and copied paragraph, in order, the FIRST line's
text, its last char, and whether it ends with 应.  Paragraph start = "4、装饰".  Right indent = start + 2*idx twips
(A, C: -18; B: -64)."""
import sys, os, pymupdf
START = {'A': -18, 'B': -64, 'C': -18}
print('# var\tidx\tright_indent_tw\tpage\tlast_char\ttakes_ying\tx1_last_char\tlines_in_para\tfirst_line_text')
for v, st in START.items():
    d = pymupdf.open(os.path.join(sys.argv[1], 'dig-%s-orig.pdf' % v))
    rows = []
    for pn, p in enumerate(d, 1):
        ls = []
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars']]
                if cs: ls.append((l['bbox'][1], l['bbox'][0], ''.join(c['c'] for c in cs), cs[-1]['bbox'][2], pn))
        rows += sorted(ls)
    paras = []
    for y, x0, t, x1, pn in rows:
        if t.startswith('4、装饰'): paras.append([t, x1, pn, 1])
        elif paras and not t.strip().startswith('—'): paras[-1][3] += 1
    if len(paras) != 14: print('# WARNING', v, 'found', len(paras), 'expected 14', file=sys.stderr)
    for i, (t, x1, pn, c) in enumerate(paras):
        t = t.rstrip()
        print('%s\t%d\t%d\t%d\t%s\t%d\t%.2f\t%d\t%s' % (v, i, st + 2 * i, pn, t[-1], int(t.endswith('应')), x1, c, t))
