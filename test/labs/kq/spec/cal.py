import json, pymupdf, glob, os
out = {}
for f in sorted(glob.glob('cal/cal-m*.docx')):
    n = os.path.basename(f)[4:-5]
    ks = json.load(open('cal/cal-%s.keys' % n))
    d = pymupdf.open('cal/cal-%s-orig.pdf' % n)
    ls = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if cs:
                    ls.append(cs)
    assert len(ls) == len(ks), (n, len(ls), len(ks))
    out[n] = {k: cs[-1]['bbox'][2] - cs[0]['bbox'][0] for k, cs in zip(ks, ls)}
    print(n, {k: round(v, 2) for k, v in out[n].items()})
json.dump(out, open('widths.json', 'w'))
