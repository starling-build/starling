# lo-tdf76115's sheet (Segoe UI 8 cells in a Calibri 11 book, no sheetViews/
# sheetFormatPr/cols) in four copies: as is, +sheetViews, +sheetFormatPr, +cols.
# First 60 rows only. Usage: mk.py SRC.xlsx OUTDIR
import zipfile, re, sys, os
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
files = {n.replace('\\', '/'): z.read(n) for n in z.namelist()}
sheet = files['xl/sheet1.xml'].decode('latin-1')
rows = re.findall(r'<row r="\d+".*?</row>', sheet, re.S)[:60]
head = sheet[:sheet.index('<sheetData>')]
tail = sheet[sheet.index('</sheetData>') + len('</sheetData>'):]
body = '<sheetData>' + ''.join(rows) + '</sheetData>'
variants = {
  'asis': (head, body),
  'view': (head + '<sheetViews><sheetView workbookViewId="0"/></sheetViews>', body),
  'fmtpr': (head + '<sheetFormatPr defaultRowHeight="15"/>', body),
  'cols': (head + '<cols><col min="1" max="1" width="12" customWidth="1"/></cols>', body),
}
for k, (h, b) in variants.items():
    f = dict(files); f['xl/sheet1.xml'] = (h + b + tail).encode('latin-1')
    with zipfile.ZipFile(f'{out}/rowfmt-{k}.xlsx', 'w', zipfile.ZIP_DEFLATED) as o:
        for n, d in f.items(): o.writestr(n, d)
