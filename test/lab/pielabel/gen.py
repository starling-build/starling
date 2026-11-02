#!/usr/bin/env python3
"""Builds 24 one-pie documents: the big slice at 180/220/270/300 degrees, labels inside
(ctr/inEnd/bestFit), short ("NN%") and long (category name) text. Template: lo-9fa3dedd's chart."""
import zipfile, sys, os, re
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
for deg in (180, 220, 270, 300):
    big = round(deg / 360 * 100)
    for pos in ("ctr", "inEnd", "bestFit"):
        for kind in ("short", "long"):
            chart = z.read("word/charts/chart1.xml").decode()
            chart = chart.replace('<c:dLblPos val="bestFit"/>', f'<c:dLblPos val="{pos}"/>')
            chart = chart.replace('<c:pt idx="0"><c:v>80</c:v></c:pt><c:pt idx="1"><c:v>20</c:v></c:pt>',
                                  f'<c:pt idx="0"><c:v>{big}</c:v></c:pt><c:pt idx="1"><c:v>{100-big}</c:v></c:pt>')
            if kind == "long":
                chart = chart.replace('<c:v>green</c:v>', '<c:v>Large slice with a long name</c:v>').replace('<c:v>red</c:v>', '<c:v>Small slice</c:v>')
                chart = chart.replace('<c:showCatName val="0"/><c:showSerName val="0"/><c:showPercent val="1"/>',
                                      '<c:showCatName val="1"/><c:showSerName val="0"/><c:showPercent val="0"/>')
            name = f"pie-{deg}-{pos}-{kind}.docx"
            with zipfile.ZipFile(os.path.join(out, name), "w", zipfile.ZIP_DEFLATED) as o:
                for i in z.infolist():
                    o.writestr(i.filename, chart.encode() if i.filename == "word/charts/chart1.xml" else z.read(i.filename))
print(len(os.listdir(out)), "documents in", out)
