#!/usr/bin/env python3
"""Lab sqz7 (Word for Windows, for amd-3): the REAL zh-e0ca7252 paragraph, then variants one change at a time.
Question: Word prints line 1 as  "4.保險期間：自[9 spaces]起至□契約所定履約期限之日止；□" (the last □ stays on the line, justified).
Our engine needs 19.9 pt of squeeze for that against 14 pt of room. sqz6 (synthetic) only kept a symbol 7 pt short. Which feature of the real line allows more?
gen.py OUT_DIR: reads test/corpus/docx/docs/zh-e0ca7252*.docx (styles, settings, section, fonts all real) and writes one docx per variant.
Each file: 16 copies of the paragraph, right indent stepped 0,2,...,30 pt (so the line gets 0..30 pt narrower). Paragraph 1 (right=0) is the original.
Variants: a exact original; b the 9 spaces removed; c justification left (jc left); d spaces removed AND jc left; e spaces not underlined;
f the hanging indent removed (left 1135, hanging 0); g spaces replaced by 9 ideographs 空空空空空空空空空 (same count of cells, no spaces).
Read-out: for each paragraph in each file, does line 1 end with 止； or 止；□  (the last character on line 1)? Report the largest right indent where □ is still on line 1."""
import sys, os, re, glob, zipfile
src = glob.glob(os.path.join(os.path.dirname(__file__), "../../corpus/docx/docs/zh-e0ca7252*.docx"))[0]
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read("word/document.xml").decode("utf8")
ps = [m.start() for m in re.finditer(r'<w:p[ >]', doc)]
P = doc[ps[324]:ps[325]]
assert "保險期間" in P
SP = '<w:t xml:space="preserve">' + " " * 9 + '</w:t>'
assert SP in P
def var(k):
    p = P
    if k in "bd": p = p.replace('<w:r w:rsidR="002C190D" w:rsidRPr="00003E05"><w:rPr><w:rFonts w:ascii="標楷體" w:eastAsia="標楷體" w:hint="eastAsia"/><w:color w:val="000000"/><w:sz w:val="28"/><w:u w:val="single"/></w:rPr>' + SP + '</w:r>', "")
    if k in "cd": p = p.replace('<w:jc w:val="both"/>', '<w:jc w:val="left"/>')
    if k == "e": p = p.replace('<w:u w:val="single"/>', "")
    if k == "f": p = p.replace('w:hanging="284"', 'w:hanging="0"')
    if k == "g": p = p.replace(SP, '<w:t>空空空空空空空空空</w:t>')
    return p
for k in "abcdefg":
    ps_ = []
    for i in range(16):
        r = i * 40  # twips, 2pt steps
        p = var(k).replace('<w:ind w:left="1135" w:hanging="%s"/>' % ("0" if k == "f" else "284"),
                           '<w:ind w:left="1135" w:right="%d" w:hanging="%s"/>' % (r, "0" if k == "f" else "284"))
        assert 'w:right="%d"' % r in p
        ps_.append(p)
    sect = re.findall(r'<w:sectPr(?:(?!<w:sectPr).)*?</w:sectPr>', doc, re.S)[-1]
    head = doc[:doc.index("<w:body>") + 8]
    new = head + "".join(ps_) + sect + "</w:body></w:document>"
    with zipfile.ZipFile(os.path.join(out, "sqz7-%s.docx" % k), "w", zipfile.ZIP_DEFLATED) as o:
        for it in z.infolist():
            o.writestr(it.filename, new.encode("utf8") if it.filename == "word/document.xml" else z.read(it.filename))
print("ok", out)
