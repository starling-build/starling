import sys, pymupdf
d = pymupdf.open(sys.argv[1])
print('slide\tbaseline\tx0\ty0\tx1\ty1\tfont\tsize\ttext')
for pi, p in enumerate(d):
    L = []
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            sp = [s for s in l['spans'] if ''.join(c['c'] for c in s['chars']).strip() or True]
            txt = ''.join(''.join(c['c'] for c in s['chars']) for s in sp)
            if not txt.strip(): continue
            fonts = []; sizes = []
            for s in sp:
                if s['font'] not in fonts: fonts.append(s['font'])
                z = '%g' % round(s['size'], 2)
                if z not in sizes: sizes.append(z)
            x0, y0, x1, y1 = l['bbox']
            L.append((sp[0]['origin'][1], x0, y0, x1, y1, '+'.join(fonts), '+'.join(sizes), txt))
    for r in sorted(L, key=lambda r: (round(r[0], 1), r[1])):
        print('%d\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%s\t%s' % (pi + 1, r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]))
