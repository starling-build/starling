import json, sys, glob, os, pymupdf
L = json.load(open('cal/lines.json', encoding='utf8'))
res = {}
for f in glob.glob('cal/*-orig.pdf'):
    tag = os.path.basename(f)[4:-9]
    d = pymupdf.open(f); lines = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars']]
                if cs: lines.append((cs[0]['bbox'][0], max(c['bbox'][2] for c in cs if c['c'].strip()), ''.join(c['c'] for c in cs)))
    assert len(lines) == len(L), (tag, len(lines), len(L))
    res[tag] = {k: round(x1 - x0, 3) for (k, sz, t), (x0, x1, txt) in zip(L, lines)}
json.dump(res, open('widths.json', 'w'))
for t in res: print(t, list(res[t].items())[:4], list(res[t].items())[-1])
