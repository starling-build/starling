#!/usr/bin/env python3
"""Lab E (Windows, for amd-2): the LEGACY cameras' wall shading. Each cell is one slide with two shapes side by side, an ellipse (every wall
normal in one print) and a rect, both C86432, no outline, extrusionH 457200 (36pt, deep so the walls show), default material, the same camera
and rig. Cells: 18 legacy cameras (9 legacyOblique*, 9 legacyPerspective*: TopLeft Top TopRight Left Front Right BottomLeft Bottom BottomRight)
under threePt; then ObliqueTopRight and PerspectiveTopRight under twoPt and harsh (4); then ObliqueBottomRight with and without
extrusionClr 89C064 (2) and with and without sp3d z=228600 (2, camera rot lat 0 lon 10 rev 20 as oox-Scene3d_legacyObliqueBottomRight).
usage: genE.py GEN_BASE.py OUTDIR -> OUTDIR/E.pptx, OUTDIR/cells-E.tsv"""
import sys
base = open(sys.argv[1], encoding='utf8').read()
sys.argv = [sys.argv[0], sys.argv[2]]
exec(compile(base.split('out = sys.argv[1]')[0], 'gen_base', 'exec'))
import os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
SZ = 1371600


def shape(i, x, y, prst, cam, rig, ext, camrot, extclr, z):
    c = '<a:camera prst="%s">%s</a:camera>' % (cam, ('<a:rot lat="%d" lon="%d" rev="%d"/>' % tuple(v * 60000 for v in camrot)) if camrot else '')
    sp3 = '<a:sp3d%s extrusionH="%d">%s</a:sp3d>' % ((' z="%d"' % z) if z else '', ext, ('<a:extrusionClr><a:srgbClr val="%s"/></a:extrusionClr>' % extclr) if extclr else '')
    return ('<p:sp><p:nvSpPr><p:cNvPr id="%d" name="%s"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
            '<a:prstGeom prst="%s"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="C86432"/></a:solidFill><a:ln><a:noFill/></a:ln>'
            '<a:scene3d>%s<a:lightRig rig="%s" dir="t"/></a:scene3d>%s</p:spPr></p:sp>' % (i, prst, x, y, SZ, SZ, prst, c, rig, sp3))


def cell(cam, rig, camrot=None, extclr=None, z=0):
    y = (CY - SZ) // 2
    body = shape(2, 2400000, y, 'ellipse', cam, rig, 457200, camrot, extclr, z) + shape(3, 6400000, y, 'rect', cam, rig, 457200, camrot, extclr, z)
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>%s</p:spTree></p:cSld>'
            '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>' % (NSA, body))


POS = 'TopLeft Top TopRight Left Front Right BottomLeft Bottom BottomRight'.split()
cells = []
for kind in ('legacyOblique', 'legacyPerspective'):
    for p in POS:
        cells.append(('cam=%s%s rig=threePt' % (kind, p), cell(kind + p, 'threePt')))
for rig in ('twoPt', 'harsh'):
    for kind in ('legacyOblique', 'legacyPerspective'):
        cells.append(('cam=%sTopRight rig=%s' % (kind, rig), cell(kind + 'TopRight', rig)))
for extclr in (None, '89C064'):
    cells.append(('cam=legacyObliqueBottomRight rig=threePt rot=0,10,20 extrusionClr=%s' % (extclr or 'none'), cell('legacyObliqueBottomRight', 'threePt', (0, 10, 20), extclr)))
for z in (0, 228600):
    cells.append(('cam=legacyObliqueBottomRight rig=threePt rot=0,10,20 z=%d' % z, cell('legacyObliqueBottomRight', 'threePt', (0, 10, 20), None, z)))
pkg(os.path.join(out, 'E.pptx'), [c[1] for c in cells])
open(os.path.join(out, 'cells-E.tsv'), 'w').write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(cells)))
print(len(cells), 'cells')
