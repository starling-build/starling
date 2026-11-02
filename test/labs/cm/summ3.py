#!/usr/bin/env python3
"""summ.py CM2-WORD.tsv PDF > CM2-SUMMARY.txt: per table Kn: pages it covers, every A line (page, baseline), per page the first and last right-hand line (head/foot) with baseline,
and the vertical border segments (x, y0, y1) per page to see where the rules end."""
import sys, re, collections, pymupdf
rows = [l.rstrip('\n').split('\t') for l in open(sys.argv[1], encoding='utf8') if not l.startswith('#') and l.strip() and not l.startswith('page')]
T = collections.defaultdict(lambda: collections.defaultdict(list))
for r in rows:
    pg, base, text = int(r[0]), float(r[2]), r[4]
    m = re.match(r'([NP]\d+)(-.*)?$', text)
    if m: T[m.group(1)][pg].append((base, text))
pdf = pymupdf.open(sys.argv[2])
def vsegs(pg):
    out = []
    for d in pdf[pg - 1].get_drawings():
        r = d['rect']
        if r.width < 1.5 and r.height > 2: out.append((round(r.x0, 1), round(r.y0, 1), round(r.y1, 1)))
    return sorted(set(out))
for k in sorted(T, key=lambda s: min(T[s])):
    print('== %s: pages %s' % (k, sorted(T[k])))
    for pg in sorted(T[k]):
        L = sorted(T[k][pg]); A = [(b, t) for b, t in L if re.search(r'-A\d+$', t)]; R = [(b, t) for b, t in L if '-r' in t]
        print('  p%d  A: %s' % (pg, ', '.join('%s@%.2f' % (t, b) for b, t in A) or '-'))
        if R: print('      right head %s@%.2f   foot %s@%.2f   (%d right lines)' % (R[0][1], R[0][0], R[-1][1], R[-1][0], len(R)))
        vs = vsegs(pg)
        if vs: print('      vertical rules: ' + '; '.join('x%.1f y%.1f-%.1f' % v for v in vs))
