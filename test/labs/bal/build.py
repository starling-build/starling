#!/usr/bin/env python3
"""Lab bal builder: Word's markup balloons -- a deleted section break, a deleted mark that keeps inserted text, two balloons at one anchor, runs of reformatted marks. usage: build.py OUTDIR"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
A = 'w:author="Lab" w:date="2026-11-02T10:00:00Z"'
n = [100]
def i():
    n[0] += 1; return str(n[0])
RP = '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="18"/>'
def run(t): return f'<w:r><w:rPr>{RP}</w:rPr><w:t xml:space="preserve">{t}</w:t></w:r>'
def dele(t): return f'<w:del w:id="{i()}" {A}><w:r><w:rPr>{RP}</w:rPr><w:delText xml:space="preserve">{t}</w:delText></w:r></w:del>'
def ins(t): return f'<w:ins w:id="{i()}" {A}><w:r><w:rPr>{RP}</w:rPr><w:t xml:space="preserve">{t}</w:t></w:r></w:ins>'
def fmt(t): return f'<w:r><w:rPr>{RP}<w:b/><w:rPrChange w:id="{i()}" {A}><w:rPr>{RP}</w:rPr></w:rPrChange></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r>'
def comment(t, cid): return f'<w:commentRangeStart w:id="{cid}"/>{run(t)}<w:commentRangeEnd w:id="{cid}"/><w:r><w:commentReference w:id="{cid}"/></w:r>'
def p(*parts, mark=None, sect=None, markfmt=False):
    m = ''
    if mark == 'del': m += f'<w:del w:id="{i()}" {A}/>'
    if mark == 'ins': m += f'<w:ins w:id="{i()}" {A}/>'
    m += RP
    if markfmt: m += f'<w:b/><w:rPrChange w:id="{i()}" {A}><w:rPr>{RP}</w:rPr></w:rPrChange>'
    s = ''
    if sect: s = '<w:sectPr>' + ('<w:type w:val="continuous"/>' if sect == 'cont' else '') + '<w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<w:p><w:pPr><w:rPr>{m}</w:rPr>{s}</w:pPr>{"".join(parts)}</w:p>'
L = lambda k: run(f"LINE {k} plain text of the paragraph.")
V = [
 ("del-text-mark",      [L(1), p(dele("XXX"), mark='del'), L(2), L(3)]),
 ("del-sect-cont",      [L(1), p(mark='del', sect='cont'), L(2), L(3)]),
 ("del-text-then-sect", [L(1), p(dele("XXX"), mark='del'), p(mark='del', sect='cont'), L(2), L(3)]),
 ("del-sect-next",      [L(1), p(mark='del', sect='next'), L(2), L(3)]),
 ("del-mark-ins-text",  [L(1), p(ins("INSERTED TEXT KEPT"), mark='del'), L(2), L(3)]),
 ("del-and-fmt-same",   [L(1), p(run("Before "), dele("DELETED"), fmt("FORMATTED"), run(" after")), L(2), L(3)]),
 ("fmt-then-del-same",  [L(1), p(run("Before "), fmt("FORMATTED"), dele("DELETED"), run(" after")), L(2), L(3)]),
 ("comment-and-del",    [L(1), p(run("Before "), comment("COMMENTED", 0), dele("DELETED"), run(" after")), L(2), L(3)]),
 ("del-and-comment",    [L(1), p(run("Before "), dele("DELETED"), comment("COMMENTED", 0), run(" after")), L(2), L(3)]),
 ("marks-fmt-x4",       [L(1)] + [p(fmt(f"HEADING {k}"), markfmt=True) for k in range(4)] + [L(2), L(3)]),
 ("marks-fmt-x2-gap",   [L(1), p(fmt("HEADING A"), markfmt=True), p(run("plain between")), p(fmt("HEADING B"), markfmt=True), L(2)]),
 ("fmt-only-run-then-mark", [L(1), p(fmt("HEADING A"), markfmt=True), L(2)]),
]
COMMENTS = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:comments {NS}><w:comment w:id="0" w:author="Lab" w:date="2026-11-02T10:00:00Z" w:initials="L"><w:p><w:r><w:t>A comment.</w:t></w:r></w:p></w:comment></w:comments>'
def doc(body):
    sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{"".join(body)}{sect}</w:body></w:document>'
STYLES = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="18"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/></Relationships>')
def main(out):
    os.makedirs(out, exist_ok=True)
    for k, (code, body) in enumerate(V, 1):
        with zipfile.ZipFile(os.path.join(out, f"bal-{k:02d}-{code}.docx"), "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
            z.writestr("word/document.xml", doc(body)); z.writestr("word/styles.xml", STYLES)
            z.writestr("word/comments.xml", COMMENTS); z.writestr("word/_rels/document.xml.rels", DRELS)
    print(len(V), "documents in", out)
if __name__ == "__main__": main(sys.argv[1])
