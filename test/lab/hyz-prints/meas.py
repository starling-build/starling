import sys, pymupdf
d = sys.argv[1]
print('# doc\tright_ind_tw\tcol_width_pt\tnlines\tline3_tail\tline3_x1\tline2_tail\tline4_head\tall_line_ends')
for k in ('hyz0', 'hyz360', 'hyz720', 'hyzoff'):
    L = []
    for pg in pymupdf.open('%s/%s-orig.pdf' % (d, k)):
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars']]
                t = ''.join(c['c'] for c in ch).rstrip()
                if t: L.append((t, [c for c in ch if c['c'] != ' '][-1]['bbox'][2], [c for c in ch if c['c'] != ' '][0]['bbox'][0]))
    P = []
    for t, x1, x0 in L:
        if t.startswith('Everyone'): P.append([])
        P[-1].append((t, x1))
    for r, p in zip(range(-40, 42, 2), P):
        ln = [(i, t, x1) for i, (t, x1) in enumerate(p) if 'unemployment' in t or t.endswith('sickness,') or 'sickness' in t]
        i = ln[0][0] if ln else 0
        tail = lambda j: p[j][0][-22:] if 0 <= j < len(p) else ''
        print('%s\t%d\t%.2f\t%d\t%s\t%.2f\t%s\t%s\t%s' % (k, r, 481.9 - r / 20, len(p), tail(i), p[i][1], tail(i-1), p[i+1][0][:14] if i+1 < len(p) else '', ' | '.join(t.split(' ')[-1] for t, _ in p)))
