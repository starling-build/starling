#!/usr/bin/env python3
"""Lab p3d (Windows 01QbbApP, for amd-4): PowerPoint 3-D model. usage: gen.py OUTDIR -> A.pptx B.pptx C.pptx + cells-X.tsv"""
import sys, os, zipfile
NSA = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
       'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
       'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"')
H = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
CX, CY = 12192000, 6858000
BOX = 1371600
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'


def slide(name, prst, mat, rig, d, rot, ext=274320, bevT=None, bevB=None, cam=None, lrot=None):
    x = (CX - BOX) // 2
    y = (CY - BOX) // 2
    if cam:
        sc = '<a:scene3d><a:camera prst="%s"/>' % cam
    else:
        sc = '<a:scene3d><a:camera prst="orthographicFront"><a:rot lat="%d" lon="%d" rev="%d"/></a:camera>' % rot
    if rig:
        if lrot:
            sc += '<a:lightRig rig="%s" dir="%s"><a:rot lat="%d" lon="%d" rev="%d"/></a:lightRig>' % ((rig, d) + tuple(v * 60000 for v in lrot))
        else:
            sc += '<a:lightRig rig="%s" dir="%s"/>' % (rig, d)
    sc += '</a:scene3d>'
    sp = '<a:sp3d extrusionH="%d"' % ext + (' prstMaterial="%s"' % mat if mat else '') + '>'
    if bevT:
        sp += '<a:bevelT w="%d" h="%d" prst="%s"/>' % bevT
    if bevB:
        sp += '<a:bevelB w="%d" h="%d" prst="%s"/>' % bevB
    sp += '</a:sp3d>'
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>' % NSA
            + '<p:sp><p:nvSpPr><p:cNvPr id="2" name="%s"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>' % (name, x, y, BOX, BOX)
            + '<a:prstGeom prst="%s"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="C86432"/></a:solidFill><a:ln><a:noFill/></a:ln>%s%s</p:spPr></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>' % (prst, sc, sp))


def rels(items):
    return (H + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + ''.join('<Relationship Id="%s" Type="%s/%s" Target="%s"/>' % i for i in items) + '</Relationships>')


def cl(n, v):
    return '<a:%s><a:srgbClr val="%s"/></a:%s>' % (n, v, n)


def pkg(path, slides):
    n = len(slides)
    ct = (H + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
          '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
          '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
          '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
          + ''.join('<Override PartName="/ppt/slides/slide%d.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>' % (i + 1) for i in range(n)) + '</Types>')
    pres = (H + '<p:presentation %s><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>' % NSA
            + ''.join('<p:sldId id="%d" r:id="rId%d"/>' % (256 + i, i + 2) for i in range(n))
            + '</p:sldIdLst><p:sldSz cx="%d" cy="%d"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>' % (CX, CY))
    master = (H + '<p:sldMaster %s><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>'
              '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
              '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>' % NSA)
    layout = (H + '<p:sldLayout %s type="blank"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld></p:sldLayout>' % NSA)
    sf = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    ln = lambda w: '<a:ln w="%d">%s</a:ln>' % (w, sf)
    ef = '<a:effectStyle><a:effectLst/></a:effectStyle>'
    theme = (H + '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="T"><a:themeElements><a:clrScheme name="c">'
             + cl('dk1', '000000') + cl('lt1', 'FFFFFF') + cl('dk2', '44546A') + cl('lt2', 'E7E6E6')
             + ''.join(cl('accent%d' % i, '4472C4') for i in range(1, 7)) + cl('hlink', '0563C1') + cl('folHlink', '954F72')
             + '</a:clrScheme><a:fontScheme name="f"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
             '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="m">'
             '<a:fillStyleLst>' + sf * 3 + '</a:fillStyleLst><a:lnStyleLst>' + ln(6350) + ln(12700) + ln(19050) + '</a:lnStyleLst>'
             '<a:effectStyleLst>' + ef * 3 + '</a:effectStyleLst><a:bgFillStyleLst>' + sf * 3 + '</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', ct)
        z.writestr('_rels/.rels', rels([('rId1', R, 'officeDocument', 'ppt/presentation.xml')]))
        z.writestr('ppt/presentation.xml', pres)
        z.writestr('ppt/_rels/presentation.xml.rels', rels([('rId1', R, 'slideMaster', 'slideMasters/slideMaster1.xml')] + [('rId%d' % (i + 2), R, 'slide', 'slides/slide%d.xml' % (i + 1)) for i in range(n)]))
        z.writestr('ppt/slideMasters/slideMaster1.xml', master)
        z.writestr('ppt/slideMasters/_rels/slideMaster1.xml.rels', rels([('rId1', R, 'slideLayout', '../slideLayouts/slideLayout1.xml'), ('rId2', R, 'theme', '../theme/theme1.xml')]))
        z.writestr('ppt/slideLayouts/slideLayout1.xml', layout)
        z.writestr('ppt/slideLayouts/_rels/slideLayout1.xml.rels', rels([('rId1', R, 'slideMaster', '../slideMasters/slideMaster1.xml')]))
        z.writestr('ppt/theme/theme1.xml', theme)
        for i, s in enumerate(slides):
            z.writestr('ppt/slides/slide%d.xml' % (i + 1), s)
            z.writestr('ppt/slides/_rels/slide%d.xml.rels' % (i + 1), rels([('rId1', R, 'slideLayout', '../slideLayouts/slideLayout1.xml')]))


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
ROT = (315, 330, 0)


