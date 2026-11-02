import json, pymupdf, glob, os, sys
RUN = sys.argv[1] if len(sys.argv) > 1 else 'run'
START = '政府機'
rows = []
gaps = []


def isla(c):
    return ord(c) < 0x2000


def desc(cs):
    """cs = all chars of a line (incl. spaces). spaces: widths of ' ' chars; commas: width and gap after; autospace: Latin|CJK boundary gaps (non-space neighbours)."""
    sp = [round(c['bbox'][2] - c['bbox'][0], 2) for c in cs if c['c'] == ' ']
    nz = [c for c in cs if c['c'] != ' ']
    cm = []
    au = []
    for a, b in zip(nz, nz[1:]):
        g = b['bbox'][0] - a['bbox'][2]
        if a['c'] == '，':
            cm.append('，w%.1f gap%.2f' % (a['bbox'][2] - a['bbox'][0], g))
        elif isla(a['c']) != isla(b['c']):
            au.append('%s|%s %.2f' % (a['c'], b['c'], g))
    ii = [b['bbox'][0] - a['bbox'][2] for a, b in zip(nz, nz[1:]) if not isla(a['c']) and not isla(b['c']) and a['c'] != '，']
    mean = sum(ii) / len(ii) if ii else 0
    return 'spaces=%s | commas=%s | autospace=%s | ideo-gap mean %.2f' % (sp, cm, au, mean)


for f in sorted(glob.glob(RUN + '/wsf-*.docx')):
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
    for k in (0, 1, 3):
        taken = None
        last = None
        for (kk, w), i in zip(meta, starts):
            if kk != k:
                continue
            cs = [c for c in lines[i] if c['c'].strip()]
            txt = ''.join(c['c'] for c in lines[i])
            ink = cs[-1]['bbox'][2] - cs[0]['bbox'][0]
            took = '移工' in txt.replace(' ', '')
            rows.append((n, k, w, txt.strip()[-4:], round(ink, 2), round(ink - w, 2) if ink > w + .05 else ''))
            if took and taken is None:
                taken = (w, lines[i])
            if not took and taken is None:
                last = (w, lines[i])
        gaps.append((n, k, 'first W taking X', taken[0] if taken else None, desc(taken[1]) if taken else ''))
        gaps.append((n, k, 'last wrapped W', last[0] if last else None, desc(last[1]) if last else ''))
with open('wsf-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\tk inner commas\tW\tline1 ends\tink\tpast W\n')
    for r in rows:
        o.write('\t'.join(map(str, r)) + '\n')
with open('wsf-GAPS.tsv', 'w', encoding='utf8') as o:
    o.write('# variant\tk\twhich\tW\tper-gap advances on that line (pt)\n')
    for r in gaps:
        o.write('\t'.join(map(str, r)) + '\n')
print(len(rows), len(gaps))
