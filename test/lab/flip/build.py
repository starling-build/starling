#!/usr/bin/env python3
"""Lab flip: does PowerPoint leave a flipped shape's text upright, or turn it a half round?
Three slides. Boxes 150x60 pt, plain rectangle, blue 0.75pt outline, Courier New 14, text "Ab cd" / "ef gh", anchor top.
Slide 1: columns none / flipH / flipV / flipH+flipV; rows horizontal text, vert270, vert (xfrm flips only, bodyPr rot 0).
Slide 2: the same with bodyPr rot=30 degrees.
Slide 3: the same four flips with the SHAPE turned 30 degrees (xfrm rot), horizontal text, plus a second row turned 90.
Usage: build.py TEMPLATE.pptx OUT.pptx   (any one-slide deck, e.g. test/corpus/pptx/decks/oox-tdf149551_TextRot.pptx)"""
import sys, zipfile, re
tpl, out = sys.argv[1], sys.argv[2]
E=12700
FLIPS=[('', 'none'), (' flipH="1"', 'flipH'), (' flipV="1"', 'flipV'), (' flipH="1" flipV="1"', 'flipHV')]
def box(i, name, flip, vert, brot, srot, col, row):
    x = 15 + col * 165; y = (20 + row * 130) if srot == 0 else (95 + row * 200)
    run = '<a:r><a:rPr lang="en-US" sz="1400"><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:latin typeface="Courier New"/></a:rPr><a:t>%s</a:t></a:r>'
    return f'''<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="{name}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm rot="{srot*60000}"{flip}><a:off x="{x*E}" y="{y*E}"/><a:ext cx="{150*E}" cy="{60*E}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="9525"><a:solidFill><a:srgbClr val="4472C4"/></a:solidFill></a:ln></p:spPr><p:txBody><a:bodyPr rot="{brot*60000}" vert="{vert}" wrap="square" rtlCol="0" anchor="t"/><a:lstStyle/><a:p>{run % "Ab cd"}</a:p><a:p>{run % "ef gh"}</a:p></p:txBody></p:sp>'''
zin = zipfile.ZipFile(tpl)
s1 = zin.read('ppt/slides/slide1.xml').decode()
head = s1[:s1.index('<p:sp>')]
tail = s1[s1.rindex('</p:sp>') + len('</p:sp>'):]
def slide(k):
    n = 2; body = ''
    if k in (1, 2):
        for row, vert in enumerate(('horz', 'vert270', 'vert')):
            for col, (fl, nm) in enumerate(FLIPS):
                body += box(n, f'{nm} {vert} rot{0 if k==1 else 30}', fl, vert, 0 if k == 1 else 30, 0, col, row); n += 1
    else:
        for row, srot in enumerate((30, 90)):
            for col, (fl, nm) in enumerate(FLIPS):
                body += box(n, f'{nm} shaperot{srot}', fl, 'horz', 0, srot, col, row); n += 1
    return head + body + tail
rels = zin.read('ppt/slides/_rels/slide1.xml.rels')
zout = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
for item in zin.infolist():
    data = zin.read(item.filename)
    if item.filename == 'ppt/slides/slide1.xml': data = slide(1).encode()
    elif item.filename == '[Content_Types].xml':
        add = ''.join(f'<Override PartName="/ppt/slides/slide{k}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>' for k in (2, 3))
        data = data.decode().replace('</Types>', add + '</Types>').encode()
    elif item.filename == 'ppt/_rels/presentation.xml.rels':
        add = ''.join(f'<Relationship Id="rId{90+k}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{k}.xml"/>' for k in (2, 3))
        data = data.decode().replace('</Relationships>', add + '</Relationships>').encode()
    elif item.filename == 'ppt/presentation.xml':
        data = re.sub(r'(<p:sldId id="256" r:id="rId2"/>)', r'\1<p:sldId id="257" r:id="rId92"/><p:sldId id="258" r:id="rId93"/>', data.decode()).encode()
    zout.writestr(item.filename, data)
for k in (2, 3):
    zout.writestr(f'ppt/slides/slide{k}.xml', slide(k))
    zout.writestr(f'ppt/slides/_rels/slide{k}.xml.rels', rels)
zout.close()
