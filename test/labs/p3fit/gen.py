#!/usr/bin/env python3
"""Lab p3fit (amd-2 for windows): second samples for three single-deck fits of the 3-D shape painter.
usage: gen.py OUTDIR -> F.pptx (9 slides) + cells-F.tsv.  Package writer shared with p3u/gen.py.
 slides 1-3: how a rig lights a flat-filled solid whose fill is one of six colours (face = a*fill + b*white?),
             isometricRightUp under threePt, twoPt, and an orthographic tilt under threePt.
 slides 4-7: `a:sp3d z` (the solid stands this far toward the eye) under three cameras, five z values each.
 slides 8-9: legacyWireframe: edge colour, edge width, box growth, two cameras and two sizes."""
import sys, os, re
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'p3u', 'gen.py')).read()
exec(src[:src.index('\nout = sys.argv[1]')])

FILLS = ['C86432', 'A9D18E', '4472C4', '808080', 'F2F2F2', '203040']
COLS = [(0.10, 0.12), (0.40, 0.12), (0.70, 0.12)]


def cells(n, cols=3, size=1371600):
    out = []
    for i in range(n):
        r, c = divmod(i, cols)
        out.append((int(CX * (0.08 + 0.30 * c)), int(CY * (0.12 + 0.42 * r)), size, size))
    return out


def shape(i, name, box, prst, fill, camera, rig, d, ext, z=None, ln=None, mat=None):
    x, y, w, h = box
    sc = '<a:scene3d>%s<a:lightRig rig="%s" dir="%s"/></a:scene3d>' % (camera, rig, d)
    sp = '<a:sp3d%s extrusionH="%d"%s/>' % ((' z="%d"' % z) if z is not None else '', ext, (' prstMaterial="%s"' % mat) if mat else '')
    fl = '<a:solidFill><a:srgbClr val="%s"/></a:solidFill>' % fill
    lnx = ln if ln is not None else '<a:ln><a:noFill/></a:ln>'
    return ('<p:sp><p:nvSpPr><p:cNvPr id="%d" name="%s"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
            '<a:prstGeom prst="%s"><a:avLst/></a:prstGeom>%s%s%s%s</p:spPr></p:sp>') % (i + 2, name, x, y, w, h, prst, fl, lnx, sc, sp)


def sld(shapes):
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>' % NSA
            + ''.join(shapes) + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')


def cam(prst, rot=None):
    if rot:
        return '<a:camera prst="%s"><a:rot lat="%d" lon="%d" rev="%d"/></a:camera>' % ((prst,) + tuple(v * 60000 for v in rot))
    return '<a:camera prst="%s"/>' % prst


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
slides, rows = [], []


def add(desc, shapes):
    slides.append(sld(shapes)); rows.append('%d\t%s' % (len(slides), desc))


for rig, cm, tag in [('threePt', cam('isometricRightUp'), 'iso'), ('twoPt', cam('isometricRightUp'), 'iso'), ('threePt', cam('orthographicFront', (20, 330, 0)), 'tilt 20/330')]:
    bx = cells(6)
    add('fill colours C86432 A9D18E 4472C4 808080 F2F2F2 203040 (row-major), %s %s, extrusionH 36pt, rect 108pt, no line' % (tag, rig),
        [shape(i, 'cell-%d' % (i + 1), bx[i], 'rect', FILLS[i], cm, rig, 't', 457200) for i in range(6)])
ZS = [0, 114300, 228600, 457200, -228600]
for camname in ['legacyObliqueBottomRight', 'legacyObliqueTopLeft', 'legacyPerspectiveRight', 'isometricRightUp']:
    bx = cells(5)
    add('z = 0, 9, 18, 36, -18 pt (row-major), camera %s, threePt t, extrusionH 36pt, fill A9D18E, rect 108pt' % camname,
        [shape(i, 'cell-%d' % (i + 1), bx[i], 'rect', 'A9D18E', cam(camname), 'threePt', 't', 457200, z=ZS[i]) for i in range(5)])
LNS = [('red 1pt', '<a:ln w="12700"><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:ln>'),
       ('blue 2pt', '<a:ln w="25400"><a:solidFill><a:srgbClr val="0000FF"/></a:solidFill></a:ln>'),
       ('black 0.25pt', '<a:ln w="3175"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln>'),
       ('black 3pt', '<a:ln w="38100"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln>'),
       ('line with no width, black', '<a:ln><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln>'),
       ('no line', None)]
bx = cells(6)
add('legacyWireframe, camera obliqueTopLeft, edges: ' + '; '.join(n for n, _ in LNS) + ' (row-major), extrusionH 72pt, 108pt rect',
    [shape(i, 'cell-%d' % (i + 1), bx[i], 'rect', 'C86432', cam('obliqueTopLeft'), 'twoPt', 't', 914400, ln=LNS[i][1], mat='legacyWireframe') for i in range(6)])
bx = [(int(CX * 0.06), int(CY * 0.12), 2743200, 1828800), (int(CX * 0.50), int(CY * 0.12), 1371600, 2743200),
      (int(CX * 0.06), int(CY * 0.58), 2743200, 1371600), (int(CX * 0.50), int(CY * 0.58), 1828800, 1828800)]
cms = [cam('isometricRightUp'), cam('orthographicFront', (20, 330, 0)), cam('obliqueTopLeft'), cam('orthographicFront', (340, 20, 0))]
add('legacyWireframe, 1pt black line, four sizes/cameras: 216x144 iso; 108x216 tilt 20/330; 216x108 obliqueTopLeft; 144x144 tilt 340/20; extrusionH 72pt',
    [shape(i, 'cell-%d' % (i + 1), bx[i], 'rect', 'C86432', cms[i], 'twoPt', 't', 914400, ln=LNS[4][1].replace('<a:ln>', '<a:ln w="12700">'), mat='legacyWireframe') for i in range(4)])
pkg(os.path.join(out, 'F.pptx'), slides)
open(os.path.join(out, 'cells-F.tsv'), 'w').write('slide\tcells\n' + '\n'.join(rows) + '\n')
print(len(slides), 'slides ->', out)
