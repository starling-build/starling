#!/usr/bin/env python3
"""Hatch tile origin lab: python3 mklab.py OUT.xlsx. Twelve copies of chart-hatch-fill's chart (area dkDnDiag, one lgGrid
slice), each on its own cell with the frame moved by a stated offset: x 0,.5,1,2,3,4 pt (row 0) and y the same (row 8).
Print the entire workbook to PDF from Excel; each chart's pattern tile origin (the 6 pt images, `get_image_info`) minus
its frame's left/top gives the rule."""
import zipfile, sys, re
src = "test/corpus/xlsx/books/chart-chart-hatch-fill.xlsx"
zi = zipfile.ZipFile(src)
chart = zi.read("xl/charts/chart1.xml").decode()
steps = [0, .5, 1, 2, 3, 4]
anchors = []
for k, d in enumerate(steps):
    anchors.append((k * 2, 0, d, 0))           # col, row, dx pt, dy pt  (x series)
for k, d in enumerate(steps):
    anchors.append((k * 2, 9, 0, d))           # y series
E = 12700
def anchor(i, col, row, dx, dy):
    return (f'<xdr:oneCellAnchor><xdr:from><xdr:col>{col}</xdr:col><xdr:colOff>{int(dx*E)}</xdr:colOff><xdr:row>{row}</xdr:row><xdr:rowOff>{int(dy*E)}</xdr:rowOff></xdr:from>'
            f'<xdr:ext cx="{int(95*E)}" cy="{int(120*E)}"/><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="{i+2}" name="H{i}"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
            f'<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
            f'<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rId{i+1}"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:oneCellAnchor>')
drawing = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
           + "".join(anchor(i, *a) for i, a in enumerate(anchors)) + '</xdr:wsDr>')
rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        + "".join(f'<Relationship Id="rId{i+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart{i+1}.xml"/>' for i in range(len(anchors))) + '</Relationships>')
out = zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED)
for it in zi.infolist():
    n = it.filename
    d = zi.read(n)
    if n == "xl/drawings/drawing1.xml": d = drawing.encode()
    elif n == "xl/drawings/_rels/drawing1.xml.rels": d = rels.encode()
    elif n == "xl/charts/chart1.xml": continue
    elif n == "[Content_Types].xml":
        s = d.decode()
        s = re.sub(r'<Override PartName="/xl/charts/chart1.xml"[^>]*/>', "".join(f'<Override PartName="/xl/charts/chart{i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' for i in range(len(anchors))), s)
        d = s.encode()
    out.writestr(it, d)
for i in range(len(anchors)): out.writestr(f"xl/charts/chart{i+1}.xml", chart)
out.close()
