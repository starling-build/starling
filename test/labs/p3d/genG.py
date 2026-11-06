#!/usr/bin/env python3
"""Lab G (Windows, for amd-2): a shape with NO prstMaterial (PowerPoint's default). The donut of lab F (1440000x2160000 EMU, fill F8DCCB,
line F4B183, extrusionH 914400, camera orthographicFront) with no sp3d prstMaterial attribute, under twoPt and threePt (dir t), light rev 90 and 0,
camera lon 225 (the face turned away, as the highlight deck), 135 (the other way) and 0 (square on). 2 rigs x 2 revs x 3 lons = 12 cells, in cells-G.tsv order.
usage: genG.py GEN_BASE.py OUTDIR -> OUTDIR/G.pptx, OUTDIR/cells-G.tsv"""
import sys
base = open(sys.argv[1], encoding='utf8').read()
sys.argv = [sys.argv[0], sys.argv[2]]
exec(compile(base.split('out = sys.argv[1]')[0], 'gen_base', 'exec'))
import os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
CELLS = [(r, v, lon) for lon in (225, 135, 0) for r in ('threePt', 'twoPt') for v in (90, 0)]


def cell(rig, rev, lon):
    x = (12192000 - 1440000) // 2; y = (CY - 2160000) // 2
    body = ('<p:sp><p:nvSpPr><p:cNvPr id="2" name="donut"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="1440000" cy="2160000"/></a:xfrm>'
            '<a:prstGeom prst="donut"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="F8DCCB"/></a:solidFill><a:ln><a:solidFill><a:srgbClr val="F4B183"/></a:solidFill></a:ln>'
            '<a:scene3d><a:camera prst="orthographicFront"><a:rot lat="0" lon="%d" rev="0"/></a:camera><a:lightRig rig="%s" dir="t"><a:rot lat="0" lon="0" rev="%d"/></a:lightRig></a:scene3d>'
            '<a:sp3d extrusionH="914400"/></p:spPr></p:sp>' % (x, y, lon * 60000, rig, rev * 60000))
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>%s</p:spTree></p:cSld>'
            '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>' % (NSA, body))


cells = [('mat=none rig=%s rev=%d lon=%d' % c, cell(*c)) for c in CELLS]
pkg(os.path.join(out, 'G.pptx'), [c[1] for c in cells])
open(os.path.join(out, 'cells-G.tsv'), 'w').write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(cells)))
print(len(cells), 'cells')
