"""model.py: the single-label anchor model (Word's box corner / edge middle on the rim point by sector), scored on every print.
Word box: text advance w x 10.99 pt (9 pt Calibri), fitz centre = Word centre + 0.82 pt (y)."""
import math, collections
from load import rows
HH = 10.99 / 2
def sector(th):
    t = th % 360
    # (ax, ay): anchor point on the box as fractions of half sizes (-1 left/top .. +1 right/bottom)
    if t <= 15 or t >= 345: return (0, 1)
    if t < 61: return (-1, 1)
    if t <= 105: return (-1, 0)
    if t < 165: return (-1, -1)
    if t <= 195: return (0, -1)
    if t < 240: return (1, -1)
    if t <= 285: return (1, 0)
    return (1, 1)
def place(th, R, w, h=10.99, down=1.5):
    """Word box centre (pt, rel. pie centre, y down) for a lone label."""
    ax, ay = sector(th); u = math.radians(th)
    P = (R * math.sin(u), -R * math.cos(u))
    cx = P[0] - ax * w / 2; cy = P[1] - ay * h / 2
    if ay == 0: cx = (R if ax < 0 else -R) - ax * w / 2   # side labels: inner edge on the bounding square
    if ay == -1: cy += down                                 # below the pie: a little lower
    return cx, cy
def score(R, tol=3):
    hit = collections.Counter(); n = collections.Counter(); ex = collections.defaultdict(list)
    for r in R:
        cx, cy = place(r['th'], r['R'], r['w'], r['h'] + 1.8 + 0.25)
        dx = r['dx'] - cx; dy = (r['dy'] - 0.82) - cy
        g = round(r['th'] / 5) * 5 if r['n'] != 8 or r['ang'] % 45 else round(r['th'] * 2) / 2
        key = 'edge' if (r['ang'] % 45 == 0 and r['n'] == 8) else 'clean'
        n[key] += 1; hit[key] += abs(dx) <= tol and abs(dy) <= tol; ex[key].append((dx, dy))
    return hit, n, ex
if __name__ == '__main__':
    R = [r for r in rows() if not r['inside'] and r['h'] < 12]
    hit, n, ex = score(R)
    for k in n: print('%-6s %d/%d within 3pt (%.0f%%)  median |dx| %.1f |dy| %.1f' % (k, hit[k], n[k], 100 * hit[k] / n[k], sorted(abs(a) for a, b in ex[k])[len(ex[k]) // 2], sorted(abs(b) for a, b in ex[k])[len(ex[k]) // 2]))
    # clean by angle
    G = collections.defaultdict(list)
    for r in R:
        if r['ang'] % 45 == 0 and r['n'] == 8: continue
        cx, cy = place(r['th'], r['R'], r['w'], r['h'] + 2.05); G[round(r['th'])].append((r['dx'] - cx, r['dy'] - 0.82 - cy, r['doc'], r['k']))
    bad = [(th, v) for th, v in sorted(G.items()) for v in v if abs(v[0]) > 3 or abs(v[1]) > 3]
    print(len(bad), 'clean misses:'); [print('  %5.1f dx %+5.1f dy %+5.1f %s k%d' % (th, *v)) for th, v in bad]
