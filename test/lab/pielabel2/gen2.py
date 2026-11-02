#!/usr/bin/env python3
"""gen2.py <lo-9fa3dedd1f1d716a.docx> <outdir>: pielabel's pies again, but each label is its own rich text of N
lines (N = 1, 2, 3, 5; one short word per line, 16 pt bold Times, white): 48 documents."""
import zipfile, sys, os
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
WORDS = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
def rich(n, prefix):
    paras = "".join(f'<a:p><a:r><a:rPr lang="en-US" sz="1600" b="1"/><a:t>{prefix}{WORDS[i]}</a:t></a:r></a:p>' for i in range(n))
    return f'<c:tx><c:rich><a:bodyPr/><a:lstStyle/>{paras}</c:rich></c:tx>'
for deg in (180, 220, 270, 300):
    big = round(deg / 360 * 100)
    for pos in ("ctr", "inEnd", "bestFit"):
        for n in (1, 2, 3, 5):
            chart = z.read("word/charts/chart1.xml").decode()
            chart = chart.replace('<c:dLblPos val="bestFit"/>', f'<c:dLblPos val="{pos}"/>')
            chart = chart.replace('<c:pt idx="0"><c:v>80</c:v></c:pt><c:pt idx="1"><c:v>20</c:v></c:pt>',
                                  f'<c:pt idx="0"><c:v>{big}</c:v></c:pt><c:pt idx="1"><c:v>{100-big}</c:v></c:pt>')
            chart = chart.replace('<c:dLbl><c:idx val="0"/>', '<c:dLbl><c:idx val="0"/>' + rich(n, ""), 1)
            chart = chart.replace('<c:dLbl><c:idx val="1"/>', '<c:dLbl><c:idx val="1"/>' + rich(n, ""), 1)
            name = f"pie-{deg}-{pos}-{n}line.docx"
            with zipfile.ZipFile(os.path.join(out, name), "w", zipfile.ZIP_DEFLATED) as o:
                for i in z.infolist():
                    o.writestr(i.filename, chart.encode() if i.filename == "word/charts/chart1.xml" else z.read(i.filename))
print(len(os.listdir(out)), "documents in", out)
