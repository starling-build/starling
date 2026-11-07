import sys, os, pymupdf
print('doc\tpage\tbaseline\tx0\tx1\ty0\ty1\tfont\tsize\ttext')
for f in sorted(x for x in os.listdir(sys.argv[1]) if x.endswith('-orig.pdf')):
    d = pymupdf.open(os.path.join(sys.argv[1], f))
    for pi, p in enumerate(d):
        L = []
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                txt = ''.join(c['c'] for s in l['spans'] for c in s['chars'])
                if not txt.strip(): continue
                fonts = list(dict.fromkeys(s['font'] for s in l['spans'])); sizes = list(dict.fromkeys('%g' % round(s['size'], 2) for s in l['spans']))
                x0, y0, x1, y1 = l['bbox']; L.append((l['spans'][0]['origin'][1], x0, x1, y0, y1, '+'.join(fonts), '+'.join(sizes), txt))
        for r in sorted(L, key=lambda r: (round(r[0], 1), r[1])):
            print('%s\t%d\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%s\t%s' % (f[:-9], pi + 1, *r))
