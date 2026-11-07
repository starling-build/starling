import sys, pymupdf
print('doc\tcopy\tright_indent_pt\tline\tpage\tbaseline\tx0\tx1\tline1_takes_yue\ttext')
for name in ('q0-orig', 'q1-comma-for-paren', 'q2-no-paren'):
    d = pymupdf.open(name + '-orig.pdf'); L = []
    for pi, p in enumerate(d):
        rows = []
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(c['c'] for s in l['spans'] for c in s['chars'])
                if t.strip(): rows.append((l['spans'][0]['origin'][1], l['bbox'][0], l['bbox'][2], t))
        for r in sorted(rows, key=lambda r: round(r[0], 1)): L.append((pi + 1,) + r)
    copies = []
    for r in L:
        if r[4].startswith('藉由'): copies.append([])
        if copies: copies[-1].append(r)
    for ci, c in enumerate(copies):
        ind = -2 + 0.5 * ci; yue = 'yes' if c[0][4].rstrip().endswith('約') else 'no'
        for li, r in enumerate(c): print('%s\t%d\t%.1f\t%d\t%d\t%.2f\t%.2f\t%.2f\t%s\t%s' % (name, ci + 1, ind, li + 1, r[0], r[1], r[2], r[3], yue if li == 0 else '', r[4].rstrip()))
