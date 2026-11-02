#!/usr/bin/env python3
"""meas2.py DIR [SUFFIX] > BSP2-WORD.tsv: per variant (bsp-V SUFFIX .pdf) and paragraph in order: T, the first line's last
two characters, x1 of its last character, and the drawn advance of each space after "条" on that line."""
import sys, os, pymupdf
suf = sys.argv[2] if len(sys.argv) > 2 else ''
T = {}
T.update({k: [round(7.0 + 0.2 * i, 2) for i in range(21)] for k in 'hij'})
print('# variant\tT\tfirst_line_last2\tx1_last\tspace_advances\tfirst_line_text')
for v in 'hij':
    f = os.path.join(sys.argv[1], 'bsp-%s%s.pdf' % (v, suf))
    if not os.path.exists(f): continue
    rows = []
    for pn, p in enumerate(pymupdf.open(f), 1):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars']]
                if cs: rows.append((pn, round(l['bbox'][1], 1), l['bbox'][0], cs))
    rows.sort(key=lambda r: (r[0], r[1], r[2]))
    # (merge pieces of one line: same page, same y)
    lines = []
    for pn, y, x0, cs in rows:
        if lines and lines[-1][0] == pn and abs(lines[-1][1] - y) < 2: lines[-1][2].extend(cs)
        else: lines.append([pn, y, list(cs)])
    firsts = [sorted(cs, key=lambda c: c['bbox'][0]) for pn, y, cs in lines if ''.join(c['c'] for c in sorted(cs, key=lambda c: c['bbox'][0])).startswith(('第三十八条', '第四条'))]
    for i, cs in enumerate(firsts):
        t = ''.join(c['c'] for c in cs)
        k = t.index('条')
        sp, j = [], k + 1
        while j < len(cs) and cs[j]['c'] == ' ':
            sp.append('%.2f' % (cs[j + 1]['origin'][0] - cs[j]['origin'][0]) if j + 1 < len(cs) else '?'); j += 1
        print('%s\t%s\t%s\t%.2f\t%s\t%s' % (v, T[v][i] if i < len(T[v]) else '?', t.rstrip()[-2:], cs[-1]['bbox'][2], ','.join(sp), t))
