#!/usr/bin/env python3
"""meas.py DIR > EC-WORD.tsv: per variant and case: T (room left, pt), page of K marker, page of X, X's top y and baseline, last filler's baseline on its page. page offsets relative to the case's first page. Empty paragraph: on the K page iff X's page == K page, or (X on next page at y_top) ."""
import sys, os, re, pymupdf
T = {int(l.split()[0]): l.split()[1] for l in open(os.path.join(sys.argv[1], 'cases.txt'))}
print('# variant\tcase\tT_room_pt\tK_page\tX_page\tX_dpage\tX_top\tX_base\tlastfiller_base\tfiller_last_page')
for v in 'abc':
    d = pymupdf.open(os.path.join(sys.argv[1], 'ec%s-orig.pdf' % v))
    K = {}; X = {}; L = {}
    for pn, p in enumerate(d):
        for b in p.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).strip()
                m = re.fullmatch(r'K(\d\d)', t)
                if m: K[int(m.group(1))] = pn
                m = re.fullmatch(r'X(\d\d)', t)
                if m: X[int(m.group(1))] = (pn, l['bbox'][1], l['spans'][0]['origin'][1])
                if t == 'filler-last': L[len(K) - 1] = (pn, l['spans'][0]['origin'][1])
    for i in sorted(K):
        x = X.get(i); l = L.get(i)
        print('%s\t%d\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s' % (v, i, T[i], K[i] + 1, x[0] + 1 if x else '-', (x[0] - K[i]) if x else '-', '%.2f' % x[1] if x else '-', '%.2f' % x[2] if x else '-', '%.2f' % l[1] if l else '-', l[0] + 1 if l else '-'))
