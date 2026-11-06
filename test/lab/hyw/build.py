#!/usr/bin/env python3
"""Lab hyw (for Windows, from lenovo-2): where Word's English automatic hyphenation parts each word.
lo-a594fa6b's prints part "Na-tions" and "na-tions" (two letters before the hyphen) but keep "re-alization", "mea-sures" and
"pun-ishment" whole, where our en-US patterns (min 3) differ in six lines. For every word of that document of five letters or
more, one paragraph PER candidate break k (2..n-2 letters before the hyphen), set alone in 12pt Times New Roman, left aligned,
with a right indent that leaves room for exactly the first k letters and a hyphen (not k+1): Word parts the word at the last
valid break <= k, so the first line of each paragraph says whether k is a break and, if not, which earlier one is.
usage: build.py SOURCE.docx OUT.docx  -> OUT.docx, OUT.tsv (index, word, k) in print order."""
import sys, re, zipfile
from fontTools.ttLib import TTFont
src, out = sys.argv[1:3]
z = zipfile.ZipFile(src)
text = re.sub(r'<[^>]+>', ' ', z.read('word/document.xml').decode())
words = sorted({w.lower() for w in re.findall(r"[A-Za-z]{5,}", text)})
f = TTFont('/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf')
cmap, hmtx, upm = f.getBestCmap(), f['hmtx'], f['head'].unitsPerEm
adv = lambda c: hmtx[cmap[ord(c)]][0] * 12 / upm
TEXT_W = 595.3 - 144.0
paras, rows = [], []
for w in words:
    for k in range(2, len(w) - 1):
        lo = sum(adv(c) for c in w[:k]) + adv('-')
        hi = sum(adv(c) for c in w[:k + 1]) + adv('-')
        room = (lo + hi) / 2
        right = round((TEXT_W - room) * 20)
        paras.append('<w:p><w:pPr><w:keepLines/><w:spacing w:before="0" w:after="160" w:line="240" w:lineRule="auto"/><w:ind w:left="0" w:right="%d"/></w:pPr>'
                     '<w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="24"/><w:lang w:val="en-US"/></w:rPr>'
                     '<w:t>%s</w:t></w:r></w:p>' % (right, w))
        rows.append((len(rows), w, k))
ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s'
       '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>') % (ns, ''.join(paras))
settings = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:autoHyphenation w:val="true"/><w:hyphenationZone w:val="0"/><w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>' % ns
styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:sz w:val="24"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % ns
ct = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
drels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as o:
    for n, b in [('[Content_Types].xml', ct), ('_rels/.rels', rels), ('word/document.xml', doc), ('word/_rels/document.xml.rels', drels), ('word/styles.xml', styles), ('word/settings.xml', settings)]:
        o.writestr(n, b)
open(out.replace('.docx', '.tsv'), 'w').write('\n'.join('%d\t%s\t%d' % r for r in rows) + '\n')
print(len(words), 'words', len(rows), 'paragraphs')
