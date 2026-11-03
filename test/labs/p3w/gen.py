#!/usr/bin/env python3
"""Lab p3w (windows, for amd-4/starling-d1): the deck word with its warp, camera rotation off and on. usage: gen.py OUTDIR -> W.pptx + cells-W.tsv. Package builder copied from lab p3d."""
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



def tslide(name, rot=None, cam=None, ext=342900, bevT=None, bevB=None, rig='morning', d='t', lrot=None,
           text='HO', sz=20000, box=(4572000, 1828800), at=None, contour=False, mat=None, face='C86432', side='808080',
           warp='textPlain', adj=None):
    """One text box, Arial Black, laid out by WordArt (prstTxWarp, textPlain = stretched to the box)."""
    bx, by = box
    x, y = at if at else ((CX - bx) // 2, (CY - by) // 2)
    if cam:
        sc = '<a:scene3d><a:camera prst="%s"/>' % cam
    else:
        sc = '<a:scene3d><a:camera prst="orthographicFront"><a:rot lat="%d" lon="%d" rev="%d"/></a:camera>' % tuple(v * 60000 for v in rot)
    if lrot:
        sc += '<a:lightRig rig="%s" dir="%s"><a:rot lat="%d" lon="%d" rev="%d"/></a:lightRig>' % ((rig, d) + tuple(v * 60000 for v in lrot))
    else:
        sc += '<a:lightRig rig="%s" dir="%s"/>' % (rig, d)
    sc += '</a:scene3d>'
    sp = '<a:sp3d extrusionH="%d"' % ext + (' contourW="12700"' if contour else '') + (' prstMaterial="%s"' % mat if mat else '') + '>'
    if bevT:
        sp += '<a:bevelT w="%d" h="%d" prst="%s"/>' % bevT
    if bevB:
        sp += '<a:bevelB %sh="%d"/>' % (('w="%d" ' % bevB[0]) if bevB[0] else '', bevB[1])
    sp += '<a:extrusionClr><a:srgbClr val="%s"/></a:extrusionClr>' % side
    if contour:
        sp += '<a:contourClr><a:srgbClr val="009876"/></a:contourClr>'
    sp += '</a:sp3d>'
    wp = '<a:prstTxWarp prst="%s"><a:avLst>%s</a:avLst></a:prstTxWarp>' % (warp, ('<a:gd name="adj" fmla="val %d"/>' % adj) if adj else '')
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>' % NSA
            + '<p:sp><p:nvSpPr><p:cNvPr id="2" name="%s"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>' % (name, x, y, bx, by)
            + '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
            + '<p:txBody><a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr" rtlCol="0">%s%s%s</a:bodyPr><a:lstStyle/>' % (wp, sc, sp)
            + '<a:p><a:pPr algn="ctr"/><a:r><a:rPr lang="en-US" sz="%d"><a:solidFill><a:srgbClr val="%s"/></a:solidFill><a:latin typeface="Arial Black"/></a:rPr><a:t>%s</a:t></a:r></a:p></p:txBody></p:sp>' % (sz, face, text)
            + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
T = []
def add(nm, **kw):
    T.append((nm, tslide(nm, **kw)))

D = dict(text='WordArt', box=(4320000, 2160000), face='FFFF00', side='990000')
for wn, warp, adj in (('plain', 'textPlain', None), ('curveDown 56338', 'textCurveDown', 56338), ('arch up', 'textArchUp', None)):
    add('%s, rotation off, no depth, no bevel' % wn, rot=(0, 0, 0), ext=0, warp=warp, adj=adj, **D)
    add('%s, rotation off, depth 27' % wn, rot=(0, 0, 0), ext=342900, warp=warp, adj=adj, **D)
    add('%s, rot 20,330, no depth' % wn, rot=(20, 330, 0), ext=0, warp=warp, adj=adj, **D)
    add('%s, rot 20,330, depth 27' % wn, rot=(20, 330, 0), ext=342900, warp=warp, adj=adj, **D)
    add('%s, rot 0,330 only (turn about the vertical), depth 27' % wn, rot=(0, 330, 0), ext=342900, warp=warp, adj=adj, **D)
    add('%s, rot 20,0 only (tip), depth 27' % wn, rot=(20, 0, 0), ext=342900, warp=warp, adj=adj, **D)

pkg(os.path.join(out, 'W.pptx'), [c[1] for c in T])
with open(os.path.join(out, 'cells-W.tsv'), 'w') as f:
    f.write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(T)))
print(len(T), 'cells')
