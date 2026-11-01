import sys, json, pymupdf
print('# variant\tW\tline1 ends\tline1 x-extent (x1 - x0)\tcomma hung (right edge beyond W)')
for v in 'ABC':
    ws = json.load(open(f'run/hc-{v}.ws')); d = pymupdf.open(f'run/hc-{v}-orig.pdf'); lines = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if cs: lines.append(cs)
    starts = [i for i, cs in enumerate(lines) if ''.join(c['c'] for c in cs).startswith('COVID')]
    assert len(starts) == len(ws), (v, len(starts), len(ws))
    for w, i in zip(ws, starts):
        cs = lines[i]; t = ''.join(c['c'] for c in cs); x0 = cs[0]['bbox'][0]; x1 = cs[-1]['bbox'][2]
        print(f"{v}\t{w}\t{t[-4:]}\t{x1-x0:.2f}\t{'HUNG %.2f' % (x1-x0-w) if x1-x0 > w+0.05 else ''}")
