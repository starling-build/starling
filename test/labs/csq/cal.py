import json, pymupdf, sys
out = {}
for c in (14, 15):
    ks = json.load(open('cal/cal-c%d.keys' % c)); d = pymupdf.open('cal/cal-c%d-orig.pdf' % c)
    ls = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [x for s in l['spans'] for x in s['chars'] if x['c'].strip()]
                if cs: ls.append(cs)
    assert len(ls) == len(ks), (c, len(ls), len(ks))
    out['c%d' % c] = {k: cs[-1]['bbox'][2] - cs[0]['bbox'][0] for k, cs in zip(ks, ls)}
json.dump(out, open('widths.json', 'w'))
print({k: round(v, 2) for k, v in list(out['c15'].items())[:6]})
