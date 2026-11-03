#!/usr/bin/env python3
"""meas.py DIR OUT.tsv: for DIR/dbc-{a,b,c}.pdf, the first line of each table's paragraph in order:
doc, index (0,1 control; then p10 widths 3925..3985 by 4, p11 2783..2923 by 10), width, the line's last 4 chars,
its right end, its first char's x."""
import sys, collections, pymupdf as fitz
d, out = sys.argv[1], sys.argv[2]
rows = []
widths = [3965, 2903] + list(range(3925, 3986, 4)) + list(range(2783, 2924, 10))
for name in ('dbc-a', 'dbc-b', 'dbc-c'):
    lines = []
    for pi, p in enumerate(fitz.open('%s/%s.pdf' % (d, name))):
        L = collections.defaultdict(list)
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                for s in l['spans']:
                    for c in s['chars']:
                        if c['c'].strip(): L[round(c['origin'][1], 1)].append((c['origin'][0], c['c'], c['bbox'][2]))
        for y in sorted(L): lines.append(sorted(L[y]))
    firsts = [cs for cs in lines if ''.join(c for _, c, _ in cs).startswith(('(1)台', '(4)通', '台電公司', '通霄新'))]
    if len(firsts) != len(widths): print('WARNING %s: %d first lines for %d tables' % (name, len(firsts), len(widths)))
    for k, (w, cs) in enumerate(zip(widths, firsts)):
        t = ''.join(c for _, c, _ in cs)
        rows.append((name, k, w, t[-4:], round(cs[-1][2], 2), round(cs[0][0], 2)))
open(out, 'w').write('\n'.join('\t'.join(str(x) for x in r) for r in rows) + '\n')
print(len(rows), 'rows ->', out)
