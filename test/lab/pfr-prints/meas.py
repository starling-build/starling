import sys, re, pymupdf
d = sys.argv[1]
print('# doc\tsection\tpage\tpage_h_pt\ttblpY_pt\tbottom_margin_pt\tlines_kept\tlast_kept\tfirst_line_top\tlast_line_bottom\tpages_with_this_section')
H = list(range(600, 632, 2)); Y = list(range(500, 564, 4)); B = [720 + 130 * k for k in range(12)]
for k in ('pfH', 'pfY', 'pfB'):
    docp = pymupdf.open('%s/%s-orig.pdf' % (d, k)); sec = {}
    for pg in docp:
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(c['c'] for s in l['spans'] for c in s['chars']); m = re.match(r'S(\d\d) L(\d)', t)
                if m: sec.setdefault(int(m.group(1)), []).append((int(m.group(2)), pg.number + 1, l['bbox'][1], l['bbox'][3], pg.rect.height))
    for s in sorted(sec):
        v = sorted(sec[s]); n = len(v)
        h = H[s-1] if k == 'pfH' else 612; y = Y[s-1] if k == 'pfY' else 540.7; bm = B[s-1] / 20 if k == 'pfB' else 72
        pgs = sorted(set(x[1] for x in v))
        p1 = [x for x in v if x[1] == pgs[0]]
        print('%s\t%d\t%d\t%.1f\t%.1f\t%.1f\t%d\tL%d\t%.2f\t%.2f\t%s' % (k, s, pgs[0], h, y, bm, len(p1), p1[-1][0], p1[0][2], p1[-1][3], ','.join(map(str, pgs))))
