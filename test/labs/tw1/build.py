# build.py OUTDIR — lab tw1: how Word for Windows sets the columns of a table whose second row has cells wider than the
# grid. LibreOffice's tdf79329 (lo-43db5218741de0fa): tblGrid 4536 + 1845 (6381), row 1 cells 4536 + 1845 ("A1"/"B1"),
# row 2 cells 6381 + 6381 ("C1"/"D1"), jc centre on table and rows, A4, margins 1134 (text 9638 twips = 481.9pt).
# Word's print: A1 and A1-2 at x 57, B1 and D1 BOTH at x 310; ours centres a 319pt table with a 226.8pt first column.
# Eight documents, each the same two-row bordered table with every cell one word; only row 2's widths and the alignment move:
#   orig    row 2 = 6381 + 6381, jc centre        (the original; control: A1 57, B1/D1 310)
#   left    row 2 = 6381 + 6381, jc left
#   fixed   row 2 = 6381 + 6381, tblLayout fixed
#   same    row 2 = 4536 + 1845 (as the grid)
#   small   row 2 = 3000 + 3000
#   wide    row 2 = 9000 + 3000
#   one     row 2 = one cell 6381
#   pct     row 2 = 50% + 50% (tblW pct 5000)
import sys, os, zipfile
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
NS = ('xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"')
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
B = ''.join('<w:%s w:val="single" w:sz="4" w:space="0" w:color="auto"/>' % s for s in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'))
def cell(w, text, kind="dxa"):
    return ('<w:tc><w:tcPr><w:tcW w:w="%d" w:type="%s"/></w:tcPr><w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
            '<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="24"/></w:rPr><w:t>%s</w:t></w:r></w:p></w:tc>' % (w, kind, text))
def row(cells, jc):
    return '<w:tr><w:trPr><w:trHeight w:val="567"/>%s</w:trPr>%s</w:tr>' % ('<w:jc w:val="%s"/>' % jc if jc else '', cells)
def table(row2, jc="center", fixed=False, tblw='<w:tblW w:w="0" w:type="auto"/>'):
    pr = '<w:tblPr>%s%s<w:tblBorders>%s</w:tblBorders>%s</w:tblPr>' % (
        tblw, '<w:jc w:val="%s"/>' % jc if jc else '', B, '<w:tblLayout w:type="fixed"/>' if fixed else '')
    return ('<w:tbl>%s<w:tblGrid><w:gridCol w:w="4536"/><w:gridCol w:w="1845"/></w:tblGrid>%s%s</w:tbl>' % (
        pr, row(cell(4536, "A1") + cell(1845, "B1"), jc), row(row2, jc)))
two = lambda a, b: cell(a, "C1") + cell(b, "D1")
VARIANTS = {
    "orig":  table(two(6381, 6381)),
    "left":  table(two(6381, 6381), jc="left"),
    "fixed": table(two(6381, 6381), fixed=True),
    "same":  table(two(4536, 1845)),
    "small": table(two(3000, 3000)),
    "wide":  table(two(9000, 3000)),
    "one":   table(cell(6381, "C1")),
    "pct":   table(cell(2500, "C1", "pct") + cell(2500, "D1", "pct"), tblw='<w:tblW w:w="5000" w:type="pct"/>'),
}
SECT = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
for name, tbl in VARIANTS.items():
    body = '<w:p><w:r><w:t>%s</w:t></w:r></w:p>%s<w:p/>%s' % (name, tbl, SECT)
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s</w:body></w:document>' % (NS, body)
    with zipfile.ZipFile(os.path.join(out, "tw-%s.docx" % name), "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS); z.writestr("word/document.xml", doc)
print("wrote", len(VARIANTS), "documents to", out)
