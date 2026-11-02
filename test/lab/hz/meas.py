#!/usr/bin/env python3
"""meas.py DIR > HZ-WORD.tsv: per doc (hz0 no grid, hz1 grid) per page (cases.txt order): baseline and bbox top/bottom of the heading line (starts with ※),
the PREV line (p cases) and the NEXT line, all in pt from the page top; plus heading baseline - text-area top (72pt), NEXT baseline - heading baseline."""
import sys, os, pymupdf
d = sys.argv[1]
keys = open(os.path.join(d, 'cases.txt')).read().split()
print('# doc\tkey\tprev_base\thead_base\thead_box_top\thead_box_bot\tnext_base\thead_base_minus_72\tnext_minus_head\tfont\tsize')
for f in ('hz0', 'hz1'):
    pdf = pymupdf.open(os.path.join(d, f + '-orig.pdf'))
    for k, page in zip(keys, pdf):
        prev = head = nxt = None; hb = None; font = ''; size = 0
        for b in page.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans'])
                base = l['spans'][0]['origin'][1]
                if t.startswith('PREV'): prev = base
                elif t.startswith('※'): head = base; hb = l['bbox']; font = l['spans'][0]['font']; size = l['spans'][0]['size']
                elif t.startswith('NEXT'): nxt = base
        if head is None: print('%s\t%s\tNONE' % (f, k)); continue
        print('%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%.1f' % (f, k, '' if prev is None else '%.2f' % prev, head, hb[1], hb[3], nxt, head - 72, nxt - head, font, size))
