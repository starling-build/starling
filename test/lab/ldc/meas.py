#!/usr/bin/env python3
"""meas.py PDF -> per paragraph in order: how the line holding 獲選 ends: 計 (taken), 合 (refused), else other."""
import sys, pymupdf
d = pymupdf.open(sys.argv[1]); k = 0
for pg in d:
    for b in pg.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']).rstrip()
            if '獲選' in t: print(k, t[-1], t); k += 1
