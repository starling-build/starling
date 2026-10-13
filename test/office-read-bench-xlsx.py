#!/usr/bin/env python3
"""A workbook of ROWS rows by 10 columns for test/office-read-bench.sh:
four number columns, three text columns out of a shared-string table of
1,000 strings, and three formulas per row (a sum, a product, a lookup of
the row above), every one with its cached value. Written by hand, part
by part, so the size is exactly what was asked for.

    test/office-read-bench-xlsx.py ROWS OUT.xlsx
"""
import sys, zipfile

rows, out = int(sys.argv[1]), sys.argv[2]
strings = ["item %04d of the catalogue" % i for i in range(1000)]
parts = {
    "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>',
    "_rels/.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    "xl/workbook.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>',
    "xl/_rels/workbook.xml.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>',
    "xl/sharedStrings.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="%d" uniqueCount="%d">%s</sst>'
        % (rows * 3, len(strings), "".join("<si><t>%s</t></si>" % s for s in strings)),
}
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name, text in parts.items():
        z.writestr(name, text)
    with z.open("xl/worksheets/sheet1.xml", "w", force_zip64=True) as f:
        f.write(b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
        buf = []
        for r in range(1, rows + 1):
            a, b, c, d = r, r * 1.5, (r * 7) % 1000, (r % 97) / 4
            prev = a if r == 1 else r - 1
            buf.append(
                '<row r="%d"><c r="A%d"><v>%d</v></c><c r="B%d"><v>%s</v></c><c r="C%d"><v>%d</v></c><c r="D%d"><v>%s</v></c>'
                '<c r="E%d" t="s"><v>%d</v></c><c r="F%d" t="s"><v>%d</v></c><c r="G%d" t="s"><v>%d</v></c>'
                '<c r="H%d"><f>SUM(A%d:D%d)</f><v>%s</v></c><c r="I%d"><f>A%d*D%d</f><v>%s</v></c><c r="J%d"><f>%s</f><v>%d</v></c></row>'
                % (r, r, a, r, b, r, c, r, d, r, r % 1000, r, (r * 3) % 1000, r, (r * 11) % 1000,
                   r, r, r, a + b + c + d, r, r, r, a * d, r, ("A%d" % (r - 1)) if r > 1 else "A1", prev))
            if len(buf) == 5000:
                f.write("".join(buf).encode()); buf = []
        f.write("".join(buf).encode())
        f.write(b"</sheetData></worksheet>")
print("wrote %d rows, %d cells to %s" % (rows, rows * 10, out))
