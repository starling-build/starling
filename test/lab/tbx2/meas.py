#!/usr/bin/env python3
"""meas.py DIR_OF_PDFS > TBX2-WORD.tsv: for each tbx2-cNN.pdf, PAGE 1: baseline y and x0 of the "政府…" line, baseline y of the table's first row (會計科目), box outline bottom y.
(PDFs named tbx2-cNN.pdf, one per tbx2-cNN.docx.)"""
import sys, re, glob, pymupdf
print('# case\tline_baseline_y\tline_x0\ttable_text_y\tbox_bottom_y')
for f in sorted(glob.glob(sys.argv[1] + '/tbx2-c*.pdf')):
    p = pymupdf.open(f)[0]; ly = lx = ty = None
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            cs = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
            t = ''.join(c['c'] for c in cs)
            if t.startswith('政府補助款'): ly, lx = cs[0]['origin'][1], cs[0]['origin'][0]
            if t.startswith('會計科目') and ty is None: ty = cs[0]['origin'][1]
    bb = [dr['rect'].y1 for dr in p.get_drawings() if dr['rect'].width > 300]
    print('%s\t%s\t%s\t%s\t%s' % (re.search(r'c(\d\d)', f).group(1), '%.2f' % ly if ly else '', '%.2f' % lx if lx else '', '%.2f' % ty if ty else '', '%.2f' % max(bb) if bb else ''))
