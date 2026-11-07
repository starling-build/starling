import sys, pymupdf
d = pymupdf.open(sys.argv[1]); spans = len(sys.argv) > 2
print('page\tbaseline\tx0\tx1\ty0\ty1\t' + ('font\tsize\ttext' if spans else 'fonts\tsizes\ttext'))
for pi, p in enumerate(d):
    L = []
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            if spans:
                for s in l['spans']:
                    t = ''.join(c['c'] for c in s['chars'])
                    if t.strip(): L.append((s['origin'][1], s['bbox'][0], s['bbox'][2], s['bbox'][1], s['bbox'][3], s['font'], '%g' % round(s['size'], 2), t))
            else:
                t = ''.join(c['c'] for s in l['spans'] for c in s['chars'])
                if not t.strip(): continue
                L.append((l['spans'][0]['origin'][1], l['bbox'][0], l['bbox'][2], l['bbox'][1], l['bbox'][3], '+'.join(dict.fromkeys(s['font'] for s in l['spans'])), '+'.join(dict.fromkeys('%g' % round(s['size'], 2) for s in l['spans'])), t))
    for r in sorted(L, key=lambda r: (round(r[0], 1), r[1])):
        print('%d\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%s\t%s' % (pi + 1, *r))
