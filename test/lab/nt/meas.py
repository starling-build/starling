#!/usr/bin/env python3
"""meas.py DIR > NT-WORD.tsv: for every page of nt*-orig.pdf, each paragraph in order (cases from DIR/cases.txt):
case, number x0 / last glyph x0 / number x1 (relative to the 90pt margin), first text char x0, number width, and text - (hang position 107.7 = margin + (2154) twips)."""
import sys, os, pymupdf
d = sys.argv[1]
cases = open(os.path.join(d, 'cases.txt'), encoding='utf-8').read().split()
print('# doc\tcase\tnum_x0\tlast_glyph_x0\tnum_x1\ttext_x0\tnum_w\tend_minus_hang\ttext_minus_hang\tnumber')
for f in ('nt15', 'nt14'):
    k = 0
    for page in pymupdf.open(os.path.join(d, f + '-orig.pdf')):
        for b in page.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars']]
                s = ''.join(c['c'] for c in ch)
                if '乙' not in s: continue
                i = s.index('乙')
                num = ch[:i]
                if not [c for c in num if c['c'] != ' ']: continue
                while num and num[-1]['c'] == ' ': num = num[:-1]
                x0 = num[0]['bbox'][0] - 90; x1 = num[-1]['bbox'][2] - 90; lg = num[-1]['origin'][0] - 90; tx = ch[i]['origin'][0] - 90
                hang = 2154 / 20
                print('%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%+.2f\t%+.2f\t%s' % (f, cases[k], x0, lg, x1, tx, x1 - x0, x1 - hang, tx - hang, ''.join(c['c'] for c in num)))
                k += 1
