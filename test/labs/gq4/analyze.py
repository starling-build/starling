#!/usr/bin/env python3
"""analyze.py gq4-gOrig.pdf gq4-gCS0.pdf gq4-gLines.pdf [--index gq4-index.tsv] > gq4.tsv -- per configuration the characters (blanks not counted) on line 1 at R = 0..12pt, and line 1's text at R=0."""
import sys, os, fitz, collections
args = [a for a in sys.argv[1:]]
idx = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gq4-index.tsv')
if '--index' in args: i = args.index('--index'); idx = args[i + 1]; del args[i:i + 2]
rows = collections.defaultdict(list)
for l in list(open(idx))[1:]:
    d, pg, v, r, t = l.rstrip('\n').split('\t'); rows[d].append((int(pg), v, int(r)))
res = collections.OrderedDict(); first = {}
for pdf in args:
    d = os.path.basename(pdf).replace('gq4-', '').replace('.pdf', '')
    doc = fitz.open(pdf)
    for (pg, v, r), page in zip(rows[d], doc):
        lines = []
        for b in page.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(s['text'] for s in l['spans']).replace(' ', '').replace('　', '')
                if t: lines.append((round(l['bbox'][1], 1), t))
        lines.sort(); t = lines[0][1] if lines else ''
        res.setdefault(v, []).append(len(t))
        if r == 0: first[v] = t
print('# variant  chars on line 1 at R = 0..12pt   | line 1 at R=0')
for v, ns in res.items(): print('%s\t%s\t| %s' % (v, ' '.join(map(str, ns)), first.get(v, '')))
