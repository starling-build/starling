#!/usr/bin/env python3
"""Lab G2 (Windows, for amd-2): lab G again, but with the p:style (lnRef 2 accent1 shade, fillRef 1, effectRef 0) and optionally a text body that real shapes carry; no prstMaterial except two explicit warmMatte cells. The donut of lab F (1440000x2160000 EMU, fill F8DCCB,
line F4B183, extrusionH 914400, camera orthographicFront) with no sp3d prstMaterial attribute, under twoPt and threePt (dir t), light rev 90 and 0,
camera lon 225 only. Variants: style / style+text body, x 2 rigs x 2 revs = 8 cells, then explicit warmMatte with style, twoPt and threePt rev 90 = 2 cells. cells-G2.tsv order.
usage: genG2.py GEN_BASE.py OUTDIR -> OUTDIR/G2.pptx, OUTDIR/cells-G2.tsv"""
import sys
base = open(sys.argv[1], encoding='utf8').read()
sys.argv = [sys.argv[0], sys.argv[2]]
exec(compile(base.split('out = sys.argv[1]')[0], 'gen_base', 'exec'))
import os
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
CELLS = [(v, r, rev, '') for v in ('style', 'styletx') for r in ('threePt', 'twoPt') for rev in (90, 0)] + [('style', r, 90, 'warmMatte') for r in ('threePt', 'twoPt')]
STYLE = ('<p:style><a:lnRef idx="2"><a:schemeClr val="accent1"><a:shade val="15000"/></a:schemeClr></a:lnRef><a:fillRef idx="1"><a:schemeClr val="accent1"/></a:fillRef>'
         '<a:effectRef idx="0"><a:schemeClr val="accent1"/></a:effectRef><a:fontRef idx="minor"><a:schemeClr val="lt1"/></a:fontRef></p:style>')
TX = '<p:txBody><a:bodyPr rtlCol="0" anchor="ctr"/><a:lstStyle/><a:p><a:pPr algn="ctr"/><a:endParaRPr lang="en-US"/></a:p></p:txBody>'


def cell(var, rig, rev, mat):
    x = (12192000 - 1440000) // 2; y = (CY - 2160000) // 2
    body = ('<p:sp><p:nvSpPr><p:cNvPr id="2" name="donut"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="1440000" cy="2160000"/></a:xfrm>'
            '<a:prstGeom prst="donut"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="F8DCCB"/></a:solidFill><a:ln><a:solidFill><a:srgbClr val="F4B183"/></a:solidFill></a:ln>'
            '<a:scene3d><a:camera prst="orthographicFront"><a:rot lat="0" lon="13500000" rev="0"/></a:camera><a:lightRig rig="%s" dir="t"><a:rot lat="0" lon="0" rev="%d"/></a:lightRig></a:scene3d>'
            '<a:sp3d extrusionH="914400"%s/></p:spPr>%s%s</p:sp>' % (x, y, rig, rev * 60000, (' prstMaterial="%s"' % mat) if mat else '', STYLE, TX if var == 'styletx' else ''))
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>%s</p:spTree></p:cSld>'
            '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>' % (NSA, body))


cells = [('var=%s rig=%s rev=%d mat=%s' % (c[0], c[1], c[2], c[3] or 'none'), cell(*c)) for c in CELLS]
pkg(os.path.join(out, 'G2.pptx'), [c[1] for c in cells])
open(os.path.join(out, 'cells-G2.tsv'), 'w').write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(cells)))
print(len(cells), 'cells')
