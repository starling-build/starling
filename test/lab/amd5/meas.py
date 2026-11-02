#!/usr/bin/env python3
"""meas.py DIR > AMD5-WORD.tsv: per doc: pages; per page: n lines, first line y(baseline), last non-marker line y, marker M baseline(s), lowest drawn rect y1.
Lab A also: number of table rows' text lines ('xxxxx') on the page."""
import sys, os, glob, pymupdf
print('# doc\tpages\tpage\tnlines\tfirst_y\tlast_y\tM_y\tlowest_rect_y1\tn_xxxxx')
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*-orig.pdf'))):
    d = pymupdf.open(f); k = os.path.basename(f)[:-9]
    for pg in d:
        L = []; M = []
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).strip()
                if not t: continue
                y = l['spans'][0]['origin'][1]
                if t == 'M': M.append(y)
                else: L.append((y, t))
        L.sort()
        rs = [dr['rect'].y1 for dr in pg.get_drawings()]
        print('%s\t%d\t%d\t%d\t%s\t%s\t%s\t%s\t%d' % (k, len(d), pg.number + 1, len(L), '%.2f' % L[0][0] if L else '', '%.2f' % L[-1][0] if L else '',
              ','.join('%.2f' % y for y in M), '%.2f' % max(rs) if rs else '', sum(1 for y, t in L if t.startswith('xxxxx'))))
