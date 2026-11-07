"""sim.py: a placement simulator over every print (configs.py). A rule is a function place(cfg, k, placed) -> (L, T) in px
relative to the pie centre for label k, given the boxes already placed this pass ({k: (L, T, w, h)}); run(cfg, rule, order, passes)
applies it in the given order for the given number of passes. score(rule, ...) counts labels within 4 px of Word in x and y.
Baseline rule: the landed Chart.swift rule (30/60 table, ring 0, 0.75 zone, push-out <= 1.5 px)."""
import math, collections, sys
from configs import load
H_FITZ_TO_WORD_TOP = 1.8 / 0.75   # px
CY = 133 + 1 / 3
def quad(th):
    t = th % 360; right = t <= 180; top = t < 90 or t > 270
    a = t if t <= 90 else 180 - t if t <= 180 else t - 180 if t <= 270 else 360 - t
    return right, top, a
def snap(L, T): return float(round(L)), round(T + CY) - CY
def pen(L, T, R, w, h):
    nx = 0 if L <= 0 <= L + w else (L if L > 0 else L + w); ny = 0 if T <= 0 <= T + h else (T if T > 0 else T + h)
    return R - math.hypot(nx, ny)
def lone(cfg, k, zone=(13, 30), frac=0.75, tol=1.5, down=1.5, ring=0.0):
    s0, span = cfg['slices'][k - 1]; th = (s0 + span / 2) % 360; R = cfg['R'] / 0.75
    w = cfg['labels'][k][0] / 0.75; h = 14.65
    right, top, a = quad(th); u = math.radians(th); px, py = R * math.sin(u), -R * math.cos(u)
    if zone[0] <= a < zone[1]:
        inner = abs(px) - w / 2 + frac * w / 2; L = inner if right else -(inner + w); T = -R - h if top else R + down
        return snap(L, T)
    if a < 30: L = px - w / 2; T = py - h if top else py + down
    elif a < 60:
        qx, qy = (R + ring) * math.sin(u), -(R + ring) * math.cos(u); L = qx if right else qx - w; T = qy - h if top else qy + down
    else: L = px if right else px - w; T = py - h / 2
    L, T = snap(L, T); n = 0
    while pen(L, T, R, w, h) > tol and n < 60:
        if abs(px) >= abs(py): L += 1 if px > 0 else -1
        else: T += 1 if py > 0 else -1
        n += 1
    return L, T
def run(cfg, rule, order='index', passes=1):
    ks = [k for k in cfg['kept'] if k in cfg['obs']]
    if order == 'reverse': ks = ks[::-1]
    placed = {}
    for _ in range(passes):
        for k in ks:
            L, T = rule(cfg, k, {j: v for j, v in placed.items() if j != k}); placed[k] = (L, T, cfg['labels'][k][0] / 0.75, 14.65)
    return placed
def score(rule, cfgs=None, order='index', passes=1, tol=4.0, show=0):
    cfgs = cfgs or load(); hit = collections.Counter(); n = collections.Counter(); miss = []
    for key, cfg in cfgs.items():
        pl = run(cfg, rule, order, passes)
        for k, (L0, T0, inside) in cfg['obs'].items():
            if inside or k not in pl: continue
            L, T = pl[k][:2]; f = cfg['lab']; n[f] += 1
            ok = abs(L - L0) <= tol and abs(T - T0) <= tol; hit[f] += ok
            if not ok: miss.append((key, k, round(L - L0, 1), round(T - T0, 1)))
    tot = sum(hit.values()); N = sum(n.values())
    print('%d/%d (%.0f%%)  ' % (tot, N, 100 * tot / N) + ' '.join('%s %d/%d' % (f, hit[f], n[f]) for f in sorted(n)))
    for m in miss[:show]: print('  miss', m)
    return tot
if __name__ == '__main__':
    C = load()
    score(lambda cfg, k, placed: lone(cfg, k), C)
