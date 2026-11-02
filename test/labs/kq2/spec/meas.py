import json, pymupdf, glob, os, sys
RUN = sys.argv[1] if len(sys.argv) > 1 else 'run'
START = '各等級'
MK = '，、”'
rows = []
summ = []
wd = json.load(open('widths.json'))
for f in sorted(glob.glob(RUN + '/kq2-*.docx')):
    n = os.path.basename(f)[:-5]
    pdf = RUN + '/' + n + '-orig.pdf'
    if not os.path.exists(pdf):
        continue
    meta = json.load(open(RUN + '/' + n + '.meta'))
    pp = n.split('-'); compat = pp[1]; mark = pp[3]
    d = pymupdf.open(pdf)
    lines = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if cs:
                    lines.append(cs)
    starts = [i for i, cs in enumerate(lines) if ''.join(c['c'] for c in cs).startswith(START)]
    if len(starts) != len(meta):
        print('#', n, len(starts), len(meta))
        continue
    for k in (0, 1, 2, 4):
        first = None
        for (kk, w), i in zip(meta, starts):
            if kk != k:
                continue
            cs = lines[i]
            t = ''.join(c['c'] for c in cs)
            nxt = lines[i + 1] if i + 1 < len(lines) else []
            t2 = ''.join(c['c'] for c in nxt)
            ink = cs[-1]['bbox'][2] - cs[0]['bbox'][0]
            mk_w = [c['bbox'][2] - c['bbox'][0] for c in cs if c['c'] in MK]
            on = t[-1] in MK
            nat = wd[compat]['L-%d' % k]
            over = nat + (16 if mark != 'q' and False else 0)
            rows.append((n, k, w, 'on line1' if on else 'next line' if t2[:1] in MK else 'other', t[-3:], t2[:3], round(ink, 2), round(ink - w, 2) if ink > w + .05 else '', ''.join('%.1f ' % x for x in mk_w[-1:])))
            if on and first is None:
                first = (w, round(ink - w, 2) if ink > w + .05 else 0)
        summ.append((n, k, first))
with open('kq2-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\tk inner commas\tW\tmark\tline1 ends\tline2 starts\tink\tpast W\tmark width on line1\n')
    for r in rows:
        o.write('\t'.join(map(str, r)) + '\n')
with open('kq2-SUMMARY.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\tk\tfirst W with the mark kept on line 1 (W, ink past W)\n')
    for r in summ:
        o.write('\t'.join(map(str, r)) + '\n')
print(len(rows))
