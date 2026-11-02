#!/usr/bin/env python3
"""Lab D (Windows 01QbbApP, for amd-2): the light rig's a:rot. Cell = Lab A's slab (rect, warmMatte, fill C86432, extrusionH 274320, camera isometricOffAxis1Right),
vary only <a:lightRig rig dir><a:rot lat lon rev/></a:lightRig>. usage: genD.py GEN_BASE.py OUTDIR -> OUTDIR/D.pptx, OUTDIR/cells-D.tsv
Per rig (threePt harsh soft flood): lat {0,45,90,315} x lon {0,45,90,180,315} at rev 0 (dir t), then rev 90 and 180 at lat 0 lon 0, then dir=r lat 45 lon 45 rev 0. 23 cells per rig, 92 in all."""
import sys
base = open(sys.argv[1], encoding='utf8').read()
sys.argv = [sys.argv[0], sys.argv[2]]
exec(compile(base.split('out = sys.argv[1]')[0], 'gen_base', 'exec'))
import os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
TILT = 'isometricOffAxis1Right'; ROT = (315, 330, 0)
cells = []
for rig in ('threePt', 'harsh', 'soft', 'flood'):
    L = [(la, lo, 0, 't') for la in (0, 45, 90, 315) for lo in (0, 45, 90, 180, 315)] + [(0, 0, 90, 't'), (0, 0, 180, 't'), (45, 45, 0, 'r')]
    for la, lo, rv, d in L:
        nm = 'rig=%s lat=%d lon=%d rev=%d dir=%s' % (rig, la, lo, rv, d)
        cells.append((nm, slide(nm, 'rect', 'warmMatte', rig, d, ROT, cam=TILT, lrot=(la, lo, rv))))
pkg(os.path.join(out, 'D.pptx'), [c[1] for c in cells])
open(os.path.join(out, 'cells-D.tsv'), 'w').write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(cells)))
print(len(cells), 'cells')
