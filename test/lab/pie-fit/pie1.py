"""pie1.py [LABDIR]: analyse lab pie1's Word prints (PIE1-WORD.tsv, LEADERS1-WORD.tsv in LABDIR/pie1/test/lab/pie1/).
Single labels (p1-one-aNNN): the one label's anchor against its rim point P(th) in Word's box (text advance box, hhea line:
top = fitz top - 1.8 pt, bottom = fitz bottom + 0.25), as (ax, ay) = (P - box centre) / (half w, half h), the box's clearance
from the circle, R, and which box feature is nearest the rim. Pairs (p1-pair-I-J): each label's move from its single-label
position (same angle) in px. Widths (p1-wNNN): the layouts."""
import sys, os, math, collections
if len(sys.argv) > 1: os.environ['LAB'] = sys.argv[1]
from load import rows
R = [r for r in rows() if r['doc'].startswith('p1-')]
print(len(R), 'labels in', len({r['doc'] for r in R}), 'pie1 docs')
def wbox(r): return (r['dx'] - r['w'] / 2, r['dy'] - r['h'] / 2 - 1.8, r['dx'] + r['w'] / 2, r['dy'] + r['h'] / 2 + 0.25)
def anchor(r):
    th = math.radians(r['th']); P = (r['R'] * math.sin(th), -r['R'] * math.cos(th))
    b = wbox(r); cx = (b[0] + b[2]) / 2; cy = (b[1] + b[3]) / 2
    ax = (P[0] - cx) / ((b[2] - b[0]) / 2); ay = (P[1] - cy) / ((b[3] - b[1]) / 2)
    x = min(max(0, b[0]), b[2]); y = min(max(0, b[1]), b[3]); clear = math.hypot(x, y) - r['R']
    return ax, ay, clear, P, b
single = {}
print('\n== single labels: angle  R   ax    ay   clear  box(l,t,r,b pt rel. centre)  leader')
for r in sorted((r for r in R if r['doc'].startswith('p1-one-')), key=lambda r: r['th']):
    ax, ay, clear, P, b = anchor(r); single[round(r['th'] * 2) / 2] = r
    print('%6.1f %6.2f %+5.2f %+5.2f %5.1f  (%6.1f %6.1f %6.1f %6.1f) %s%s' % (r['th'], r['R'], ax, ay, clear, *b, 'L' if r['leader'] else '', ' IN' if r['inside'] else ''))
print('\n== pairs: doc  k th  dx_from_single dy_from_single (px)  leader')
for r in sorted((r for r in R if r['doc'].startswith('p1-pair-')), key=lambda r: (r['doc'], r['k'])):
    s = single.get(round(r['th'] * 2) / 2)
    if s: print('%-14s %d %6.1f  %+6.1f %+6.1f %s' % (r['doc'], r['k'], r['th'], (r['dx'] - s['dx']) / 0.75, (r['dy'] - s['dy']) / 0.75, 'L' if r['leader'] else ''))
    else: print('%-14s %d %6.1f  (no single at this angle)' % (r['doc'], r['k'], r['th']))
print('\n== widths')
D = collections.OrderedDict()
for r in sorted((r for r in R if r['doc'].startswith('p1-w')), key=lambda r: (r['fw'], r['k'])): D.setdefault(r['doc'], []).append(r)
for d, L in D.items(): print('%-10s R%.2f |' % (d, L[0]['R']), ' '.join('%d:(%+.1f,%+.1f)%s' % (r['k'], r['dx'], r['dy'], 'L' if r['leader'] else '') for r in L))
