#!/usr/bin/env python3
"""meas.py DIR > LATG-WORD.tsv: per doc, per paragraph a..f (a paragraph starts at a line whose first char is 一):
line-1 last chars, number of chars on line 1, x of each Latin glyph (origin), x of the first CJK char after the Latin run (origin), x1 of line 1."""
import sys, os, pymupdf
d = sys.argv[1]
print('# doc\tvar\tline1_nchars\tline1_tail\tlatin_on_line\tlatin_x\tcjk_after_x\tline1_x1\tline2_head')
for f in ('latgm1024', 'latg0', 'latgm2048', 'latgp1024', 'latgsnap0'):
    p = os.path.join(d, f + '-orig.pdf')
    if not os.path.exists(p): continue
    lines = []
    for pg in pymupdf.open(p):
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars']]
                ch = [c for c in ch if c['c'] != ' ']
                if ch: lines.append(ch)
    paras = []
    for ch in lines:
        if ch[0]['c'] == '一': paras.append([ch])
        elif paras: paras[-1].append(ch)
    for v, ps in zip('abcdef', paras):
        l1 = ps[0]; l2 = ps[1] if len(ps) > 1 else []
        lat = [(i, c) for i, c in enumerate(l1) if c['c'].isascii() and c['c'].strip()]
        where = 'l1'
        if not lat and l2:
            lat = [(i, c) for i, c in enumerate(l2) if c['c'].isascii() and c['c'].strip()]; where = 'l2'
        src = l1 if where == 'l1' else l2
        lx = ' '.join('%s@%.2f' % (c['c'], c['origin'][0]) for i, c in lat)
        after = ''
        if lat:
            j = lat[-1][0] + 1
            if j < len(src): after = '%s@%.2f' % (src[j]['c'], src[j]['origin'][0])
        print('%s\t%s\t%d\t%s\t%s\t%s\t%s\t%.2f\t%s' % (f, v, len(l1), ''.join(c['c'] for c in l1[-4:]), where, lx, after, l1[-1]['bbox'][2], ''.join(c['c'] for c in l2[:3])))
