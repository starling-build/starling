#!/usr/bin/env python3
"""meas.py DIR > LEF-WORD.tsv: per case and copied paragraph (in order) the FIRST line's text, its last 4 chars, x1 of its last char, line count of the paragraph. Paragraph start = the case's START string."""
import sys, os, pymupdf
CASES = {'e68': ('（一）住宅', 21, -200, 20), 'x621': ('您好', 21, -200, 20), 'cf8': ('指標1', 31, -60, 4)}
print('# case\tidx\tright_indent_tw\tpage\tfirst_line_last4\tx1_last_char\tlines_in_para\tfirst_line_text')
for k, (start, n, lo, st) in CASES.items():
    d = pymupdf.open(os.path.join(sys.argv[1], 'lef-%s-orig.pdf' % k))
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
        if t.startswith(start): paras.append([t, x1, pn, 1])
        elif paras: paras[-1][3] += 1
    if len(paras) != n: print('# WARNING', k, 'found', len(paras), 'expected', n, file=sys.stderr)
    for i, (t, x1, pn, c) in enumerate(paras):
        print('%s\t%d\t%d\t%d\t%s\t%.2f\t%d\t%s' % (k, i, lo + i * st, pn, t.rstrip()[-4:], x1, c, t))
