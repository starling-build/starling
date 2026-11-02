#!/usr/bin/env python3
"""Lab vertrot: where PowerPoint puts text that is both vertical (bodyPr vert) and turned (bodyPr rot).
Three slides, one per vert mode (vert, vert270, eaVert); on each, columns rot 0/30/90/180 degrees,
row 1 a wide box (150x60 pt), row 2 a tall box (60x150 pt). Plain rectangle, blue 0.75pt outline,
default insets, anchor top, Courier New 14, two paragraphs ("Ab cd" / "ef gh").
Usage: build.py TEMPLATE.pptx OUT.pptx   (TEMPLATE: any one-slide deck, e.g. test/corpus/pptx/decks/oox-tdf149551_TextRot.pptx)
Print each slide to PDF/PNG and report, per box: the text's ink bounding box and its angle."""
import sys, zipfile, re
tpl, out = sys.argv[1], sys.argv[2]
E=12700
def box(i, vert, rot, wide, col):
    w, h = (150, 60) if wide else (60, 150)
    x = 20 + col * 165 + (0 if wide else 45)
    y = 25 if wide else 215
    return f'''<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="{vert} rot{rot} {'wide' if wide else 'tall'}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="{x*E}" y="{y*E}"/><a:ext cx="{w*E}" cy="{h*E}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="9525"><a:solidFill><a:srgbClr val="4472C4"/></a:solidFill></a:ln></p:spPr><p:txBody><a:bodyPr rot="{rot*60000}" vert="{vert}" wrap="square" rtlCol="0" anchor="t"/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="1400"><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:latin typeface="Courier New"/></a:rPr><a:t>Ab cd</a:t></a:r></a:p><a:p><a:r><a:rPr lang="en-US" sz="1400"><a:solidFill><a:srgbClr val="000000"/></a:solidFill><a:latin typeface="Courier New"/></a:rPr><a:t>ef gh</a:t></a:r></a:p></p:txBody></p:sp>'''
zin = zipfile.ZipFile(tpl)
s1 = zin.read('ppt/slides/slide1.xml').decode()
head = s1[:s1.index('<p:sp>')]
tail = s1[s1.rindex('</p:sp>') + len('</p:sp>'):]
def slide(vert):
    n = 2
    body = ''
    for wide in (True, False):
        for col, rot in enumerate((0, 30, 90, 180)):
            body += box(n, vert, rot, wide, col); n += 1
    return head + body + tail
modes = ['vert', 'vert270', 'eaVert']
rels = zin.read('ppt/slides/_rels/slide1.xml.rels')
zout = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
for item in zin.infolist():
    data = zin.read(item.filename)
    if item.filename == 'ppt/slides/slide1.xml':
        data = slide(modes[0]).encode()
    elif item.filename == '[Content_Types].xml':
        t = data.decode()
        add = ''.join(f'<Override PartName="/ppt/slides/slide{k}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>' for k in (2, 3))
        data = t.replace('</Types>', add + '</Types>').encode()
    elif item.filename == 'ppt/_rels/presentation.xml.rels':
        t = data.decode()
        add = ''.join(f'<Relationship Id="rId{90+k}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{k}.xml"/>' for k in (2, 3))
        data = t.replace('</Relationships>', add + '</Relationships>').encode()
    elif item.filename == 'ppt/presentation.xml':
        t = data.decode()
        t = re.sub(r'(<p:sldId id="256" r:id="rId2"/>)', r'\1<p:sldId id="257" r:id="rId92"/><p:sldId id="258" r:id="rId93"/>', t)
        data = t.encode()
    zout.writestr(item.filename, data)
for k in (2, 3):
    zout.writestr(f'ppt/slides/slide{k}.xml', slide(modes[k - 1]))
    zout.writestr(f'ppt/slides/_rels/slide{k}.xml.rels', rels)
zout.close()
