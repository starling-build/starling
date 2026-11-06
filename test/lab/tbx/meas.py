#!/usr/bin/env python3
"""meas.py PDF > TBX-WORD.tsv: per page (case): tag, baseline y of the "Cnn" line, its x0, baseline y of the END line, box outline bottom y (if drawn)."""
import sys, re, pymupdf
d = pymupdf.open(sys.argv[1])
print('# page\ttag\tline_baseline_y\tline_x0\tend_baseline_y\tbox_bottom_y')
for n, p in enumerate(d):
    tag = ly = lx = ey = None
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            cs = [c for s in l['spans'] for c in s['chars']]
            t = ''.join(c['c'] for c in cs)
            m = re.match(r'(C\d\d) ?政府', t)
            if m: tag, ly, lx = m.group(1), cs[0]['origin'][1], cs[0]['origin'][0]
            if re.match(r'C\d\d END', t): ey = cs[0]['origin'][1]
    bb = [dr['rect'].y1 for dr in p.get_drawings() if dr['rect'].width > 300]
    print('%d\t%s\t%s\t%s\t%s\t%s' % (n + 1, tag, '%.2f' % ly if ly else '', '%.2f' % lx if lx else '', '%.2f' % ey if ey else '', '%.2f' % max(bb) if bb else ''))
