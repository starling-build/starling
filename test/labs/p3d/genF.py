#!/usr/bin/env python3
"""Lab F (Windows, for amd-2): the material highlight band. One slide per cell: a donut (as in oox-Scene3d_material_highlight: 1440000x2160000 EMU,
fill F8DCCB, line F4B183, extrusionH 914400, camera orthographicFront rot lon 225) under one prstMaterial and one rig. Rigs: twoPt rev 90 (the deck's),
twoPt rev 0, threePt rev 90. 15 materials x 3 rigs = 45 cells, in cells-F.tsv order.
usage: genF.py GEN_BASE.py OUTDIR -> OUTDIR/F.pptx, OUTDIR/cells-F.tsv"""
import sys
base = open(sys.argv[1], encoding='utf8').read()
sys.argv = [sys.argv[0], sys.argv[2]]
exec(compile(base.split('out = sys.argv[1]')[0], 'gen_base', 'exec'))
import os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
MATS = 'legacyMatte legacyPlastic legacyMetal matte plastic metal warmMatte translucentPowder powder dkEdge softEdge clear flat softmetal'.split()
RIGS = [('twoPt', 90), ('twoPt', 0), ('threePt', 90)]


def cell(mat, rig, rev):
    x = (12192000 - 1440000) // 2; y = (CY - 2160000) // 2
    body = ('<p:sp><p:nvSpPr><p:cNvPr id="2" name="donut"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="1440000" cy="2160000"/></a:xfrm>'
            '<a:prstGeom prst="donut"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="F8DCCB"/></a:solidFill><a:ln><a:solidFill><a:srgbClr val="F4B183"/></a:solidFill></a:ln>'
            '<a:scene3d><a:camera prst="orthographicFront"><a:rot lat="0" lon="13499976" rev="0"/></a:camera><a:lightRig rig="%s" dir="t"><a:rot lat="0" lon="0" rev="%d"/></a:lightRig></a:scene3d>'
            '<a:sp3d extrusionH="914400" prstMaterial="%s"/></p:spPr></p:sp>' % (x, y, rig, rev * 60000, mat))
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>%s</p:spTree></p:cSld>'
            '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>' % (NSA, body))


cells = [('mat=%s rig=%s rev=%d' % (m, r, v), cell(m, r, v)) for (r, v) in RIGS for m in MATS]
pkg(os.path.join(out, 'F.pptx'), [c[1] for c in cells])
open(os.path.join(out, 'cells-F.tsv'), 'w').write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(cells)))
print(len(cells), 'cells')
