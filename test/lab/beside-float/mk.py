#!/usr/bin/env python3
"""Lab: when does Word set a NON-floating table / text in the strip beside a wide float, and when under it?
Writes one .docx per case into ./docs (names say the case). Page A4 portrait, margins 1134 -> column 9639 twips = 481.95 pt.
Case name: <float>-<pct>-<follow>[-ovl]
  float  : tbl  = a floating table (tblpPr vertAnchor=text tblpY=1, 22 rows of 15pt, tblOverlap never; -ovl = overlap allowed)
           sq / tb = a rectangle shape anchored in the first paragraph, wrapSquare / wrapTopAndBottom, 330pt tall, at the left margin
  pct    : the float's width, 50 / 65 / 78 / 90 percent of the column (the original lo-5e49366b is 7000 twips = 73%)
  follow : what comes after the float's anchor
    ept-ctr  empty paragraph, a centred 900+900 twip table (cells T1 T2), "x"            (lo-5e49366b's shape)
    ept-lft  empty paragraph, a left-aligned 1800 twip table, "x"
    nar      empty paragraph, a centred 900 twip table (one cell T1), "x"
    wide     empty paragraph, a fixed 4000 twip table (T1 T2), "x"
    full     empty paragraph, an autofit table at 100% width (T1 T2), "x"
    txt      "x" directly, left            (zh-316044fe's "附件2：")
    ctr      "x" directly, centred         (zh-316044fe's title)
    ept-txt  empty paragraph, then "x"
  Every case ends with a long paragraph LONG... (40 words) to see where the following lines stand.
"""
import os, zipfile, sys
COL = 9639
NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" '
      'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
      'xmlns:wpg="http://schemas.microsoft.com/office/word/2010/wordprocessingGroup" '
      'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" mc:Ignorable="w14"')
def cell(w, t=""):
    r = f'<w:r><w:t>{t}</w:t></w:r>' if t else ''
    return f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/></w:tcPr><w:p>{r}</w:p></w:tc>'
def table(widths, texts, jc=None, fixed=True, pct=False):
    tw = '<w:tblW w:w="5000" w:type="pct"/>' if pct else f'<w:tblW w:w="{sum(widths)}" w:type="dxa"/>'
    j = f'<w:jc w:val="{jc}"/>' if jc else ''
    lay = '<w:tblLayout w:type="fixed"/>' if fixed else ''
    b = '<w:tblBorders>' + ''.join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="auto"/>' for s in ('top','left','bottom','right','insideH','insideV')) + '</w:tblBorders>'
    grid = ''.join(f'<w:gridCol w:w="{w}"/>' for w in widths)
    row = '<w:tr><w:trPr><w:trHeight w:val="300"/></w:trPr>' + ''.join(cell(w, t) for w, t in zip(widths, texts)) + '</w:tr>'
    return f'<w:tbl><w:tblPr>{tw}{j}{b}{lay}</w:tblPr><w:tblGrid>{grid}</w:tblGrid>{row}</w:tbl>'
def float_table(width, overlap_never=True):
    n = 7; cw = width // n; ws = [cw] * n
    rows = ''
    for r in range(22):
        rows += '<w:tr><w:trPr><w:trHeight w:val="300"/></w:trPr>' + ''.join(cell(w, 'F' if (r == 0 and c == 0) else '') for c, w in enumerate(ws)) + '</w:tr>'
    b = '<w:tblBorders>' + ''.join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="auto"/>' for s in ('top','left','bottom','right','insideH','insideV')) + '</w:tblBorders>'
    ov = '<w:tblOverlap w:val="never"/>' if overlap_never else ''
    return (f'<w:tbl><w:tblPr><w:tblW w:w="{cw*n}" w:type="dxa"/><w:tblpPr w:leftFromText="141" w:rightFromText="141" w:vertAnchor="text" w:tblpY="1"/>'
            f'{ov}{b}<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>' + ''.join(f'<w:gridCol w:w="{w}"/>' for w in ws) + f'</w:tblGrid>{rows}</w:tbl>')
def shape_anchor(width_tw, wrap):
    emu = lambda tw: int(tw * 635)
    w = emu(width_tw); h = int(330 * 12700)
    wr = '<wp:wrapSquare wrapText="bothSides"/>' if wrap == 'sq' else '<wp:wrapTopAndBottom/>'
    return (f'<w:p><w:r><w:drawing><wp:anchor distT="0" distB="0" distL="89535" distR="89535" simplePos="0" relativeHeight="1" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1">'
            f'<wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="margin"><wp:posOffset>0</wp:posOffset></wp:positionH>'
            f'<wp:positionV relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset></wp:positionV>'
            f'<wp:extent cx="{w}" cy="{h}"/><wp:effectExtent l="0" t="0" r="0" b="0"/>{wr}<wp:docPr id="1" name="Float"/><wp:cNvGraphicFramePr/>'
            f'<a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape"><wps:wsp><wps:cNvSpPr/>'
            f'<wps:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{w}" cy="{h}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
            f'<a:solidFill><a:srgbClr val="DDDDDD"/></a:solidFill><a:ln w="9525"><a:solidFill><a:srgbClr val="000000"/></a:solidFill></a:ln></wps:spPr>'
            f'<wps:bodyPr/></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>')
X = '<w:p><w:r><w:t>x</w:t></w:r></w:p>'
XC = '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>x</w:t></w:r></w:p>'
E = '<w:p/>'
LONG = '<w:p><w:r><w:t>' + ' '.join(f'LONG{i}' for i in range(1, 41)) + '</w:t></w:r></w:p>'
FOLLOW = {
    'ept-ctr': lambda: E + table([900, 900], ['T1', 'T2'], jc='center') + X,
    'ept-lft': lambda: E + table([900, 900], ['T1', 'T2']) + X,
    'nar': lambda: E + table([900], ['T1'], jc='center') + X,
    'wide': lambda: E + table([2000, 2000], ['T1', 'T2']) + X,
    'full': lambda: E + table([4800, 4800], ['T1', 'T2'], fixed=False, pct=True) + X,
    'txt': lambda: X,
    'ctr': lambda: XC,
    'ept-txt': lambda: E + X,
}
def doc(kind, pct, follow, ovl=False):
    width = COL * pct // 100
    if kind == 'tbl':
        head = float_table(width, overlap_never=not ovl)
    else:
        head = shape_anchor(width, kind)
    body = head + FOLLOW[follow]() + LONG
    sect = '<w:sectPr><w:pgSz w:w="11907" w:h="16840"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
CT = ('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>'
def write(name, xml, out):
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/document.xml', xml); z.writestr('word/_rels/document.xml.rels', DRELS)
if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else 'docs'
    os.makedirs(out, exist_ok=True); n = 0
    for pct in (50, 65, 78, 90):
        for f in FOLLOW:
            write(f'tbl-{pct}-{f}', doc('tbl', pct, f), out); n += 1
    for f in FOLLOW:
        write(f'tbl-78-{f}-ovl', doc('tbl', 78, f, ovl=True), out); n += 1
    for kind in ('sq', 'tb'):
        for pct in (50, 65, 78, 90):
            for f in ('ept-ctr', 'txt', 'ctr'):
                write(f'{kind}-{pct}-{f}', doc(kind, pct, f), out); n += 1
    write('orig-like', doc('tbl', 73, 'ept-ctr'), out); n += 1   # 7000 twips, the corpus file's own width
    print(n, 'docs in', out)
