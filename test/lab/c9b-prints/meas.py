import sys, re, pymupdf
d = sys.argv[1]
VAR = {'c9H': [('page_h', h) for h in range(580, 644, 4)], 'c9Y': [('dy_pt', dy) for dy in range(-8, 8)], 'c9B': [('bottom_pt', (720 + 140 * k) / 20) for k in range(12)],
       'c9F': [('footer_pt', f) for f in (0, 10, 20, 30, 35.4, 40, 50, 60, 72, 90)]}
print('# doc\tsec\tvar\tvalue\tA4_last_bottom\tA5_lines_on_page1\tA5_last_line_bottom\tpage1_last_bottom\tcont_lines_on_page2\tpages')
for k, vs in VAR.items():
    pages = []
    for pg in pymupdf.open('%s/%s-orig.pdf' % (d, k)):
        L = []
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).strip()
                if t: L.append((l['bbox'][1], l['bbox'][3], t))
        pages.append(sorted(L))
    # section starts: page with "A1 Snn"
    start = {}
    for i, L in enumerate(pages):
        for y0, y1, t in L:
            m = re.match(r'A1 S(\d\d)', t)
            if m: start[int(m.group(1))] = i
    for n, (name, v) in enumerate(vs, 1):
        i = start[n]; nxt = start.get(n + 1, len(pages)); L = pages[i]
        a4 = [x for x in L if x[2].startswith('A4 ')]; a5 = [x for x in L if x[2].startswith('A5 ')]
        a4b = a4[0][1] + 7 * 13.45 if a4 else float('nan')
        if a5:
            ys = [x for x in L if x[0] >= a5[0][0]]; n5 = len(ys); b5 = ys[-1][1]
        else: n5 = 0; b5 = float('nan')
        cont = len(pages[i + 1]) if nxt > i + 1 else 0
        print('%s\t%d\t%s\t%s\t%.1f\t%d\t%.1f\t%.1f\t%d\t%d' % (k, n, name, v, a4b, n5, b5, L[-1][1], cont, nxt - i))
