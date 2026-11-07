#!/usr/bin/env python3
"""Lab gothic-last (Windows, for amd-3): why does Word put a punctuation-only last line (引》）。) 4.3 pt higher
than we do, and the next paragraph 4.7 pt lower?  Source paragraph: zh-5450d509 p1 (仿宋_GB2312 -> JhengHei + MS Gothic
punctuation, grid lines pitch 312, line 360 auto, firstLineChars 200).  One variant per page (pageBreakBefore),
each preceded by an Arial label line and followed by the next real paragraph's twin so the gap below shows.
Variants: 1 as-is; 2 line rule auto 240; 3 docGrid removed; 4 eastAsia 宋体; 5 one extra char in front (reflow);
6 line 360 exact-free atLeast 360; 7 size 28 (14pt) ; 8 as-is without firstLine indent.
gen.py SRC.docx OUT.docx [nogrid]   (nogrid: the same eight pages with docGrid removed from the section; V3 in the grid file is a duplicate of V1 and means nothing)"""
import sys, zipfile, re
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
d = z.read("word/document.xml").decode()
i = d.find("引》）")
s = max(d.rfind("<w:p>", 0, i), d.rfind("<w:p ", 0, i)); e = d.find("</w:p>", i) + 6
para = d[s:e]
V = []
def add(label, p, grid=True):
    V.append((label, p, grid))
add("V1 as-is", para)
add("V2 line auto 240", para.replace('w:line="360"', 'w:line="240"'))
add("V3 grid off", para, False)
add("V4 eastAsia SimSun", para.replace("仿宋_GB2312", "宋体"))
add("V5 one extra char", para.replace("<w:t>按照", "<w:t>据按照", 1))
add("V6 atLeast 360", para.replace('w:lineRule="auto"', 'w:lineRule="atLeast"'))
add("V7 size 28 all runs", re.sub(r"<w:rPr>(?!<w:sz )", "<w:rPr><w:sz w:val=\"28\"/><w:szCs w:val=\"28\"/>", para))
add("V9 last line 2 chars shorter, size 24", para.replace("引》）", "引》"))
add("V8 no firstLine", para.replace('<w:ind w:firstLine="480" w:firstLineChars="200"/>', ""))
body = ""
for n, (label, p, grid) in enumerate(V):
    lab = ('<w:p><w:pPr><w:pageBreakBefore/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/></w:rPr>'
           '<w:t>%s</w:t></w:r></w:p>' % label)
    body += lab + p + p
sect = re.findall(r"<w:sectPr.*?</w:sectPr>", d, re.S)[0]
if "</w:p>" in sect: sect = re.findall(r"<w:sectPr.*?</w:sectPr>", d, re.S)[-1]
if len(sys.argv) > 3 and sys.argv[3] == "nogrid": sect = re.sub(r"<w:docGrid[^>]*/>", "", sect)  # V3: run the whole lab with the grid off (compare with the grid-on file)
head = d[:d.find("<w:body>") + 8]
doc = head + body + sect + "</w:body></w:document>"
zo = zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED)
for it in z.infolist():
    data = z.read(it.filename)
    if it.filename == "word/document.xml": data = doc.encode()
    zo.writestr(it, data)
zo.close()
