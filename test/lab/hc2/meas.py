import json, pymupdf
START = {'1a': '《山东省', '1b': '等有关法律', '2': 'COVID', '3': 'COVID'}
print('# variant\tW\tline1 ends\tink extent (x1-x0)\tpast W')
for v in ('1a', '1b', '2', '3'):
    ws = json.load(open(f'run/hc2-{v}.ws')); d = pymupdf.open(f'run/hc2-{v}-orig.pdf'); lines = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if cs: lines.append(cs)
    starts = [i for i, cs in enumerate(lines) if ''.join(c['c'] for c in cs).startswith(START[v])]
    if len(starts) != len(ws): print('#', v, len(starts), len(ws)); continue
    for w, i in zip(ws, starts):
        cs = lines[i]; t = ''.join(c['c'] for c in cs); x0 = cs[0]['bbox'][0]; x1 = cs[-1]['bbox'][2]
        print(f"{v}\t{w}\t{t[-5:]}\t{x1-x0:.2f}\t{'%.2f' % (x1-x0-w) if x1-x0 > w+0.05 else ''}")
