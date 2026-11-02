import json, pymupdf, glob, os, sys
RUN = sys.argv[1] if len(sys.argv) > 1 else 'run'
START = '各等'
MARKS = '，、；'
rows, gaps, summ = [], [], []


def isla(c):
    return ord(c) < 0x2000


def desc(cs):
    nz = [c for c in cs if c['c'].strip()]
    cm, au = [], []
    for a, b in zip(nz, nz[1:]):
        g = b['bbox'][0] - a['bbox'][2]
        if a['c'] in MARKS:
            cm.append('%sw%.1f gap%.2f' % (a['c'], a['bbox'][2] - a['bbox'][0], g))
        elif isla(a['c']) != isla(b['c']):
            au.append('%s|%s %.2f' % (a['c'], b['c'], g))
    ii = [b['bbox'][0] - a['bbox'][2] for a, b in zip(nz, nz[1:]) if not isla(a['c']) and not isla(b['c']) and a['c'] not in MARKS]
    mean = sum(ii) / len(ii) if ii else 0
    return 'marks=%s | autospace=%s | ideo-gap mean %.2f' % (cm, au, mean)


for f in sorted(glob.glob(RUN + '/csq-*.docx')):
    n = os.path.basename(f)[:-5]
    pdf = RUN + '/' + n + '-orig.pdf'
    if not os.path.exists(pdf):
        continue
    meta = json.load(open(RUN + '/' + n + '.meta'))
    d = pymupdf.open(pdf)
    lines = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars']]
                if cs:
                    lines.append(cs)
    starts = [i for i, cs in enumerate(lines) if ''.join(c['c'] for c in cs).lstrip().startswith(START)]
    if len(starts) != len(meta):
        print('#', n, len(starts), len(meta))
        continue
    for k in sorted({m[0] for m in meta}):
        taken = last = None
        for (kk, w, nat), i in zip(meta, starts):
            if kk != k:
                continue
            cs = [c for c in lines[i] if c['c'].strip()]
            txt = ''.join(c['c'] for c in lines[i])
            ink = cs[-1]['bbox'][2] - cs[0]['bbox'][0]
            took = '移' in txt
            rows.append((n, k, round(nat, 2), round(w, 2), 'X taken' if took else 'X wrapped', txt.strip()[-4:], round(ink, 2), round(ink - w, 2) if ink > w + .05 else ''))
            if took and taken is None:
                taken = (w, nat, lines[i])
            if not took and taken is None:
                last = (w, nat, lines[i])
        summ.append((n, k, round(taken[1], 2) if taken else None, round(taken[0], 2) if taken else None, round(taken[1] - taken[0], 2) if taken else None))
        gaps.append((n, k, 'first W taking X', round(taken[0], 2) if taken else None, desc(taken[2]) if taken else ''))
        gaps.append((n, k, 'last wrapped W', round(last[0], 2) if last else None, desc(last[2]) if last else ''))
with open('csq-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\tk marks\tnatural(L+X)\tW\tX\tline1 ends\tink\tpast W\n')
    for r in rows:
        o.write('\t'.join(map(str, r)) + '\n')
with open('csq-GAPS.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\tk\twhich\tW\tadvances on that line (pt)\n')
    for r in gaps:
        o.write('\t'.join(map(str, r)) + '\n')
with open('csq-SUMMARY.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\tk\tnatural(L+X)\tfirst W taking X\tsqueeze = natural - W (pt)\n')
    for r in summ:
        o.write('\t'.join(map(str, r)) + '\n')
print(len(rows), len(gaps), len(summ))
