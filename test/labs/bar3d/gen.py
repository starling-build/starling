#!/usr/bin/env python3
"""Build bar3d.docx: one 3-D clustered column chart per page, Word's auto plot area.
Template: zh-b8de3ae2's chart1 (rotX 15, rotY 20, rAngAx 1, empty plot layout, no wall
lines). Usage: gen.py <zh-b8de3ae2.docx> <out.docx>"""
import re, sys, zipfile
src, out = sys.argv[1:3]
z = zipfile.ZipFile(src)
tpl = z.read('word/charts/chart1.xml').decode()
tpl = re.sub(r'<c:externalData.*?</c:externalData>', '', tpl, flags=re.S)
FR = {'F1': (6857365, 3618412), 'F3': (6813550, 4524375), 'F5': (6143625, 4663440), 'N4': (5080000, 3810000), 'N3': (3810000, 3175000)}
LONG = ['Category number one long', 'Category number two long', 'Category number three long',
        'Category number four long', 'Category number five long', 'Category number six long']
SHORT = ['A', 'B', 'C', 'D', 'E', 'F']
BASE = ['罰款及賠償收入', '規費收入', '財產收入', '補助及協助收入', '捐贈及贈與收入', '其他收入']
def mk(frame='F1', title=True, cats=BASE, top=None, legend='b'):
    c = tpl
    if legend is None: c = re.sub(r'<c:legend>.*?</c:legend>', '', c, flags=re.S)
    elif legend != 'b': c = c.replace('<c:legendPos val="b"/>', '<c:legendPos val="%s"/>' % legend)
    if cats is not BASE:
        for a, b in zip(BASE, cats): c = c.replace('<c:v>%s</c:v>' % a, '<c:v>%s</c:v>' % b)
    if top is not None:
        def scale(m):
            vals = [int(v) for v in re.findall(r'<c:v>(\d+)</c:v>', m.group(0))]
            f = top / 107660
            return re.sub(r'<c:v>(\d+)</c:v>', lambda n: '<c:v>%d</c:v>' % max(1, round(int(n.group(1)) * f)), m.group(0))
        c = re.sub(r'<c:val>.*?</c:val>', scale, c, flags=re.S)
    if not title:
        c = re.sub(r'<c:title>.*?</c:title>(?=<c:autoTitleDeleted)', '', c, flags=re.S)
        c = c.replace('<c:autoTitleDeleted val="0"/>', '<c:autoTitleDeleted val="1"/>')
    return frame, c
V = []
SET = sys.argv[3] if len(sys.argv) > 3 else 'a'
for f in (('F1', 'F3', 'F5') if SET == 'a' else []): V += [('%s title on' % f, mk(f)), ('%s title off' % f, mk(f, title=False))]
if SET == 'a': V += [('F1 short labels', mk(cats=SHORT)), ('F1 long labels', mk(cats=LONG)),
      ('F1 max 9', mk(top=9)), ('F1 max 99', mk(top=99)), ('F1 max 9999', mk(top=9999)),
      ('F3 long labels', mk('F3', cats=LONG)), ('F3 max 9', mk('F3', top=9))]
if SET == 'b':
    for f in ('F1', 'F3'):
        for lg in ('r', 't', None): V.append(('%s legend %s' % (f, lg or 'none'), mk(f, legend=lg)))
    V += [('F5 short labels', mk('F5', cats=SHORT)), ('F5 long labels', mk('F5', cats=LONG)),
          ('N4 title on', mk('N4')), ('N4 short labels', mk('N4', cats=SHORT)),
          ('N3 title on', mk('N3')), ('N3 short labels', mk('N3', cats=SHORT)),
          ('N4 legend r', mk('N4', legend='r')), ('N3 legend none', mk('N3', legend=None))]
body, rels, ct = [], [], []
for i, (name, (frame, c)) in enumerate(V, 1):
    cx, cy = FR[frame]
    body.append('<w:p><w:r><w:t>v%02d %s</w:t></w:r></w:p>' % (i, name))
    body.append('<w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="%d" cy="%d"/><wp:docPr id="%d" name="c%d"/><wp:cNvGraphicFramePr/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:id="rIdc%d"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>' % (cx, cy, i, i, i))
    if i < len(V): body.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
    rels.append('<Relationship Id="rIdc%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="charts/lab%d.xml"/>' % (i, i))
    ct.append('<Override PartName="/word/charts/lab%d.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>' % i)
doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
       'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>' + ''.join(body) +
       '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="720" w:right="510" w:bottom="720" w:left="510" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr></w:body></w:document>')
o = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
o.writestr('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' + ''.join(ct) + '</Types>')
o.writestr('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
o.writestr('word/_rels/document.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + ''.join(rels) + '</Relationships>')
o.writestr('word/document.xml', doc)
for i, (name, (frame, c)) in enumerate(V, 1): o.writestr('word/charts/lab%d.xml' % i, c)
o.close()
print(len(V), 'pages ->', out)
