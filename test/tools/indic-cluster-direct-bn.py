#!/usr/bin/env python3
"""Bengali per-cluster advances read DIRECTLY from Word prints (the Bengali counterpart of indic-cluster-direct.py):
a cluster's advance is the next cluster's first-consonant origin minus its own, in em (median, 3+ samples).
usage: python3 test/tools/indic-cluster-direct-bn.py FACE [OUT]   FACE as embedded ("Shonar Bangla", "Shonar Bangla,Bold")
OUT (default /tmp/direct_bn_<FACE>.txt) gets Swift dictionary lines; also prints spread."""
import pymupdf, glob, collections, statistics, sys
FACE = sys.argv[1]
AUTH = bool(__import__('os').environ.get('DIRECT_AUTHORED'))  # divide by the AUTHORED size (half points), not the PDF's rounded one (11 pt prints as 11.04)
OUT = sys.argv[2] if len(sys.argv) > 2 else '/tmp/direct_bn_%s.txt' % FACE.replace(',', '_')
res = collections.defaultdict(list)
cons = lambda c: 0x995 <= ord(c) <= 0x9B9 or 0x9DC <= ord(c) <= 0x9DF or 0x985 <= ord(c) <= 0x994 or ord(c) == 0x9CE  # consonants, independent vowels, khanda ta
V = '্'
for f in glob.glob(__import__('os').environ.get('PRINTS_GLOB', '/data/corpus-cache/staging/*/word-win/*-orig.pdf')):
    try: d = pymupdf.open(f)
    except Exception: continue
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                # line-level: a word's LAST cluster ends at the space that follows it (a space may sit in another span/face)
                ch = [(c, s['font'].split('+')[-1] == FACE, s['size']) for s in l['spans'] for c in s['chars']]
                n = len(ch)
                # a cluster starts at its first consonant/vowel letter (logical order) and runs to the next one; its x is the LEFTMOST
                # origin among its characters, because a pre-base vowel sign (i e ai o au) is drawn left of the consonant
                starts = [i for i in range(n) if ch[i][1] and cons(ch[i][0]['c']) and not (i > 0 and ch[i-1][0]['c'] == V)]
                for si, i in enumerate(starts):
                    k = starts[si + 1] if si + 1 < len(starts) else None
                    # the cluster must be followed directly (no non-face char) by the next start, or by a space
                    j = i + 1
                    while j < n and ch[j][1] and j not in starts and ch[j][0]['c'] not in ' \xa0': j += 1
                    if j >= n or not (ch[j][0]['c'] in ' \xa0' or j in starts): continue
                    txt = ''.join(c['c'] for c, f, _ in ch[i:j])
                    if any(not (0x980 <= ord(c) <= 0x9FF) for c in txt): continue
                    y = ch[i][0]['origin'][1]
                    if abs(ch[j][0]['origin'][1] - y) > 0.5: continue
                    x0 = min(c['origin'][0] for c, f, _ in ch[i:j])
                    if j in starts:
                        # the next cluster's leftmost origin (its own pre-base sign, if any, comes AFTER it in logical order)
                        e = j + 1
                        while e < n and ch[e][1] and e not in starts: e += 1
                        x1 = min(c['origin'][0] for c, f, _ in ch[j:e])
                    else: x1 = ch[j][0]['origin'][0]
                    res[txt].append((x1 - x0) / (round(ch[i][2] * 2) / 2 if AUTH else ch[i][2]))
import unicodedata
with open(OUT, 'w') as o:
    k = 0; seen = set()  # Swift String keys compare canonically: a duplicate traps the dictionary literal
    for t, v in sorted(res.items(), key=lambda kv: -len(kv[1])):
        n = unicodedata.normalize('NFC', t)
        if len(v) >= int(__import__("os").environ.get("MINN","3")) and n not in seen:
            seen.add(n)
            o.write('        "%s": %.4f,  // n=%d sd=%.4f\n' % (''.join('\\u{%X}' % ord(q) for q in t), statistics.median(v), len(v), statistics.pstdev(v))); k += 1
print(k, 'clusters ->', OUT)
