import sys, glob, os, re, pymupdf
rows = []
for f in sorted(glob.glob(sys.argv[1] + '/*-orig.pdf')):
    nm = os.path.basename(f)[:-9]; m = re.match(r'pb-([PC])([a-g])-m(\d+)', nm)
    kind = m.group(1); d = pymupdf.open(f)
    pg = d[1] if kind == 'P' else d[0]
    if kind == 'P' and len(d) < 2:
        rows.append((m.group(2), kind, m.group(3), 'pages=%d' % len(d))); continue
    mid = pg.rect.width / 2
    lines = []
    for b in pg.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            if t.startswith('How') and (kind == 'P' or l['bbox'][0] > mid - 5):
                lines.append((l['bbox'][1], l['spans'][0]['origin'][1], l['bbox'][0], t[:14]))
    lines.sort()
    fill = [dr['rect'] for dr in pg.get_drawings() if dr.get('fill') and (kind == 'P' or dr['rect'].x0 > mid - 5) and dr['rect'].width > 20]
    fl = min([r.y0 for r in fill], default=None)
    allr = [dr['rect'] for dr in pg.get_drawings() if (kind == 'P' or dr['rect'].x0 > mid - 5) and dr['rect'].width > 20]
    top = min([r.y0 for r in allr], default=None)
    ln = lines[0] if lines else (None,) * 4
    rows.append((m.group(2), kind, m.group(3), 'pages=%d' % len(d), 'text_top=%s' % (round(ln[0], 2) if ln[0] is not None else None), 'baseline=%s' % (round(ln[1], 2) if ln[1] else None), 'x0=%s' % (round(ln[2], 2) if ln[2] else None),
                 'box_top=%s' % (round(top, 2) if top is not None else None), 'fill_top=%s' % (round(fl, 2) if fl is not None else None), 'nlines=%d' % len(lines)))
for r in sorted(rows, key=lambda r: (r[1], r[0], r[2])): print('\t'.join(map(str, r)))
