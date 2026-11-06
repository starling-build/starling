#!/usr/bin/env python3
"""meas.py PDF TSV > OUT.tsv: per paragraph (word, k): what stands on the first line (the part before the hyphen) and the rest."""
import sys, pymupdf
rows = [l.split('\t') for l in open(sys.argv[2]).read().split('\n') if l]
paras = []; last = None
for page in pymupdf.open(sys.argv[1]):
    ls = []
    for b in page.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(c['c'] for s in l['spans'] for c in s['chars'])
            if t.strip(): ls.append((l['bbox'][1], t.strip()))
    ls.sort(); prev = None
    for y, t in ls:
        if prev is not None and y - prev < 17 and paras and last == page.number: paras[-1].append(t)
        else: paras.append([t])
        prev = y; last = page.number
print('# idx\tword\tk\tlines (| between)')
for (idx, w, k), p in zip(rows, paras):
    print('%s\t%s\t%s\t%s' % (idx, w, k, '|'.join(p)))
print('# paragraphs', len(paras), 'rows', len(rows), file=sys.stderr)
