"""compare.py OURS_DIR [more dirs]: measure our renders (<doc>-orig.pdf, lab pie2's meas2.py) and compare every label with Word's
(load.py rows): within 3 pt in x and y of the fitz box centre, per lab family; misses listed with (ours - Word) in pt."""
import sys, os, subprocess, collections, re
from load import rows
M2 = '/tmp/claude-1000/-data-s-lenovo-2-starling/2f276615-7e16-4172-8b79-6ec68f60bc88/scratchpad/lab/piezone/test/lab/piezone/meas2.py'
PY = os.path.expanduser('~/venv-word/bin/python')
W = {(r['doc'], r['k']): r for r in rows()}
ours = {}
for d in sys.argv[1:]:
    out = subprocess.run([PY, M2, d], capture_output=True, text=True).stdout
    for ln in out.splitlines():
        p = ln.split('\t')
        if ln.startswith('#') or len(p) < 14 or p[2] == 'LEADER': continue
        ours[(p[0], int(p[2]))] = dict(dx=float(p[5]), dy=float(p[6]), R=float(p[12]), inside=p[14] != 'OUT')
fam = lambda d: re.sub(r'-.*', '', d) if not d.startswith('p1-') else 'p1-' + d.split('-')[1][:4]
hit = collections.Counter(); n = collections.Counter(); miss = []
for key, o in sorted(ours.items()):
    w = W.get(key)
    if not w or w['inside']: continue
    f = fam(key[0]); n[f] += 1
    ex, ey = o['dx'] - w['dx'], o['dy'] + 0.78 - w['dy']   # our fitz box is the hhea box; Word's fitz centre is 0.78 below its box centre
    if o['inside']: miss.append((key, 'INSIDE')); continue
    if abs(ex) <= 3 and abs(ey) <= 3: hit[f] += 1
    else: miss.append((key, round(w['th'], 1), round(ex, 1), round(ey, 1)))
tot = sum(hit.values()); N = sum(n.values())
print('within 3pt: %d/%d (%.0f%%)  ' % (tot, N, 100 * tot / max(1, N)) + ' '.join('%s %d/%d' % (k, hit[k], n[k]) for k in sorted(n)))
if '-v' in os.environ.get('CMP', ''): [print(m) for m in miss]
