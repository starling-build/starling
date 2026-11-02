import json, pymupdf, glob, os, sys
out = {}
for f in sorted(glob.glob('cal/cal-b*.docx')):
    n = os.path.basename(f)[4:-5]; ks = json.load(open(f'cal/cal-{n}.keys')); d = pymupdf.open(f'cal/cal-{n}-orig.pdf')
    ls = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if cs: ls.append(cs)
    assert len(ls) == len(ks), (n, len(ls), len(ks))
    wd = {tuple(k): cs[-1]['bbox'][2] - cs[0]['bbox'][0] for k, cs in zip(ks, ls)}
    out[n] = {l: [wd[(l, 'L')], max(wd[(l, 'c')], wd[(l, 's')], wd[(l, 'p')])] for l in 'daA'}
    print(n, {l: [round(v, 2) for v in out[n][l]] for l in out[n]})
json.dump(out, open('widths.json', 'w'))
