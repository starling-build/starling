import pymupdf, re, glob, os
rows = []
for f in sorted(glob.glob('run/*-orig.pdf')):
    nm = os.path.basename(f)[:-9]; d = pymupdf.open(f)
    pages = []
    for p in d:
        L = []
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(c['c'] for s in l['spans'] for c in s['chars']).strip()
                if t and not t.isdigit(): L.append((round(l['spans'][0]['chars'][0]['origin'][1], 1), t))
        L.sort(); pages.append(L)
    i = 0
    while i < len(pages):
        L = pages[i]
        m = next((re.match(r'P(\d+)$', t) for y, t in L if re.match(r'P(\d+)$', t)), None)
        if not m: i += 1; continue
        dd = int(m.group(1)); mk = [y for y, t in L if re.match(r'P\d+$', t)][0]
        lines = [y for y, t in L if not re.match(r'P\d+$', t) and y > mk + 1]
        nxt = pages[i + 1] if i + 1 < len(pages) and not any(re.match(r'P\d+$', t) for y, t in pages[i + 1]) else []
        rows.append((nm, dd, len(lines), ' '.join('%.1f' % y for y in lines), '%.1f' % nxt[0][0] if nxt else '', len(nxt)))
        i += 2 if nxt else 1
with open('PF-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# doc\td (room from filler end to body bottom 778.9)\tkept lines on page 1\tbaselines on page 1\tfirst baseline on page 2\tlines on page 2\n')
    for r in rows: o.write('\t'.join(map(str, r)) + '\n')
# thresholds
import collections
by = collections.defaultdict(list)
for r in rows: by[r[0]].append(r)
for nm, rs in by.items():
    th = []
    for k in range(1, 7):
        ds = [r[1] for r in rs if r[2] >= k]
        th.append(min(ds) if ds else None)
    print(nm, 'smallest d with kept>=1..6:', th, 'pages', len(rs))
