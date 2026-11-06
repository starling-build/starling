# Lab flt015: lo-015dbec5, a floating one-column table (tblpPr) inside a centred cell; ours sits +2.3 pt.
# Variants of the real document, one change each. Print all in Word for Windows; compare the caption line baselines.
import zipfile, glob, re
src = glob.glob('test/corpus/docx/lo/docs/lo-015dbec5*.docx')[0]
zi = zipfile.ZipFile(src)
F = {n: zi.read(n) for n in zi.namelist()}
x = F['word/document.xml'].decode()
V = {
 'orig': x,
 'nofloat': re.sub(r'<w:tblpPr[^>]*/>', '', x),
 'vtop': x.replace('<w:vAlign w:val="center"/>', '<w:vAlign w:val="top"/>'),
 'novalign': x.replace('<w:vAlign w:val="center"/>', ''),
 'nofloat_vtop': re.sub(r'<w:tblpPr[^>]*/>', '', x).replace('<w:vAlign w:val="center"/>', '<w:vAlign w:val="top"/>'),
}
for k, v in V.items():
    zo = zipfile.ZipFile(f'test/labs/float-015dbec5/flt015-{k}.docx', 'w', zipfile.ZIP_DEFLATED)
    for n, d in F.items():
        zo.writestr(n, v.encode() if n == 'word/document.xml' else d)
    zo.close()
