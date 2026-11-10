#!/usr/bin/env python3
"""Bengali cluster advances from a SPACED lab print (one cluster, a space, the next ... per line): a cluster's advance is
(next cluster's leftmost origin - its own leftmost origin)/authored size - S, S the face's space advance (default 0.2067).
The space's own origin is useless here: a conjunct's ligature glyph leaves it at the conjunct's x.
usage: python3 indic-cluster-spaced-bn.py PDF FACE [S] > swift lines"""
import pymupdf, sys, collections, statistics, unicodedata
pdf, FACE = sys.argv[1], sys.argv[2]; S = float(sys.argv[3]) if len(sys.argv) > 3 else 0.2067
cons = lambda c: 0x995 <= ord(c) <= 0x9B9 or 0x9DC <= ord(c) <= 0x9DF or 0x985 <= ord(c) <= 0x994 or ord(c) == 0x9CE
res = collections.defaultdict(list)
for pg in pymupdf.open(pdf):
    for b in pg.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            ch = [(c, s['font'].split('+')[-1] == FACE, s['size']) for s in l['spans'] for c in s['chars']]
            # split at spaces: words = runs of face chars between spaces
            words = []; cur = []
            for c, f, sz in ch:
                if c['c'] == ' ':
                    if cur: words.append(cur); cur = []
                elif f: cur.append((c, sz))
                else: cur = []
            for a, bw in zip(words, words[1:]):
                txt = ''.join(c['c'] for c, _ in a)
                if any(not (0x980 <= ord(q) <= 0x9FF) for q in txt): continue
                sz = round(a[0][1] * 2) / 2
                x0 = min(c['origin'][0] for c, _ in a); x1 = min(c['origin'][0] for c, _ in bw)
                res[txt].append((x1 - x0) / sz - S)
seen = set()
for t, v in sorted(res.items()):
    n = unicodedata.normalize('NFC', t)
    if n in seen or len(v) < 2: continue
    seen.add(n)
    print('        "%s": %.4f,  // n=%d sd=%.4f' % (''.join('\\u{%X}' % ord(q) for q in t), statistics.median(v), len(v), statistics.pstdev(v)))
