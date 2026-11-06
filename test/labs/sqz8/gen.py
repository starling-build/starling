#!/usr/bin/env python3
"""Lab sqz8 (Word for Windows, for amd-3): follow-up to sqz7. In the REAL zh-e0ca7252 line (9 underlined spaces after 自) Word keeps the
last "□" on line 1 at every right indent 0..30 pt (sqz7 a/c/e/f); with the 9 spaces replaced by 9 ideographs it never does. Our engine needs 19.9pt
of squeeze there. So the spaces give squeeze room. How much, and which spaces/marks?
gen.py OUT_DIR: 5 files, each 21 copies of the paragraph, right indent stepped 0,4,...,80 pt (left-aligned paragraphs: jc left, so only fit is tested).
a original (9 spaces); h 4 spaces; i 18 spaces; j the colon "：" after 期間 removed; k the middle "□" (起至□契約) removed.
Read-out: per paragraph, does line 1 end with 止；□ or 止；(or earlier)? Report the largest right indent with □ on line 1, per file."""
import sys, os, re, glob, zipfile
src = glob.glob(os.path.join(os.path.dirname(__file__), "../../corpus/docx/docs/zh-e0ca7252*.docx"))[0]
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read("word/document.xml").decode("utf8")
ps = [m.start() for m in re.finditer(r'<w:p[ >]', doc)]
P = doc[ps[324]:ps[325]].replace('<w:jc w:val="both"/>', '<w:jc w:val="left"/>')
SP = " " * 9
assert SP in P and "：自" in P and "起至□契約" in P
V = {"a": P, "h": P.replace(SP, " " * 4), "i": P.replace(SP, " " * 18), "j": P.replace("：自", "自"), "k": P.replace("起至□契約", "起至契約")}
sect = re.findall(r'<w:sectPr(?:(?!<w:sectPr).)*?</w:sectPr>', doc, re.S)[-1]
head = doc[:doc.index("<w:body>") + 8]
for k, p0 in V.items():
    body = ""
    for i in range(21):
        r = i * 80
        p = p0.replace('<w:ind w:left="1135" w:hanging="284"/>', '<w:ind w:left="1135" w:right="%d" w:hanging="284"/>' % r)
        assert 'w:right="%d"' % r in p
        body += p
    new = head + body + sect + "</w:body></w:document>"
    with zipfile.ZipFile(os.path.join(out, "sqz8-%s.docx" % k), "w", zipfile.ZIP_DEFLATED) as o:
        for it in z.infolist():
            o.writestr(it.filename, new.encode("utf8") if it.filename == "word/document.xml" else z.read(it.filename))
print("ok")
