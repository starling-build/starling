#!/usr/bin/env python3
"""Lab p3q (windows, for the WordArt placement session): arch WordArt with spAutoFit/noAutofit/normAutofit at 18/100/200 pt, and the ThemeColorTransparency Happy textInflate with one property toggled per cell. usage: gen.py OUTDIR -> X.pptx + cells-X.tsv. Package builder copied from lab p3d."""
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



E = 12700
def wslide(name, warp, adj, w, h, text, sz, font='Calibri', fit='noAutofit', wrap='square', ins=None, anchor='t', anchorCtr=False,
           ln=None, fill=None, join='', lnspc=False):
    """One warped text box w x h pt, centred, thin red outline. ins=(l,t,r,b) pt or None (defaults). ln=(pt, hex, alpha%) or None; fill=(hex, alpha%) or None (black)."""
    bx, by = int(w * E), int(h * E)
    x, y = (CX - bx) // 2, (CY - by) // 2
    ia = ' lIns="%d" tIns="%d" rIns="%d" bIns="%d"' % tuple(int(v * E) for v in ins) if ins else ''
    def clr(h_, a):
        return '<a:srgbClr val="%s">%s</a:srgbClr>' % (h_, '<a:alpha val="%d"/>' % (a * 1000) if a < 100 else '')
    rp = ''
    if ln:
        rp += '<a:ln w="%d"><a:solidFill>%s</a:solidFill>%s</a:ln>' % (int(ln[0] * E), clr(ln[1], ln[2]), join)
    if fill:
        rp += '<a:solidFill>%s</a:solidFill>' % clr(*fill)
    rp += '<a:latin typeface="%s"/>' % font
    pp = '<a:pPr><a:lnSpc><a:spcPct val="100000"/></a:lnSpc></a:pPr>' if lnspc else ''
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>' % NSA
            + '<p:sp><p:nvSpPr><p:cNvPr id="2" name="%s"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>' % (name, x, y, bx, by)
            + '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="6350"><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></a:ln></p:spPr>'
            + '<p:txBody><a:bodyPr wrap="%s"%s anchor="%s"%s rtlCol="0"><a:prstTxWarp prst="%s"><a:avLst>%s</a:avLst></a:prstTxWarp><a:%s/></a:bodyPr><a:lstStyle/>' % (wrap, ia, anchor, ' anchorCtr="1"' if anchorCtr else '', warp, '<a:gd name="adj" fmla="val %d"/>' % adj if adj is not None else '', fit)
            + '<a:p>%s<a:r><a:rPr lang="en-US" sz="%d" b="0">%s</a:rPr><a:t xml:space="preserve">%s</a:t></a:r></a:p></p:txBody></p:sp>' % (pp, int(sz * 100), rp, text)
            + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
T = []
def add(nm, *a, **kw):
    T.append((nm, wslide(nm, *a, **kw)))
# Part 1: textArchUp, default adj, three autofit modes. 18 pt as the deck (135x71 box, 15 letters); 100 and 200 pt as lab p3x (340x170, WordArt, wrap none).
for fit in ('noAutofit', 'spAutoFit', 'normAutofit'):
    add('textArchUp %s 18pt box 135x71 FontEffectArcUp wrap square' % fit, 'textArchUp', 10800000, 135, 71, 'FontEffectArcUp', 18, fit=fit)
for sz in (100, 200):
    for fit in ('noAutofit', 'spAutoFit', 'normAutofit'):
        add('textArchUp %s %dpt box 340x170 WordArt Arial Black wrap none' % (fit, sz), 'textArchUp', 10800000, 340, 170, 'WordArt', sz, font='Arial Black', fit=fit, wrap='none', ins=(0, 0, 0, 0), anchor='ctr')
for sz in (100, 200):
    add('textArchUp noAutofit %dpt box 340x170 WordArt Arial Black wrap square' % sz, 'textArchUp', 10800000, 340, 170, 'WordArt', sz, font='Arial Black', fit='noAutofit', wrap='square', ins=(0, 0, 0, 0), anchor='ctr')
# Part 2: ThemeColorTransparency's top shape (oox-tdf139618): textInflate 20000, wrap none, 24 pt Arial Black "Happy ", 8.5 pt outline 25% alpha miter, fill 35% alpha, insets 10.94/7.54 pt, anchor ctr + anchorCtr, box 331.2x189.8. One property toggled per cell.
D = dict(font='Arial Black', wrap='none', ins=(10.94, 7.54, 10.94, 7.54), anchor='ctr', anchorCtr=True, ln=(8.5, '4F3434', 25), fill=('8FAADC', 35), join='<a:miter/>', lnspc=True)
def happy(nm, text='Happy ', warp='textInflate', adj=20000, **kw):
    d = dict(D); d.update(kw)
    add('TCT ' + nm, warp, adj, 331.2, 189.8, text, d.pop('sz', 24), **d)
happy('as the deck')
happy('no outline', ln=None)
happy('opaque outline and fill', ln=(8.5, '4F3434', 100), fill=('8FAADC', 100))
happy('no trailing space', text='Happy')
happy('round join', join='<a:round/>')
happy('anchorCtr off', anchorCtr=False)
happy('default insets', ins=None)
happy('textPlain 50000', warp='textPlain', adj=50000)
happy('textInflate adj 50000', adj=50000)
happy('96 pt', sz=96)
pkg(os.path.join(out, 'X.pptx'), [c[1] for c in T])
with open(os.path.join(out, 'cells-X.tsv'), 'w') as f:
    f.write(''.join('%d\t%s\n' % (i + 1, c[0]) for i, c in enumerate(T)))
print(len(T), 'cells')
