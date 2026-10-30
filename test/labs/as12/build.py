# build.py REPO OUTDIR — lab as12: is the automatic space between digits and an ideograph 7.0 (half an em at 14pt) in Word for
# Windows, as zh-12db188f's print shows, or the usual quarter (3.5)? And does "（一）" stay whole there?
#
# zh-12db188f p3, a 14pt cell paragraph (list item, hanging 624, cell text width 4264 twips, TNR digits, 標楷體 ideographs,
# mode 15, balanceSingleByteDoubleByteWidth on, compressPunctuation): Word's second line is "社（一）字第89067628 號函"; there
#   （ 14.04 | 一 14.04 | ） 14.04 | 字 13.9 | 第 14.04 | gap 7.0 | 8 9 0 6 7 6 2 8 (7.02 each) | gap 6.94 | 號 函
# so the brackets are whole and the two automatic spaces are 7.0. Ours sets （ and ） at 7.0 each (squeezed) and the spaces
# at 3.5, so its line takes "釋，" Word sends down. The same balance flag with 15pt 仿宋_GB2312 digits (zh-8415d258, mode 12)
# gives 3.75 (a quarter). Which of mode, face, balance, cell/body, brackets decides?
#
# One document per (mode, balance, face); every document holds the same six paragraphs, all list items of the original's
# numbering (numId 26, hanging 624) at 14pt, justified:
#   A1/A2  body, wide (no wrapping): the short text, with / without "（一）" — reads the gaps with nothing squeezed
#   B1/B2  body, 4264 twips of text (right indent 6169): the full text, with / without "（一）" — where the lines break
#   C1/C2  a one-cell table, cell 4320 twips, margins 28: the full text, with / without "（一）" — the original's situation
# mode 12 / 14 / 15; balance on / off (w:balanceSingleByteDoubleByteWidth); face
#   a TNR digits + 標楷體 ideographs (the original)   b TNR + 宋体   c 標楷體 for both (digits in the ideograph face)
# -> 18 documents as-<mode>-<bal>-<face>.docx ("on"/"off"). The control is as-15-on-a: it should print what Word printed.
import re, sys, os, zipfile
repo, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
docs = os.path.join(repo, "test/corpus/docx/docs")
src = next(os.path.join(docs, f) for f in os.listdir(docs) if f.startswith("zh-12db188f"))
z = zipfile.ZipFile(src)
data = {nm: z.read(nm) for nm in z.namelist()}
doc = data["word/document.xml"].decode("utf-8")
st = data["word/settings.xml"].decode("utf-8")
head = doc[:doc.index("<w:body>") + 8]
sect = re.findall(r"<w:sectPr[ >].*?</w:sectPr>", doc, re.S)[-1]
LONG = "依教育部89年6月13日台89社（一）字第89067628號函釋，於88年6月16日「補習及進修教育法」修正公布前，專科進修補習學校結業並未取得資格證明書者，不具有專科學校畢業同等資格。"
SHORT = "台89社（一）字第89067628號函釋，於88年6月16日"
FACES = {"a": ("Times New Roman", "標楷體"), "b": ("Times New Roman", "宋体"), "c": ("標楷體", "標楷體")}
def para(text, face, right=0):
    asc, ea = FACES[face]
    rpr = ('<w:rPr><w:rFonts w:ascii="%s" w:hAnsi="%s" w:eastAsia="%s"/><w:kern w:val="2"/><w:sz w:val="28"/><w:szCs w:val="24"/></w:rPr>' % (asc, asc, ea))
    ind = '<w:ind w:leftChars="0" w:left="624" w:right="%d" w:hanging="624"/>' % right if right else '<w:ind w:leftChars="0" w:left="624" w:hanging="624"/>'
    return ('<w:p><w:pPr><w:pStyle w:val="ad"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="26"/></w:numPr><w:adjustRightInd/>'
            '<w:spacing w:line="240" w:lineRule="auto"/>%s<w:jc w:val="both"/><w:textAlignment w:val="auto"/></w:pPr>'
            '<w:r>%s<w:t>%s</w:t></w:r></w:p>' % (ind, rpr, text))
def plain(text):  # a label paragraph, to name each block in the print
    return '<w:p><w:pPr><w:spacing w:before="120"/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>%s</w:t></w:r></w:p>' % text
def cell_table(paras):
    rows = "".join('<w:tr><w:tc><w:tcPr><w:tcW w:w="4320" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr>' % p for p in paras)
    return ('<w:tbl><w:tblPr><w:tblW w:w="4320" w:type="dxa"/><w:tblInd w:w="0" w:type="dxa"/>'
            '<w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders><w:tblLayout w:type="fixed"/>'
            '<w:tblCellMar><w:left w:w="28" w:type="dxa"/><w:right w:w="28" w:type="dxa"/></w:tblCellMar></w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="4320"/></w:tblGrid>%s</w:tbl>' % rows)
def nobr(t): return t.replace("（一）", "一")
n = 0
for mode in (12, 14, 15):
    for bal in ("on", "off"):
        for face in "abc":
            s = st
            s = re.sub(r'(w:name="compatibilityMode"[^>]*w:val=")\d+', r"\g<1>%d" % mode, s)
            s = s.replace("<w:balanceSingleByteDoubleByteWidth/>", "")
            if bal == "on":
                s = s.replace("<w:compat>", "<w:compat><w:balanceSingleByteDoubleByteWidth/>", 1)
            body = (plain("A1 wide, with brackets") + para(SHORT, face) + plain("A2 wide, no brackets") + para(nobr(SHORT), face)
                    + plain("B1 narrow body, with brackets") + para(LONG, face, 6169) + plain("B2 narrow body, no brackets") + para(nobr(LONG), face, 6169)
                    + plain("C1 cell, with brackets") + cell_table([para(LONG, face)]) + plain("C2 cell, no brackets") + cell_table([para(nobr(LONG), face)]))
            d = head + body + sect + "</w:body></w:document>"
            name = "as-%d-%s-%s.docx" % (mode, bal, face)
            with zipfile.ZipFile(os.path.join(out, name), "w", zipfile.ZIP_DEFLATED) as zo:
                for nm, b in data.items():
                    if nm == "word/document.xml": b = d.encode("utf-8")
                    elif nm == "word/settings.xml": b = s.encode("utf-8")
                    zo.writestr(nm, b)
            n += 1
print(n, "documents in", out)
