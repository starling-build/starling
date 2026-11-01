#!/usr/bin/env python3
"""Lab ctdel builder: where Word puts a "Deleted:" balloon's text, and how wide it wraps it. usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
LOREM = ("Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. "
         "Proin pharetra nonummy pede. Mauris et orci. Aenean nec lorem. In porttitor. Donec laoreet nonummy augue.")
A = 'w:id="{i}" w:author="Lab" w:date="2026-01-01T00:00:00Z"'
def ids():
    n = 100
    while True:
        n += 1
        yield n
ID = ids()
def a(): return A.format(i=next(ID))
def vis(text): return f'<w:p><w:r><w:t>{text}</w:t></w:r></w:p>'
def deleted(ppr_inner="", style="", rpr="", mark=True, change=""):
    """a paragraph whose text and mark are tracked-deleted"""
    pst = f'<w:pStyle w:val="{style}"/>' if style else ''
    markdel = f'<w:del {a()}/>' if mark else ''
    return (f'<w:p><w:pPr>{pst}{ppr_inner}<w:rPr>{markdel}</w:rPr>{change}</w:pPr>'
            f'<w:del {a()}><w:r><w:rPr>{rpr}</w:rPr><w:delText xml:space="preserve">{LOREM}</w:delText></w:r></w:del></w:p>')
PPRCHANGE = lambda: f'<w:pPrChange {a()}><w:pPr/></w:pPrChange>'
V = [  # (code, description, deleted paragraph builder)
 ("D1", "CONTROL: Normal paragraph, text and mark deleted",                     lambda: deleted()),
 ("D2", "Quote style (ind 864/864, centred, italic), text and mark deleted",    lambda: deleted(style="Quote")),
 ("D3", "Quote style + a pPrChange (the CT-formatted-deletion shape)",          lambda: deleted(style="Quote", change=PPRCHANGE())),
 ("D4", "Normal + direct indent left/right 864 only",                           lambda: deleted('<w:ind w:left="864" w:right="864"/>')),
 ("D5", "Normal + direct centred only",                                         lambda: deleted('<w:jc w:val="center"/>')),
 ("D6", "Normal + italic runs only",                                            lambda: deleted(rpr='<w:i/>')),
 ("D7", "Normal + a pPrChange only",                                            lambda: deleted(change=PPRCHANGE())),
 ("D8", "Normal + direct indent left 864 only",                                 lambda: deleted('<w:ind w:left="864"/>')),
 ("D9", "Normal + direct indent right 864 only",                                lambda: deleted('<w:ind w:right="864"/>')),
 ("D10", "Quote style, text deleted but the MARK kept",                         lambda: deleted(style="Quote", mark=False)),
 ("D11", "Quote style, VISIBLE (not deleted), with one deleted run inside",
         lambda: ('<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr><w:r><w:t xml:space="preserve">Visible words before </w:t></w:r>'
                  f'<w:del {a()}><w:r><w:delText xml:space="preserve">{LOREM}</w:delText></w:r></w:del><w:r><w:t> and after.</w:t></w:r></w:p>')),
 ("D12", "Normal with a 6pt first-line indent only",                            lambda: deleted('<w:ind w:firstLine="120"/>')),
]
def doc(code, fn):
    body = (vis(f"Before {code}. Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Maecenas porttitor congue massa.")
            + fn() + vis(f"After {code}. Suspendisse dui purus, scelerisque at, vulputate vitae, pretium mattis, nunc."))
    sect = ('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
            'w:header="708" w:footer="708" w:gutter="0"/><w:cols w:space="708"/><w:docGrid w:linePitch="360"/></w:sectPr>')
    document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
    styles = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr>'
              '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="24"/></w:rPr></w:rPrDefault>'
              '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
              '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
              '<w:pPr><w:spacing w:before="200" w:after="160"/><w:ind w:left="864" w:right="864"/><w:jc w:val="center"/></w:pPr><w:rPr><w:i/><w:iCs/></w:rPr></w:style>'
              '</w:styles>')
    settings = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:trackRevisions/><w:compat>'
                '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat></w:settings>')
    return document, styles, settings
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    for n, (code, desc, fn) in enumerate(V, 1):
        d, s, st = doc(code, fn)
        with zipfile.ZipFile(os.path.join(out, f"ctdel-{n:02d}-{code}.docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", d); z.writestr("word/styles.xml", s); z.writestr("word/settings.xml", st)
            z.writestr("word/_rels/document.xml.rels", DRELS)
    print(len(V), "documents in", out)
if __name__ == "__main__":
    main(sys.argv[1])
