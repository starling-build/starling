#!/usr/bin/env python3
"""Lab proj2 (for amd-opus): the 3-D box's proportions across chart kinds and data shapes. Same page set-up
and measuring as lab proj (gen.py, meas2.py): one chart a page, floor/back wall/side wall as 1pt black
outlines, axes deleted, no title/legend. Varied: chart kind (bar3D standard / clustered, surface3D, line3D,
area3D), the number of categories and series, rotX/rotY, perspective, rAngAx.
gen2.py OUTDIR -> OUTDIR/proj2.docx; page = index in combos() + 1."""
import sys, os, zipfile
import gen

def combos():
    out = []
    for nc, ns in ((3, 2), (4, 3), (6, 2), (2, 5), (5, 5), (8, 1)):
        for rx, ry in ((15, 20), (30, 45)):
            out.append(('bar3D', 'standard', nc, ns, rx, ry, 30, 0))
    for nc, ns in ((3, 2), (6, 2)):
        out.append(('bar3D', 'clustered', nc, ns, 15, 20, 30, 0))
        out.append(('bar3D', 'clustered', nc, ns, 15, 20, 30, 1))
    for nc, ns in ((4, 3), (3, 2), (6, 4)):
        for rx, ry, ps in ((20, 170, 0), (15, 20, 0), (30, 45, 0), (15, 20, 30)):
            out.append(('surface3D', None, nc, ns, rx, ry, ps, 0))
    for kind in ('line3D', 'area3D'):
        for rx, ry in ((15, 20), (30, 45)):
            out.append((kind, 'standard', 4, 3, rx, ry, 30, 0))
    return out

COL = ('4472C4', 'ED7D31', 'A5A5A5', 'FFC000', '5B9BD5', '70AD47', '264478', '9E480E')

def chart(kind, grouping, nc, ns, rx, ry, ps, ra):
    ser = ''
    for s in range(ns):
        val = ''.join('<c:pt idx="%d"><c:v>%d</c:v></c:pt>' % (i, 1 + (s * 3 + i * 2) % 6) for i in range(nc))
        cat = ''.join('<c:pt idx="%d"><c:v>C%d</c:v></c:pt>' % (i, i + 1) for i in range(nc))
        fill = '' if kind == 'surface3D' else '<c:spPr><a:solidFill><a:srgbClr val="%s"/></a:solidFill></c:spPr>' % COL[s % 8]
        extra = '<c:invertIfNegative val="0"/>' if kind == 'bar3D' else ''
        ser += ('<c:ser><c:idx val="%d"/><c:order val="%d"/><c:tx><c:v>S%d</c:v></c:tx>%s%s'
                '<c:cat><c:strLit><c:ptCount val="%d"/>%s</c:strLit></c:cat><c:val><c:numLit><c:formatCode>General</c:formatCode><c:ptCount val="%d"/>%s</c:numLit></c:val></c:ser>'
                % (s, s, s + 1, fill, extra, nc, cat, nc, val))
    v3 = '<c:view3D><c:rotX val="%d"/><c:rotY val="%d"/><c:depthPercent val="100"/><c:rAngAx val="%d"/><c:perspective val="%d"/></c:view3D>' % (rx, ry, ra, ps)
    ax = lambda tag, i, cross, extra: ('<c:%s><c:axId val="%d"/><c:scaling><c:orientation val="minMax"/>%s</c:scaling><c:delete val="1"/>'
                                       '<c:axPos val="b"/><c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="none"/>'
                                       '<c:crossAx val="%d"/></c:%s>' % (tag, i, extra, cross, tag))
    third = grouping != 'clustered'
    ids = '<c:axId val="1"/><c:axId val="2"/>' + ('<c:axId val="3"/>' if third else '')
    if kind == 'bar3D':
        body = ('<c:bar3DChart><c:barDir val="col"/><c:grouping val="%s"/><c:varyColors val="0"/>%s<c:gapWidth val="150"/><c:shape val="box"/>%s</c:bar3DChart>'
                % (grouping, ser, ids))
    elif kind == 'surface3D':
        body = '<c:surface3DChart><c:wireframe val="0"/>%s<c:bandFmts/>%s</c:surface3DChart>' % (ser, ids)
    elif kind == 'line3D':
        body = '<c:line3DChart><c:grouping val="standard"/><c:varyColors val="0"/>%s%s</c:line3DChart>' % (ser, ids)
    else:
        body = '<c:area3DChart><c:grouping val="standard"/><c:varyColors val="0"/>%s%s</c:area3DChart>' % (ser, ids)
    axes = ax('catAx', 1, 2, '') + ax('valAx', 2, 1, '<c:max val="6"/><c:min val="0"/>') + (ax('serAx', 3, 2, '') if third else '')
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace %s><c:date1904 val="0"/><c:roundedCorners val="0"/><c:chart>'
            '<c:autoTitleDeleted val="1"/>%s<c:floor><c:thickness val="0"/>%s</c:floor><c:sideWall><c:thickness val="0"/>%s</c:sideWall>'
            '<c:backWall><c:thickness val="0"/>%s</c:backWall><c:plotArea><c:layout/>%s%s%s</c:plotArea><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>'
            '<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr></c:chartSpace>'
            % (gen.CNS, v3, gen.LN, gen.LN, gen.LN, body, axes, gen.NOLN))

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    gen.combos = combos
    gen.chart = lambda *c: chart(*c)
    gen.pkg(os.path.join(out, "proj2.docx"))
    print(len(combos()), "pages")
