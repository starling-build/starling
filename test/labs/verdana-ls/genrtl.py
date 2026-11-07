#!/usr/bin/env python3
"""Lab verdana-rtl (right-to-left lines holding more than one face): Hebrew and Arabic 24 pt lines, a Latin run in another face inside them, end mark in another face, at 90/100/110%; three boxes per cell (centred, top, bottom)."""
import sys, os, zipfile
NSA = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
       'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
       'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"')
H = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
CX, CY = 12192000, 6858000
BOX = 1371600
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'


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





A, T, V, C = 'Arial', 'Times New Roman', 'Verdana', 'Calibri'
BW, BH = 3200400, 2743200 // 2
HEB, ARA = 'שלום עולם', 'مرحبا بالعالم'
XS = [365760, 4495800, 8625840]
YS = [182880, 3566160]
# cell = (script, parts, mark, pct); parts = [(text, face, kind)], kind 'cs' (complex-script run) or 'lat' (Latin run);
# mark = (face, lang kind): 'lat' = en-US latin face, 'cs' = he/ar cs face
def cells():
    out = []
    for sc, txt in (('he-IL', HEB), ('ar-SA', ARA)):
        out += [
            (sc, [(txt, A, 'cs')], (A, 'lat'), 100),
            (sc, [(txt, A, 'cs')], (C, 'lat'), 100),
            (sc, [(txt, A, 'cs')], (C, 'cs'), 100),
            (sc, [(txt, A, 'cs'), (' Hamburg', V, 'lat')], (A, 'lat'), 100),
            (sc, [(txt, A, 'cs'), (' Hamburg', V, 'lat')], (C, 'lat'), 100),
            (sc, [(txt, T, 'cs')], (A, 'lat'), 100),
        ]
        for pct in (90, 110):
            out += [(sc, [(txt, A, 'cs')], (C, 'lat'), pct),
                    (sc, [(txt, A, 'cs'), (' Hamburg', V, 'lat')], (C, 'lat'), pct)]
    return out
CELLS = cells()


def rpr(tag, lang, face, kind):
    f = ('<a:cs typeface="%s"/>' if kind == 'cs' else '<a:latin typeface="%s"/>') % face
    return '<a:%s lang="%s" sz="2400"><a:solidFill><a:srgbClr val="000000"/></a:solidFill>%s</a:%s>' % (tag, lang, f, tag)


def box(i, name, x, y, anchor, cell):
    sc, parts, (mf, mk), pct = cell
    rs = ''.join('<a:r>%s<a:t>%s</a:t></a:r>' % (rpr('rPr', sc if k == 'cs' else 'en-US', f, k), t) for t, f, k in parts)
    ps = '<a:p><a:pPr algn="r" rtl="1"><a:lnSpc><a:spcPct val="%d"/></a:lnSpc></a:pPr>%s%s</a:p>' % (pct * 1000, rs, rpr('endParaRPr', 'en-US' if mk == 'lat' else sc, mf, mk))
    return ('<p:sp><p:nvSpPr><p:cNvPr id="%d" name="%s"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm>' % (i, name, x, y, BW, BH)
            + '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="6350"><a:solidFill><a:srgbClr val="808080"/></a:solidFill></a:ln></p:spPr>'
            + '<p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="%s" rtlCol="0"><a:noAutofit/></a:bodyPr><a:lstStyle/>%s</p:txBody></p:sp>' % (anchor, ps))


def slide(k):
    sps = ''
    for j in range(2):
        c = 2 * k + j
        if c >= len(CELLS):
            continue
        for col, a in enumerate(('ctr', 't', 'b')):
            sps += box(2 + 3 * j + col, 'c%d %s' % (c + 1, a), XS[col], YS[j], a, CELLS[c])
    return (H + '<p:sld %s><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>' % NSA
            + sps + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
N = (len(CELLS) + 1) // 2
pkg(os.path.join(out, 'RTL.pptx'), [slide(k) for k in range(N)])
with open(os.path.join(out, 'cells-RTL.tsv'), 'w') as f:
    f.write('cell\tslide\trow(0 top,1 bottom)\tscript\truns (face)\tend mark (face, lang)\tspacing %\n')
    for i, (sc, w, mk, p) in enumerate(CELLS):
        f.write('%d\t%d\t%d\t%s\t%s\t%s\t%d\n' % (i + 1, i // 2 + 1, i % 2, sc, ' | '.join('%s:%s' % (k, fc) for t, fc, k in w), '%s,%s' % mk, p))
print(len(CELLS), 'cells', N, 'slides')
