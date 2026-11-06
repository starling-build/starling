# Lab chart-ccd9da4b (dir name kept short; it is the lo-ccd9da4b chart lab; see amd-1 for area charts).
# The bar chart of lo-ccd9da4b at varied widths (EMU), height fixed at the original 2378075.
# Ours: category labels 3.1 pt too far apart in x, legend rows 17.5 vs 17.1 pt. Print in Word for Windows;
# read the category label x positions and legend row pitch per width.
import zipfile, glob
src = glob.glob('test/corpus/docx/lo/docs/lo-ccd9da4b*.docx')[0]
zi = zipfile.ZipFile(src)
F = {n: zi.read(n) for n in zi.namelist()}
x = F['word/document.xml'].decode()
old = '<wp:extent cx="4226560" cy="2378075"/>'
assert old in x
for cx in (2800000, 3400000, 4226560, 5000000, 5800000):
    v = x.replace(old, f'<wp:extent cx="{cx}" cy="2378075"/>')
    zo = zipfile.ZipFile(f'test/labs/chart-ccd9da4b/chart-ccd9da4b-w{cx}.docx', 'w', zipfile.ZIP_DEFLATED)
    for n, d in F.items():
        zo.writestr(n, v.encode() if n == 'word/document.xml' else d)
    zo.close()
