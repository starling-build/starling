#!/usr/bin/env python3
"""Lab p3pv (amd-2 for windows): where a 3-D WordArt word pivots as its depth grows.
usage: gen.py OUTDIR -> P.pptx + cells-P.tsv.
 slide 1: the word HIH (Arial bold 66 pt, no shape fill) under camera lat 20 / lon 330, extrusionH 0, 9, 18, 36, 72 pt (row-major).
 slide 2: the same word at extrusionH 36 under six cameras (lat/lon): 20/330, 340/20, 30/300, 0/330, 20/0, 0/30.
 slide 3: a plain 108x72 pt rectangle (no text) under lat 20 / lon 330, extrusionH 0, 9, 18, 36, 72 (control: the shape pivot).
 slide 4: the word with a one-point line contour and extrusionH 0, 18, 36, 72 under lat 20 / lon 330 (does the contour move it?)."""
import sys, os
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'p3u', 'gen.py')).read()
exec(src[:src.index('\nout = sys.argv[1]')])

def cell(n, i, cols=3):
    r, c = divmod(i, cols)
    return (int(CX * (0.06 + 0.31 * c)), int(CY * (0.10 + 0.45 * r)), 2743200, 1371600)

def cam(lat, lon):
    return '<a:camera prst="orthographicFront"><a:rot lat="%d" lon="%d" rev="0"/></a:camera>' % (lat * 60000, lon * 60000)

def word(i, box, lat, lon, ext, contour=False, warp='textPlain', bevel=None):
    x, y, w, h = box
    ln = '<a:ln w="12700"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln>' if contour else '<a:ln><a:noFill/></a:ln>'
    sp = '<a:sp3d extrusionH="%d"%s>%s<a:extrusionClr><a:srgbClr val="C00000"/></a:extrusionClr></a:sp3d>' % (ext, ' contourW="12700"' if contour else '', ('<a:bevelT w="%d" h="%d" prst="softRound"/>' % bevel) if bevel else '')
    return ('<p:sp><p:nvSpPr><p:cNvPr id="%d" name="cell-%d"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/>%s</p:spPr>'
            '<p:txBody><a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr"><a:prstTxWarp prst="%s"><a:avLst/></a:prstTxWarp><a:noAutofit/><a:scene3d>%s<a:lightRig rig="threePt" dir="t"/></a:scene3d>%s</a:bodyPr><a:lstStyle/><a:p><a:pPr algn="ctr"/><a:r><a:rPr lang="en-US" sz="6600" b="1"><a:solidFill><a:srgbClr val="4472C4"/></a:solidFill><a:latin typeface="Arial"/></a:rPr><a:t>HIH</a:t></a:r></a:p></p:txBody></p:sp>') % (i + 2, i + 1, x, y, w, h, ln, warp, cam(lat, lon), sp)

def rect(i, box, lat, lon, ext):
    x, y, w, h = box
    return ('<p:sp><p:nvSpPr><p:cNvPr id="%d" name="cell-%d"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="4472C4"/></a:solidFill><a:ln><a:noFill/></a:ln><a:scene3d>%s<a:lightRig rig="threePt" dir="t"/></a:scene3d>'
            '<a:sp3d extrusionH="%d"><a:extrusionClr><a:srgbClr val="C00000"/></a:extrusionClr></a:sp3d></p:spPr></p:sp>') % (i + 2, i + 1, x, y, 1371600, 914400, cam(lat, lon), ext)

def sld(shapes):
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>' % NSA
            + ''.join(shapes) + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
E5 = [0, 114300, 228600, 457200, 914400]
CAMS = [(20, 330), (340, 20), (30, 300), (0, 330), (20, 0), (0, 30)]
slides = [
    sld([word(i, cell(5, i), 20, 330, E5[i]) for i in range(5)]),
    sld([word(i, cell(6, i), CAMS[i][0], CAMS[i][1], 457200) for i in range(6)]),
    sld([rect(i, cell(5, i), 20, 330, E5[i]) for i in range(5)]),
    sld([word(i, cell(4, i), 20, 330, [0, 228600, 457200, 914400][i], True) for i in range(4)]),
    sld([word(i, cell(5, i), 20, 330, E5[i], warp='textCurveDown') for i in range(5)]),
    sld([word(i, cell(5, i), 20, 330, E5[i], warp='textCurveDown', bevel=(114300, 38100)) for i in range(5)]),
    sld([word(i, cell(6, i), CAMS[i][0], CAMS[i][1], 457200, warp='textCurveDown') for i in range(6)]),
]
rows = ['1\tword HIH 66pt, lat 20 lon 330, extrusionH 0 9 18 36 72', '2\tword at extrusionH 36, cameras 20/330 340/20 30/300 0/330 20/0 0/30',
        '3\tplain 108x72 rect, lat 20 lon 330, extrusionH 0 9 18 36 72', '4\tword with 1pt contour, extrusionH 0 18 36 72, lat 20 lon 330',
        '5\twarped (textCurveDown) word, lat 20 lon 330, extrusionH 0 9 18 36 72', '6\tsame with bevelT softRound 9x3 pt', '7\twarped word at extrusionH 36, six cameras as slide 2']
pkg(os.path.join(out, 'P.pptx'), slides)
open(os.path.join(out, 'cells-P.tsv'), 'w').write('slide\tcells\n' + '\n'.join(rows) + '\n')
print(len(slides), 'slides ->', out)
