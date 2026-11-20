#!/usr/bin/env python3
"""pinsweep.py PINSWEEP-WORD.tsv [R_src]  - read lab pinsweep (lenovo-2, 2026-11-07, advisor round 4).
Per labelled-slice middle m (12..31 by 0.5): Word's DEFAULT (pinned, c:manualLayout 0/0) and AUTO (best fit) text box, as
text-left / top in px (96 dpi) from the pie centre, for the slice at m and its mirror at 360-m (mirror x negated: -x1).
Prints the per-m table, the pull auto-default, and three verdict numbers: smoothness of the defaults, smoothness of the auto
places (largest half-degree jump), and mirror consistency (auto vs mirrored auto). Then the pinned-only extras (default law:
the box corner nearest the centre: its radius / R and its angle minus the slice middle)."""
import sys, math, collections, re
PX = 96 / 72
rows = collections.defaultdict(list); leaders = collections.defaultdict(list)
for ln in open(sys.argv[1]):
    if ln.startswith('#') or not ln.strip(): continue
    f = ln.rstrip('\n').split('\t')
    if f[2] == 'LEADER': leaders[f[0]].append(f); continue
    rows[f[0]].append(f)
def box(doc):
    """(left, top, right, bottom) of the label text box in px from the pie centre; None if missing / inside."""
    r = [f for f in rows.get(doc, []) if f[2] == '2']
    if not r: return None
    f = r[0]
    dx, dy, w, h = float(f[5]), float(f[6]), float(f[8]), float(f[9])
    return (dx - w / 2) * PX, (dy - h / 2) * PX, (dx + w / 2) * PX, (dy + h / 2) * PX, f[14], float(f[12])
def mirror(b):
    if b is None: return None
    l, t, r, bt, io, R = b
    return -r, t, -l, bt, io, R
def fmt(b):
    return '  ----   ----' if b is None else '%+6.1f %+6.1f' % (b[0], b[1])
print('m      | default(l,t)  auto(l,t)      pull(dx,dy) ld | mirror: default    auto           pull       ld | auto-mirauto')
prev = {}
jumps = collections.defaultdict(list); mres = []
for m2 in range(24, 63):
    m = m2 / 2; tag = '%04.1f' % m
    d, a = box('ps-%s-pin' % tag), box('ps-%s-auto' % tag)
    dm, am = mirror(box('ps-%s-pin-mir' % tag)), mirror(box('ps-%s-auto-mir' % tag))
    ld = 'L' if leaders.get('ps-%s-auto' % tag) else ' '
    ldm = 'L' if leaders.get('ps-%s-auto-mir' % tag) else ' '
    pull = '  ----  ----' if (d is None or a is None) else '%+5.1f %+5.1f' % (a[0] - d[0], a[1] - d[1])
    pullm = '  ----  ----' if (dm is None or am is None) else '%+5.1f %+5.1f' % (am[0] - dm[0], am[1] - dm[1])
    mr = '  ----  ----' if (a is None or am is None) else '%+5.1f %+5.1f' % (a[0] - am[0], a[1] - am[1])
    if a is not None and am is not None: mres.append((m, a[0] - am[0], a[1] - am[1]))
    for key, b in (('def', d), ('auto', a), ('defm', dm), ('autom', am)):
        if b is not None and key in prev: jumps[key].append((m, b[0] - prev[key][0], b[1] - prev[key][1]))
        if b is not None: prev[key] = b
    print('%s | %s  %s  %s %s | %s  %s  %s %s | %s' % (tag, fmt(d), fmt(a), pull, ld, fmt(dm), fmt(am), pullm, ldm, mr))
print()
for key, name in (('def', 'defaults'), ('defm', 'mirror defaults'), ('auto', 'auto'), ('autom', 'mirror auto')):
    j = jumps[key]
    if not j: continue
    big = [x for x in j if math.hypot(x[1], x[2]) > 3]
    print('%-16s steps: median |dx| %.1f |dy| %.1f px, max %.1f px; jumps > 3 px: %d of %d%s' % (
        name, sorted(abs(x[1]) for x in j)[len(j) // 2], sorted(abs(x[2]) for x in j)[len(j) // 2],
        max(math.hypot(x[1], x[2]) for x in j), len(big), len(j),
        '' if not big else ' at m=' + ','.join('%g' % x[0] for x in big[:12])))
if mres:
    big = [x for x in mres if math.hypot(x[1], x[2]) > 3]
    print('mirror residual (auto - mirrored auto): median %.1f px, max %.1f px, > 3 px in %d of %d' % (
        sorted(math.hypot(x[1], x[2]) for x in mres)[len(mres) // 2], max(math.hypot(x[1], x[2]) for x in mres), len(big), len(mres)))
print('\nDefault law (pinned extras): doc, middle, span, R pt, nearest corner r/R, corner angle - middle (deg, cw from 12)')
for doc in sorted(rows):
    mm = re.match(r'ps-def-(\d+(?:\.\d)?)-s(\d+)', doc)
    if not mm: continue
    b = box(doc)
    if b is None: print(doc, 'inside/missing'); continue
    l, t, r, bt, io, R = b; mid, span = float(mm.group(1)), int(mm.group(2))
    corners = [(l, t), (r, t), (l, bt), (r, bt)]
    cx, cy = min(corners, key=lambda c: math.hypot(*c))
    ang = math.degrees(math.atan2(cx, -cy)) % 360
    print('%-20s %6.1f %3d  R %.2f  r/R %.3f  ang-mid %+.1f  box l %.1f t %.1f (px)' % (doc, mid, span, R, math.hypot(cx, cy) / (R * PX), ang - mid, l, t))
