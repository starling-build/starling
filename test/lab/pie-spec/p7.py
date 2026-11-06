#!/usr/bin/env python3
"""p7.py LABDIR > PREDICT.tsv (amd-opus, round 2 of the lo-f9b9a8fc label-5 spec, docs/plans/pie-labels.md).
LABDIR holds the prints branches' test/lab trees side by side: LABDIR/<any>/test/lab/{pielabel3,pieang,piewid,pielabel5,pielabel6}
(git archive origin/wip/lab-<name>-prints test/lab | tar -x -C LABDIR/<name>).
Per print: the outside labels, how many of them today's Chart.swift rule (the tuneFlat branch of _pieLabels) puts within
3 pt of Word (x and y, and y alone), which labels carry Word's leader line, and every pair of label boxes' separation.
Last lines: the totals and the ceiling of any fixed per-angle rule (best constant offset per radius and angle)."""
import sys, glob, math, re, zipfile, collections
L = sys.argv[1]
def angles():
    A = {}
    for f in glob.glob(L + '/*/test/lab/*/docs/*.docx'):
        c = zipfile.ZipFile(f).read('word/charts/chart1.xml').decode()
        a = int(re.search(r'firstSliceAng val="(\d+)"', c).group(1))
        v = [float(x) for x in re.findall(r'<c:v>([\d.]+)</c:v>', re.search(r'<c:val>.*?</c:val>', c, re.S).group(0))]
        A[f.split('/')[-1][:-5]] = (a, v)
    return A
A = angles(); docs = collections.OrderedDict(); lead = collections.defaultdict(set)
for f in sorted(glob.glob(L + '/*/test/lab/*/*.tsv')):
    if 'LEADERS' in f:
        for ln in open(f):
            p = ln.rstrip('\n').split('\t')
            if ln.startswith('#') or len(p) < 2: continue
            lead[p[0]]
            if p[1] not in ('-', '?'): lead[p[0]].add(int(p[1]))
        continue
    if not re.search(r'(PIELABEL5|PIELABEL6|PIEEQ|PIEWID|PIEANG)-WORD', f): continue
    for ln in open(f):
        if ln.startswith('#'): continue
        p = ln.rstrip('\n').split('\t'); d, k = p[0], int(p[1])
        if p[13] != 'OUT': continue
        a, v = A[d]; t = sum(v); cum = sum(v[:k - 1])
        docs.setdefault(d, {})[k] = dict(dx=float(p[4]), dy=float(p[5]), w=float(p[7]), h=float(p[8]), R=float(p[11]),
                                          th=(a + 360 * (cum + v[k - 1] / 2) / t) % 360)
def today(th, R, w, h):  # Chart.swift _pieLabels, tuneFlat: gap 0 across, 3.5 pt up/down x uprightness, half width ramp
    u = math.radians(th); dx, dy = math.sin(u), -math.cos(u); hw = min(1, abs(dx) / 0.5) * w / 2
    return R * dx + (hw if dx >= 0 else -hw), R * dy + dy * abs(dy) * (3.5 + h / 2)
def box(r): return (r['dx'] - r['w'] / 2, r['dy'] - r['h'] / 2, r['dx'] + r['w'] / 2, r['dy'] + r['h'] / 2)
print('# doc\tR\tn_out\thit_xy\thit_y\tleaders\tmin_box_sep_pt\tword_label_at_202.5(dx,dy)')
T = [0, 0, 0]; G = collections.defaultdict(list)
for d, l in docs.items():
    n = hx = hy = 0
    for k, r in l.items():
        x, y = today(r['th'], r['R'], r['w'], r['h']); ex, ey = r['dx'] - x, r['dy'] - y; n += 1
        hy += abs(ey) <= 3; hx += abs(ey) <= 3 and abs(ex) <= 3
        G[(round(r['R']), round(r['th'], 1), round(r['w']))].append((ex, ey))
    sep = min((max(max(b[0] - a[2], a[0] - b[2]), max(b[1] - a[3], a[1] - b[3])) for i in l for j in l if j > i
               for a, b in [(box(l[i]), box(l[j]))]), default=float('nan'))
    k5 = [r for r in l.values() if abs(r['th'] - 202.5) < 0.1]
    print('%s\t%.2f\t%d\t%d\t%d\t%s\t%.1f\t%s' % (d, next(iter(l.values()))['R'], n, hx, hy, ','.join(map(str, sorted(lead.get(d, ())))) or '-',
          sep, '%+.1f,%+.1f' % (k5[0]['dx'], k5[0]['dy']) if k5 else '-'))
    T[0] += n; T[1] += hx; T[2] += hy
cx = sum(max(sum(abs(a - x) <= 3 and abs(b - y) <= 3 for a, b in v) for x, y in v) for v in G.values())
cy = sum(max(sum(abs(b - y) <= 3 for a, b in v) for x, y in v) for v in G.values())
print('# TOTAL\t%d prints\t%d labels\ttoday xy %d (%.0f%%)\ttoday y %d (%.0f%%)\tceiling of a fixed per-angle rule: xy %d (%.0f%%), y %d (%.0f%%)'
      % (len(docs), T[0], T[1], 100 * T[1] / T[0], T[2], 100 * T[2] / T[0], cx, 100 * cx / T[0], cy, 100 * cy / T[0]))
