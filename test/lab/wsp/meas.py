#!/usr/bin/env python3
"""meas.py DIR [SUFFIX] > WSP-WORD.tsv: per variant (V SUFFIX .pdf) and stepped paragraph in order (the control,
the document's own paragraph, comes first and is printed as T=src with its every line): T, the first line's last two
characters, x1 of its last character, and the drawn advance of each mark, space and label glyph on that line
(char:advance, advance = next origin - this origin; the last character's is its bbox width)."""
import sys, os, pymupdf
suf = sys.argv[2] if len(sys.argv) > 2 else ''
ST = [round(-8 + 0.5 * i, 1) for i in range(49)]
V = [('wsp-a', ST, '範例', '範例'), ('wsp-b', ST, '範例', '範例'), ('wsp-c', ST, '範例', '範例'), ('wsp-d', ST, '範例', '範例')]
MARKS = set('。，、：；！？”“’‘（）「」 ()[].,:;範例2')
def lines(f):
    rows = []
    for pn, p in enumerate(pymupdf.open(f), 1):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [c for s in l['spans'] for c in s['chars']]
                if cs: rows.append((pn, round(l['bbox'][3], 1), cs))
    rows.sort(key=lambda r: (r[0], r[1]))
    out = []
    for pn, y, cs in rows:
        if out and out[-1][0] == pn and abs(out[-1][1] - y) < 3: out[-1][2].extend(cs)
        else: out.append([pn, y, list(cs)])
    return [sorted(cs, key=lambda c: c['origin'][0]) for pn, y, cs in out]
def adv(cs):
    r = []
    for i, c in enumerate(cs):
        if c['c'] in MARKS:
            a = cs[i + 1]['origin'][0] - c['origin'][0] if i + 1 < len(cs) else c['bbox'][2] - c['bbox'][0]
            r.append('%s:%.2f' % (c['c'] if c['c'] != ' ' else '_', a))
    return ' '.join(r)
print('# variant\tT\tlast2\tx1_last\tadvances\tline')
for v, steps, start, ctl in V:
    f = os.path.join(sys.argv[1], v + suf + '.pdf')
    if not os.path.exists(f): continue
    ls = lines(f)
    txt = [''.join(c['c'] for c in cs).strip() for cs in ls]
    firsts = [i for i, t in enumerate(txt) if t.startswith(start)]
    c0 = [i for i, t in enumerate(txt) if ctl and t.startswith(ctl)] or firsts[:1]
    c0 = c0[:1]
    # (the control paragraph may hold a line with the same start: the stepped paragraphs are the last ones)
    if len(firsts) > len(steps): firsts = firsts[len(firsts) - len(steps):]
    if c0:
        end = firsts[0] if firsts else len(ls)
        for i in range(c0[0], end):
            print('%s\tsrc\t%s\t%.2f\t%s\t%s' % (v, txt[i][-2:], ls[i][-1]['bbox'][2], adv(ls[i]), txt[i]))
    for k, i in enumerate(firsts):
        cs = ls[i]
        print('%s\t%s\t%s\t%.2f\t%s\t%s' % (v, steps[k] if k < len(steps) else '?', txt[i][-2:], cs[-1]['bbox'][2], adv(cs), txt[i]))
