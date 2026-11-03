#!/usr/bin/env python3
"""meas.py PDF > CMS-WORD.tsv: per variant (V1..), each col-B line (R<row>-<k>) and each merged-text piece (用地、用能、环境
or its parts) with page and baseline y. Variant starts at the page holding 'V<n> filler 1'."""
import sys, re, pymupdf
d = pymupdf.open(sys.argv[1])
print('# variant\tkind\ttext\tpage\tx0\tbaseline')
v = 0
for pn, p in enumerate(d):
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).strip()
            if not t: continue
            m = re.match(r'V(\d+) filler 1', t)
            if m: v = int(m.group(1)); continue
            y = round(l['spans'][0]['origin'][1], 2); x = round(l['bbox'][0], 1)
            if re.fullmatch(r'R\d+-\d+', t): print('%d\trow\t%s\t%d\t%.1f\t%.2f' % (v, t, pn, x, y))
            elif any(c in t for c in '用地能环境'): print('%d\tmerged\t%s\t%d\t%.1f\t%.2f' % (v, t, pn, x, y))
            elif t.startswith('end V'): print('%d\tend\t%s\t%d\t%.1f\t%.2f' % (v, t, pn, x, y))
