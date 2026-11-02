import pymupdf, json
for var in 'abcd':
    for m in (12, 15):
        rs = json.load(open('test/tie-%s-m%d.json' % (var, m)))
        p = pymupdf.open('test/tie-%s-m%d-orig.pdf' % (var, m))[0]
        lines = []
        for b in p.get_text('dict')['blocks']:
            if b['type'] == 0:
                for l in b['lines']:
                    lines.append((round(l['bbox'][1], 1), ''.join(s['text'] for s in l['spans'])))
        lines.sort()
        firsts = [t for y, t in lines if t.startswith('我们')]
        assert len(firsts) == 7, (var, m, len(firsts))
        res = []
        for i, (d, r, ach) in enumerate(rs):
            l1 = firsts[i]
            res.append((ach, 'ON' if l1.rstrip().endswith('的') else 'off'))
        print(var, m, ' '.join('%+.3f:%s' % (a, s) for a, s in res))
