# Lab: a run of periods in a narrow table cell (zh-92373179 p11: Word puts 1 dot on the
# first line and 4 on the next; we keep all 5 together). Cells are the real cell: 14 pt
# 仿宋_GB2312, hint eastAsia, jc left. Cases: N periods (3..12) x cell width (941/1200/1600 tw)
# x first-line indent (552 = real, 0). Column 2 carries the case label.
# Template: the real docx (styles, settings, sectPr); only the body is replaced.
import zipfile, re, sys, glob
src = glob.glob('test/corpus/docx/docs/zh-92373179*.docx')[0]
out = sys.argv[1] if len(sys.argv) > 1 else 'test/labs/dot-run/dot-run.docx'
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode()
sect = re.search(r'<w:sectPr.*?</w:sectPr>', doc, re.S).group(0)
head = doc[:doc.index('<w:body>') + 8]
RP = '<w:rPr><w:rFonts w:hint="eastAsia" w:ascii="仿宋_GB2312"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>'
def cell(w, ind, text):
    return ('<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:ind w:firstLine="%d"/><w:jc w:val="left"/>%s</w:pPr>'
            '<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r></w:p></w:tc>') % (w, ind, RP, RP, text)
rows = []
for w in (941, 1200, 1600):
    for ind in (552, 0):
        for n in range(3, 13):
            rows.append('<w:tr>%s%s</w:tr>' % (cell(w, ind, '.' * n), cell(3000, 0, 'w%d i%d n%d' % (w, ind, n))))
grid = '<w:tblGrid><w:gridCol w:w="1600"/><w:gridCol w:w="3000"/></w:tblGrid>'
tbl = ('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblLayout w:type="fixed"/>'
       '<w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/>'
       '<w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders>'
       '<w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>%s%s</w:tbl><w:p/>') % (grid, ''.join(rows))
new = head + tbl + sect + '</w:body></w:document>'
zo = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED)
for it in z.infolist():
    zo.writestr(it, new.encode() if it.filename == 'word/document.xml' else z.read(it.filename))
zo.close(); print(out, len(rows))
