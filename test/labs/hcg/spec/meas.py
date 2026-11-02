import json, pymupdf, glob, os, re
def isla(c): return ord(c) < 0x2000
rows = []; gaps = []
for f in sorted(glob.glob('run3/hcg-*.docx')):
    n = os.path.basename(f)[:-5]; pdf = f'run3/{n}-orig.pdf'
    if not os.path.exists(pdf): continue
    meta = json.load(open(f'run3/{n}.meta')); d = pymupdf.open(pdf); lines = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip() or True]
                cs = [c for c in cs if c['c'] != ' ' or True]
                if cs: lines.append(cs)
    starts = [i for i, cs in enumerate(lines) if ''.join(c['c'] for c in cs).lstrip().startswith('COVID')]
    if len(starts) != len(meta): print('#', n, len(starts), len(meta)); continue
    for tail in 'cps':
        taken = None; last = None
        for (t, w), i in zip(meta, starts):
            if t != tail: continue
            cs = [c for c in lines[i] if c['c'].strip()]; txt = ''.join(c['c'] for c in cs)
            x0 = cs[0]['bbox'][0]; x1 = cs[-1]['bbox'][2]
            ink = x1 - x0
            took = '移工' in txt
            rows.append((n, tail, w, txt[-5:], round(ink, 2), round(ink - w, 2) if ink > w + .05 else ''))
            if took and taken is None: taken = (w, cs, ink)
            if not took and taken is None: last = (w, cs, ink)
        def gp(cs):
            out = []
            for a, b in zip(cs, cs[1:]):
                if isla(a['c']) != isla(b['c']) or a['c'] in '，；' or b['c'] in '，；工':
                    out.append(f"{a['c']}|{b['c']}:{b['bbox'][0]-a['bbox'][2]:.2f}")
            return ' '.join(out)
        def cw(cs):
            return ' '.join(f"{c['c']}{c['bbox'][2]-c['bbox'][0]:.1f}" for c in cs if c['c'] in '，；工並')
        gaps.append((n, tail, 'first W taking X', taken[0] if taken else None, (gp(taken[1]) + ' ; ' + cw(taken[1])) if taken else ''))
        gaps.append((n, tail, 'last wrapped W', last[0] if last else None, (gp(last[1]) + ' ; ' + cw(last[1])) if last else ''))
with open('hcg-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\ttail\tW\tline1 ends\tink\tpast W\n')
    for r in rows: o.write('\t'.join(map(str, r)) + '\n')
with open('hcg-GAPS.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\ttail\twhich\tW\tboundary gaps (pt, next.x0 - prev.x1) ; widths of 工/，/；/並\n')
    for r in gaps: o.write('\t'.join(map(str, r)) + '\n')
print(len(rows), len(gaps))
