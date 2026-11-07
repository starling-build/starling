#!/usr/bin/env python3
"""Lab yahei-fallback (Windows, for amd-3): zh-51af781b p64.  The paragraph starting 说明：1.除特别 has runs in
方正楷体_GBK (not on Windows) mixed with 仿宋; our print puts its lines ~9 pt off Word's.  One variant per page:
1 as-is; 2 方正楷体_GBK -> 楷体; 3 -> 仿宋; 4 -> 宋体; 5 drop w:spacing 13/8 (character spacing);
6 line rule auto 422 -> 240; 7 only the 方正楷体_GBK runs (others blanked).
Each variant is on a page of the source section (landscape 16850x11910).
gen.py SRC.docx OUT.docx"""
import sys, zipfile, re
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
d = z.read("word/document.xml").decode()
i = d.find("说明：1.除特别")
s = max(d.rfind("<w:p>", 0, i), d.rfind("<w:p ", 0, i)); e = d.find("</w:p>", i) + 6
para = d[s:e]
para = re.sub(r"<w:sectPr>.*?</w:sectPr>", "", para, flags=re.S)
G = "方正楷体_GBK"
V = [("V1 as-is", para),
     ("V2 KaiTi", para.replace(G, "楷体")),
     ("V3 FangSong", para.replace(G, "仿宋")),
     ("V4 SimSun", para.replace(G, "宋体")),
     ("V5 no char spacing", re.sub(r'<w:spacing w:val="\d+"/>', "", para)),
     ("V6 line 240", para.replace('w:line="422"', 'w:line="240"'))]
body = ""
for label, p in V:
    body += ('<w:p><w:pPr><w:pageBreakBefore/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/></w:rPr>'
             '<w:t>%s</w:t></w:r></w:p>' % label) + p
sect = ('<w:sectPr><w:pgSz w:w="16850" w:h="11910"/><w:pgMar w:top="1587" w:right="2098" w:bottom="1474" w:left="1984" '
        'w:header="1134" w:footer="1134" w:gutter="0"/></w:sectPr>')
head = d[:d.find("<w:body>") + 8]
doc = head + body + sect + "</w:body></w:document>"
zo = zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED)
for it in z.infolist():
    data = z.read(it.filename)
    if it.filename == "word/document.xml": data = doc.encode()
    zo.writestr(it, data)
zo.close()
