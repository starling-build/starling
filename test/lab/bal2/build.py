#!/usr/bin/env python3
"""Lab bal3 builder (Windows 01QbbApP, for lenovo-5): balloons for a paragraph with deleted text + 3 reformatted stretches (lo-9f27ef4097b11c63 para 22).
Reformat = rPrChange, old rPr EMPTY -> new Arial 9pt (docDefaults here are Times New Roman 12, so the change is a real font+size change).
usage: build.py OUTDIR   -> OUTDIR/b3a..b3d.docx"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
A = 'w:author="Lab" w:date="2026-11-02T10:00:00Z"'
n = [100]
def i():
    n[0] += 1; return str(n[0])
NEW = '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="18"/><w:szCs w:val="18"/>'
def plain(t): return f'<w:r><w:t xml:space="preserve">{t}</w:t></w:r>'
def dele(t): return f'<w:del w:id="{i()}" {A}><w:r><w:delText xml:space="preserve">{t}</w:delText></w:r></w:del>'
def fmt(t): return f'<w:r><w:rPr>{NEW}<w:rPrChange w:id="{i()}" {A}><w:rPr/></w:rPrChange></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r>'
def p(*parts, mark=None, pchg=False):
    m = ''
    if mark == 'del': m += f'<w:del w:id="{i()}" {A}/>'
    pc = f'<w:pPrChange w:id="{i()}" {A}><w:pPr><w:jc w:val="left"/></w:pPr></w:pPrChange>' if pchg else ''
    jc = '<w:jc w:val="center"/>' if pchg else ''
    return f'<w:p><w:pPr>{jc}<w:rPr>{m}</w:rPr>{pc}</w:pPr>{"".join(parts)}</w:p>'
L = lambda k: p(plain(f"LINE {k} plain text before or after the test paragraph, ordinary Times New Roman."))
SEP = " Unchanged words between the stretches so that it wraps over a few lines of the page. "
def sep(k): return plain(f"Plain{k}{SEP}")
def para_a(tag=''):  # deleted text + 3 stretches separated by plain text
    return p(plain(f"{tag}Start. "), dele("DELETED-TEXT one two three "), fmt("FMT-ONE stretch"), sep(1), fmt("FMT-TWO stretch"), sep(2), fmt("FMT-THREE stretch"), plain(" end of paragraph."))
def para_b(tag=''):  # adjacent
    return p(plain(f"{tag}Start. "), dele("DELETED-TEXT one two three "), fmt("FMT-ONE "), fmt("FMT-TWO "), fmt("FMT-THREE"), plain(" end of paragraph. " + SEP * 2))
DM = lambda: p(plain("DELMARK-"), mark='del', pchg=True)
V = [
 ("b3a", [L(1), L(2), para_a(), L(3), L(4)]),
 ("b3b", [L(1), L(2), para_b(), L(3), L(4)]),
 ("b3c", [L(1), L(2), DM(), para_a(), DM(), L(3), L(4)]),
 ("b3d", [L(1), L(2), para_a("P1 "), para_a("P2 "), L(3), L(4)]),
]
def doc(body):
    sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{"".join(body)}{sect}</w:body></w:document>'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
SET = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:trackRevisions/></w:settings>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
def main(out):
    os.makedirs(out, exist_ok=True)
    for code, body in V:
        with zipfile.ZipFile(os.path.join(out, code + ".docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", doc(body)); z.writestr("word/styles.xml", STYLES)
            z.writestr("word/settings.xml", SET); z.writestr("word/_rels/document.xml.rels", DRELS)
    print(len(V), "documents in", out)
if __name__ == "__main__": main(sys.argv[1])
