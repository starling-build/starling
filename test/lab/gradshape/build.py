#!/usr/bin/env python3
"""Lab gradshape (for PowerPoint on Windows, from lenovo-5): how does PowerPoint draw path="shape" on a shape that is not a
rectangle, against path="rect" and path="circle" on the same shape, with fillToRect at the centre and at a corner?
usage: build.py SRC.pptx OUT.pptx  (SRC = test/corpus/pptx/decks/lo-tdf114848.pptx; its slide 4 is replaced)
One slide, 24 shapes 150x60pt (ellipse, star5, rightArrow, heart; each x shape|rect|circle x centre|bottom-right corner), red -> yellow -> blue (pos 0/50/100, plain srgb), each labelled in its own text
(white on black label under it): path (circle|rect), fillToRect l t r b, tileRect. Print to PDF."""
import sys, zipfile, itertools
src, out = sys.argv[1], sys.argv[2]
FT = [('c', (50, 50, 50, 50)), ('br', (100, 100, 0, 0))]
GEOS = ['ellipse', 'star5', 'rightArrow', 'heart']
# fillToRect (l,t,r,b) in percent
shapes = []
n = 2
E = 12700
def sp(i, x, y, geo, path, ft, tile, label):
    l, t, r, b = ft
    tr = f'<a:tileRect' + ''.join(f' {k}="{int(v*1000)}"' for k, v in zip('ltrb', tile) if v) + '/>' if tile else ''
    grad = ('<a:gradFill flip="none" rotWithShape="1"><a:gsLst><a:gs pos="0"><a:srgbClr val="FF0000"/></a:gs><a:gs pos="50000"><a:srgbClr val="FFFF00"/></a:gs><a:gs pos="100000"><a:srgbClr val="0000FF"/></a:gs></a:gsLst>'
            f'<a:path path="{path}"><a:fillToRect' + ''.join(f' {k}="{v*1000}"' for k, v in zip('ltrb', (l, t, r, b)) if v) + f'/></a:path>{tr}</a:gradFill>')
    box = f'<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="g{i}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x*E}" y="{y*E}"/><a:ext cx="{150*E}" cy="{60*E}"/></a:xfrm><a:prstGeom prst="{geo}"><a:avLst/></a:prstGeom>{grad}<a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>'
    cap = f'<p:sp><p:nvSpPr><p:cNvPr id="{i+500}" name="c{i}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x*E}" y="{(y+60)*E}"/><a:ext cx="{150*E}" cy="{14*E}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr lIns="0" tIns="0" rIns="0" bIns="0"/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="800"/><a:t>{label}</a:t></a:r></a:p></p:txBody></p:sp>'
    return box + cap
i = 10
rows = list(itertools.product(GEOS, ('shape', 'rect', 'circle'), FT))
for k, (geo, path, (fn, ft)) in enumerate(rows):
    col, row = k % 4, k // 4
    shapes.append(sp(i, 20 + col * 170, 10 + row * 80, geo, path, ft, None, f'{geo} {path} ft={fn}{ft}')); i += 1
slide = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>' + ''.join(shapes) + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')
zin = zipfile.ZipFile(src)
files = [(it, zin.read(it.filename)) for it in zin.infolist() if not it.filename.endswith('/')]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for it, data in files:
        if it.filename == 'ppt/slides/slide4.xml': data = slide.encode('utf8')
        z.writestr(it.filename, data)
print(len(rows), 'boxes')