def emit(tag, cells):
    pkg(os.path.join(out, tag + '.pptx'), [c[1] for c in cells])
    with open(os.path.join(out, 'cells-%s.tsv' % tag), 'w') as f:
        f.write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(cells)))


TILT = 'isometricOffAxis1Right'
A = []
for rig in 'threePt balanced soft harsh flood contrasting morning sunrise sunset chilly freezing flat twoPt glow brightRoom'.split():
    for d in 'trbl':
        nm = 'rig=%s dir=%s' % (rig, d)
        A.append((nm, slide(nm, 'rect', 'warmMatte', rig, d, ROT, cam=TILT)))
for r in [(0, 0, 0), (0, 90, 0), (0, 180, 0), (315, 330, 0), (45, 0, 0), (0, 0, 90)]:
    nm = 'rig=threePt dir=t lightrot=%d,%d,%d' % r
    A.append((nm, slide(nm, 'rect', 'warmMatte', 'threePt', 't', ROT, cam=TILT, lrot=r)))
for rig in ('threePt', 'harsh', 'soft', 'flood'):
    for d in 'tr':
        nm = 'rig=%s dir=%s cam=perspectiveRelaxed' % (rig, d)
        A.append((nm, slide(nm, 'rect', 'warmMatte', rig, d, ROT, cam='perspectiveRelaxed')))
emit('A', A)

B = []
for m in 'legacyMatte legacyPlastic legacyMetal legacyWireframe matte plastic metal warmMatte translucentPowder powder dkEdge softEdge clear flat softmetal'.split() + [None]:
    for sh in ('rect', 'ellipse'):
        nm = 'mat=%s %s' % (m or 'default(omitted)', sh)
        B.append((nm, slide(nm, sh, m, 'threePt', 't', ROT, cam=TILT)))
for m in ('matte', 'plastic', 'metal'):
    nm = 'mat=%s ellipse rig=harsh dir=t' % m
    B.append((nm, slide(nm, 'ellipse', m, 'harsh', 't', ROT, cam=TILT)))
emit('B', B)

C = []
for b in 'circle relaxedInset cross coolSlant angle softRound convex slope divot riblet hardEdge artDeco'.split():
    nm = 'bevelT=%s 0.15' % b
    C.append((nm, slide(nm, 'rect', 'matte', 'threePt', 't', ROT, ext=91440, bevT=(137160, 137160, b))))
for w, h in ((45720, 45720), (137160, 137160), (274320, 274320), (274320, 91440)):
    nm = 'bevelT=circle w=%d h=%d' % (w, h)
    C.append((nm, slide(nm, 'rect', 'matte', 'threePt', 't', ROT, ext=91440, bevT=(w, h, 'circle'))))
C.append(('bevelB=circle 0.15', slide('bevelB=circle 0.15', 'rect', 'matte', 'threePt', 't', ROT, ext=91440, bevB=(137160, 137160, 'circle'))))
C.append(('bevelT=circle ext=0', slide('bevelT=circle ext=0', 'rect', 'matte', 'threePt', 't', ROT, ext=0, bevT=(137160, 137160, 'circle'))))
emit('C', C)
