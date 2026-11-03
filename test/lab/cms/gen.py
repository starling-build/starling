#!/usr/bin/env python3
"""Lab cms (for amd-opus): a CENTRED cell merged over seven rows when the page's foot falls inside its span.
zh-785e46f8's case: Word sets its 3-line "用地、/用能、/环境" (merged over rows 21-27, vAlign center) one line on p9's
foot and two on p10's top, where ours sets all three on p10. Each variant is one page-started block: N filler lines
(exact 15pt, 12pt SimSun) then the table — col A (51.15pt, as the document's) merged over rows 1-7, vAlign center, "用地、用能、环境" in exact
15pt lines (three lines); col B (300pt) rows of 3,2,4,2,3,2,2 lines ("R<row>-<line>" so each line names its row).
The table has a header row repeated on the next page (as zh-785e46f8's). N steps so the foot walks through the span.
Read (meas.py): per variant, every col-B line's page and baseline, and the merged text's lines' pages and baselines.
gen.py OUT.docx"""
import sys, zipfile
NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
ROWS = [3, 2, 4, 2, 3, 2, 2]
FILLERS = list(range(30, 52))      # filler lines before the table, one variant each
def run(t, sz=24):
    return '<w:r><w:rPr><w:rFonts w:ascii="SimSun" w:hAnsi="SimSun" w:eastAsia="SimSun"/><w:sz w:val="%d"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (sz, t)
def para(t, br=False, jc=None):
    ppr = '<w:pPr>%s<w:spacing w:before="0" w:after="0" w:line="300" w:lineRule="exact"/>%s</w:pPr>' % ('<w:pageBreakBefore/>' if br else '', '<w:jc w:val="%s"/>' % jc if jc else '')
    return '<w:p>%s%s</w:p>' % (ppr, t)
def cell(w, paras, extra=''):
    return '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s</w:tcPr>%s</w:tc>' % (w, extra, ''.join(paras))
def table():
    borders = '<w:tblBorders>' + ''.join('<w:%s w:val="single" w:sz="4" w:space="0" w:color="000000"/>' % s for s in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV')) + '</w:tblBorders>'
    rows = ['<w:tr><w:trPr><w:tblHeader/></w:trPr>%s%s</w:tr>' % (cell(1023, [para(run('领域'), jc='center')]), cell(6000, [para(run('政策内容'), jc='center')]))]
    for i, n in enumerate(ROWS):
        a = cell(1023, [para(run('用地、用能、环境'))], '<w:vMerge w:val="restart"/><w:vAlign w:val="center"/>') if i == 0 else cell(1023, [para('')], '<w:vMerge/><w:vAlign w:val="center"/>')
        b = cell(6000, [para(run('R%d-%d' % (i + 1, k + 1))) for k in range(n)])
        rows.append('<w:tr>%s%s</w:tr>' % (a, b))
    return ('<w:tbl><w:tblPr><w:tblW w:w="7023" w:type="dxa"/>%s<w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="1023"/><w:gridCol w:w="6000"/></w:tblGrid>%s</w:tbl>' % (borders, ''.join(rows)))
def body():
    out = []
    for v, n in enumerate(FILLERS):
        out.append(para(run('V%d filler 1' % (v + 1)), br=v > 0))
        out += [para(run('filler %d' % (k + 2))) for k in range(n - 1)]
        out.append(table())
        out.append(para(run('end V%d' % (v + 1))))
    return ''.join(out)
if __name__ == '__main__':
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (NS, body(), sect)
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
    rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
    with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', rels); z.writestr('word/document.xml', doc)
    print(len(FILLERS), 'variants ->', sys.argv[1])
