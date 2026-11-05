import sys, pymupdf, collections
# meas.py DIR: per cell lines. Row bands from COM RowHeight after AutoFit (COLW-ROWH.tsv); band offset calibrated on row 1 (header line centre = band centre).
d = sys.argv[1]
H = collections.defaultdict(list)
for l in open(d + '/COLW-ROWH.tsv', encoding='utf8'):
    f = l.rstrip('\n').split('\t')
    if f[0].startswith('lab-') and f[1].isdigit(): H[f[0]].append(float(f[2]))
out = open(d + '/COLW-LINES.tsv', 'w', encoding='utf8'); out.write('# file\tcol\trow\tnlines\tlines (| separated)\n')
for n, hs in H.items():
    pdf = pymupdf.open('%s/%s-af.pdf' % (d, n))
    W = []
    for pg in pdf:   # columns of one page only; later pages carry further rows
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars']]
                if ch: W.append((pg.number, ''.join(c['c'] for c in ch), l['bbox'], ch[0]['origin'][0]))
    page0 = pdf[0]
    allp = []
    chars = []   # (y0, y1, x origin, char) one per glyph, whitespace kept for runs
    pagechars = []
    for pg in pdf:
        pc = []
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                for sp in l['spans']:
                    for c in sp['chars']: pc.append((l['bbox'][1], l['bbox'][3], c['origin'][0], c['c']))
        pagechars.append(pc)
    chars = pagechars[0]
    # header cells: the P= labels, one per column; their x origins start the columns
    hy = min(y for y, y1, x, c in chars if c == 'P')
    xs = sorted(x for y, y1, x, c in chars if c == 'P' and abs(y - hy) < 1)
    xs = xs
    c1 = [(y + y1) / 2 for y, y1, x, c in chars if c == 'P' and abs(y - hy) < 1][0]
    edges = [0]
    for h in hs: edges.append(edges[-1] + h)
    top = c1 - hs[0] / 2
    runs = collections.defaultdict(str)
    start = 0
    for pi, pc in enumerate(pagechars):
        mx = 0
        for y, y1, x, c in sorted(pc, key=lambda t: (round(t[0], 1), t[2])):
            col = max([i for i, xx in enumerate(xs) if x >= xx - 1.5] or [-1])
            cy = (y + y1) / 2 - top
            e = [ee - edges[start] for ee in edges]
            row = next((i + 1 for i in range(start, len(hs)) if e[i] <= cy < e[i + 1]), 0)
            if pi: row = 100 + pi   # later pages: rows not mapped, lines kept in order
            mx = max(mx, row if row < 100 else 0)
            runs[(col, row, round(y, 1) + 1000 * pi)] += c
        start = mx
    cells = collections.defaultdict(list)
    for (col, row, y), t in sorted(runs.items(), key=lambda k: (k[0][0], k[0][1], k[0][2])): cells[(row, col)].append(t.strip())
    for (row, col), ls in sorted(cells.items(), key=lambda k: (k[0][1], k[0][0])):
        out.write('%s\t%s\t%s\t%d\t%s\n' % (n, 'ABCDEF'[col] if col >= 0 else '?', row, len(ls), ' | '.join(ls)))
