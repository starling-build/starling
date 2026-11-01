#!/usr/bin/env python3
"""meas.py DIR_WITH_PDFS : per PDF, the page and (x, y) of the tokens F T1 T2 x LONG1 LONG20 LONG40, one line per file."""
import sys, glob, os, pymupdf
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*.pdf'))):
    d = pymupdf.open(f); pos = {}
    for pi, p in enumerate(d):
        for w in p.get_text('words'):
            if w[4] in ('F', 'T1', 'T2', 'x', 'LONG1', 'LONG20', 'LONG40'): pos.setdefault(w[4], (pi + 1, round(w[0], 1), round(w[1], 1)))
    print(os.path.basename(f)[:-4].ljust(22), len(d), 'pg ', ' '.join(f'{k}={pos[k]}' for k in ('F', 'T1', 'T2', 'x', 'LONG1', 'LONG20', 'LONG40') if k in pos))
