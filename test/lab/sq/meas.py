import json, sys, glob, os, pymupdf
L = json.load(open('cal/lines.json', encoding='utf8'))
DELTAS = (1.0, 1.6, 2.2, 3.0)
def lines_of(path):
    out = []
    for p in pymupdf.open(path):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars']]
                if cs: out.append(cs)
    return out
def ns(cs): return [(c['c'], c['origin'][0]) for c in cs if c['c'].strip()]
cal = {}
for f in glob.glob('cal/*-orig.pdf'):
    tag = os.path.basename(f)[4:-9]; ls = lines_of(f)
    cal[tag] = {k: ns(cs) for (k, sz, t), cs in zip(L, ls)}
W = json.load(open('widths.json'))
print('# container\tsetting\tkey\tdelta\ttaken\tends_after\tshrink per gap (pair: natural -> printed)\tline1 width')
for f in sorted(glob.glob(sys.argv[1] + '/*-orig.pdf')):
    nm = os.path.basename(f)[:-9]; _, cont, tag = nm.split('-', 2)
    ls = lines_of(f); starts = []
    for i, cs in enumerate(ls):
        s = ''.join(c['c'] for c in cs)
        if s.startswith('各等級全') or s.startswith('The quick'): starts.append(i)
    if len(starts) != len(L) * 4:
        print(f'# {nm}: found {len(starts)} paragraph starts, expected {len(L)*4}'); continue
    n = 0
    for (key, sz, t) in L:
        for d in DELTAS:
            cs = ls[starts[n]]; n += 1
            glyphs = ns(cs); txt = ''.join(c for c, _ in glyphs)
            tnos = ''.join(ch for ch in t if ch.strip())
            kind = key[0]
            last = 'today' if kind == 'P' else '經'
            taken = (txt.find(last) >= 0) if kind != 'P' else txt.endswith('today') or 'today' in txt
            ends = txt[len(tnos):len(tnos) + 3] if taken else ''
            shr = []
            if taken:
                cg = cal[tag][key]
                for i in range(min(len(cg), len(glyphs)) - 1):
                    dn = cg[i + 1][1] - cg[i][1]; dp = glyphs[i + 1][1] - glyphs[i][1]
                    if abs(dn - dp) > 0.15: shr.append(f'{cg[i][0]}{cg[i+1][0]}:{dn:.2f}->{dp:.2f}')
            x0 = cs[0]['bbox'][0]; x1 = max(c['bbox'][2] for c in cs if c['c'].strip())
            print(f"{cont}\t{tag}\t{key}\t{d}\t{'TAKEN' if taken else 'wrapped'}\t{ends}\t{' '.join(shr[:12])}\t{x1-x0:.2f}")
