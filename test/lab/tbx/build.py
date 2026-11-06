#!/usr/bin/env python3
"""Lab tbx (for Windows, from lenovo-2): where does a paragraph's text line sit under a wrapSquare text box
that fills the line's width? zh-8e8d4c40 p1: the line "政府補助款經費科目及編列原則" (bold 14pt PMingLiU) under a box
(top 74295 EMU below the paragraph, 5273040 x 598170 EMU, effectExtent b=11430, border 758) is 2.0 pt LOWER in
our print than in Word's (Word baseline 121.9, ours 123.9).
One page per case, ONE parameter varied from the base case; page text: "Cnn" + the line. A4, margins top 908 / 720 sides, no header.
usage: build.py OUTDIR -> OUTDIR/tbx.docx and OUTDIR/cases.tsv"""
import sys, os, zipfile
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
BASE = dict(offV=74295, offH=769620, w=5273040, h=598170, eb=11430, distB=0, wrap='square', sz=28, bold=1, border=758, ind=1274, spaceB=0, line='')
CASES = [('base', {})]
for k, vs in [('eb', [0, 40000, 100000]), ('distB', [57150, 114300]), ('h', [400000, 700000, 800000, 1000000]),
              ('offV', [0, 150000, 300000]), ('wrap', ['tb', 'tight']), ('sz', [20, 24, 36]), ('bold', [0]), ('border', [0, 12700]),
              ('ind', [0]), ('spaceB', [240])]:
    for v in vs: CASES.append(('%s=%s' % (k, v), {k: v}))
CASES.append(('line=exact300', {'line': '<w:spacing w:before="0" w:after="0" w:line="300" w:lineRule="exact"/>'}))
CASES.append(('line=auto240', {'line': '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'}))
FONT = '<w:rFonts w:ascii="標楷體" w:eastAsia="標楷體" w:hAnsi="標楷體" w:cs="標楷體"/>'
PM = '<w:rFonts w:ascii="PMingLiU" w:eastAsia="PMingLiU" w:hAnsi="PMingLiU" w:cs="PMingLiU"/>'
def page(i, name, o):
    c = dict(BASE); c.update(o)
    wrap = {'square': '<wp:wrapSquare wrapText="bothSides"/>', 'tb': '<wp:wrapTopAndBottom/>',
            'tight': '<wp:wrapTight wrapText="bothSides"><wp:wrapPolygon edited="0"><wp:start x="0" y="0"/><wp:lineTo x="0" y="21600"/><wp:lineTo x="21600" y="21600"/><wp:lineTo x="21600" y="0"/><wp:lineTo x="0" y="0"/></wp:wrapPolygon></wp:wrapTight>'}[c['wrap']]
    ln = '<a:ln w="%d"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln>' % c['border'] if c['border'] else '<a:ln><a:noFill/></a:ln>'
    tag = 'C%02d' % i
    box = ('<w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><wp:anchor distT="0" distB="%d" distL="114300" distR="114300" simplePos="0" relativeHeight="%d" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
           '<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="column"><wp:posOffset>%d</wp:posOffset></wp:positionH><wp:positionV relativeFrom="paragraph"><wp:posOffset>%d</wp:posOffset></wp:positionV>'
           '<wp:extent cx="%d" cy="%d"/><wp:effectExtent l="0" t="0" r="22860" b="%d"/>%s<wp:docPr id="%d" name="b%d"/><wp:cNvGraphicFramePr/>'
           '<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp><wps:cNvSpPr txBox="1"/><wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/>%s</wps:spPr>'
           '<wps:txbx><w:txbxContent><w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:rPr>%s<w:sz w:val="28"/></w:rPr><w:t>%s box</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr/></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></mc:Choice></mc:AlternateContent></w:r>'
           ) % (c['distB'], 251654656 + i, c['offH'], c['offV'], c['w'], c['h'], c['eb'], wrap, i + 1, i, c['w'], c['h'], ln, FONT, tag)
    rp = '%s<w:b w:val="%d"/><w:sz w:val="%d"/><w:szCs w:val="%d"/>' % (PM, c['bold'], c['sz'], c['sz'])
    sp = c['line'] or '<w:spacing w:before="%d" w:after="0"/>' % c['spaceB']
    pb = '<w:pageBreakBefore/>' if i else ''
    p1 = '<w:p><w:pPr>%s%s<w:ind w:firstLine="%d"/></w:pPr>%s<w:r><w:rPr>%s</w:rPr><w:t>%s政府補助款經費科目及編列原則</w:t></w:r></w:p>' % (pb, sp, c['ind'], box, rp, tag)
    p2 = '<w:p><w:r><w:rPr>%s<w:sz w:val="24"/></w:rPr><w:t>%s END 下一段</w:t></w:r></w:p>' % (PM, tag)
    return p1 + p2
body = ''.join(page(i, n, o) for i, (n, o) in enumerate(CASES))
doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="908" w:right="720" w:bottom="1049" w:left="720" w:header="851" w:footer="992" w:gutter="0"/></w:sectPr></w:body></w:document>') % (W, body)
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
R = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
os.makedirs(sys.argv[1], exist_ok=True)
with zipfile.ZipFile(os.path.join(sys.argv[1], 'tbx.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', R); z.writestr('word/document.xml', doc)
open(os.path.join(sys.argv[1], 'cases.tsv'), 'w').write(''.join('C%02d\t%s\n' % (i, n) for i, (n, o) in enumerate(CASES)))
print(len(CASES), 'cases')
