#!/usr/bin/env python3
"""Lab bal3 overflow (Windows 01QbbApP, for lenovo-5): balloon overflow with a change on EVERY line.
Minimal package (Times New Roman 12, Letter, 1in margins, spacing after 0, trackRevisions), one-line paragraphs.
Line k cycles: k%3==0 'Deleted: word' (w:del), 1 rPrChange (sz 18 only), 2 pPrChange (jc center, old left).
usage: build.py OUTDIR -> ov1.docx (40 lines, 1 page), ov3.docx (3 pages x 40 changed lines),
       ov3s.docx (3 pages x 40 lines, only every 3rd line changed = 40 changes spread over 3 pages),
       ov2.docx (1 page, 40 lines, two changes per line: del + rPrChange)"""
import sys, os, zipfile
NS = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
A = 'w:author="Lab" w:date="2026-11-02T10:00:00Z"'
n = [100]
def i():
    n[0] += 1; return str(n[0])
def plain(t): return f'<w:r><w:t xml:space="preserve">{t}</w:t></w:r>'
def dele(t): return f'<w:del w:id="{i()}" {A}><w:r><w:delText xml:space="preserve">{t}</w:delText></w:r></w:del>'
def fmt(t): return f'<w:r><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/><w:rPrChange w:id="{i()}" {A}><w:rPr/></w:rPrChange></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r>'
def para(k, kind, pg=False):
    ppr = '<w:pageBreakBefore/>' if pg else ''
    body = plain(f'L{k:03d} ordinary text of the line ')
    if kind == 'del': body += dele(f'gone{k} ') + plain('and the rest.')
    elif kind == 'fmt': body += fmt(f'small{k}') + plain(' and the rest.')
    elif kind == 'ppr':
        ppr += '<w:jc w:val="center"/>'
        body += plain('and the rest.')
    elif kind == 'both': body += dele(f'gone{k} ') + fmt(f'small{k}') + plain(' and the rest.')
    else: body += plain('and the rest.')
    pc = f'<w:pPrChange w:id="{i()}" {A}><w:pPr><w:jc w:val="left"/></w:pPr></w:pPrChange>' if kind == 'ppr' else ''
    return f'<w:p><w:pPr>{ppr}<w:spacing w:after="0"/>{pc}</w:pPr>{body}</w:p>'
K = ['del', 'fmt', 'ppr']
def page(first, kinds, pg):
    return ''.join(para(first + j, kinds(j), pg and j == 0) for j in range(40))
def doc(body):
    sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
SET = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:trackRevisions/></w:settings>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
V = {
 'ov1': page(0, lambda j: K[j % 3], False),
 'ov2': page(0, lambda j: 'both', False),
 'ov3': ''.join(page(40 * p, lambda j: K[j % 3], p > 0) for p in range(3)),
 'ov3s': ''.join(page(40 * p, lambda j: K[(j // 3) % 3] if j % 3 == 0 else '', p > 0) for p in range(3)),
}
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for code, body in V.items():
    with zipfile.ZipFile(os.path.join(out, code + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/document.xml', doc(body)); z.writestr('word/styles.xml', STYLES)
        z.writestr('word/settings.xml', SET); z.writestr('word/_rels/document.xml.rels', DRELS)
print(len(V), 'docs')
