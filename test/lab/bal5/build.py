#!/usr/bin/env python3
"""(helpers copied from bal3o) Lab bal5 (Windows 01QbbApP, for lenovo-5): do two rPrChange stretches share a Formatted balloon when only an ins/del lies between? cases a-f, one paragraph each.
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

def insr(t, rpc=False): 
    rp = f'<w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/><w:rPrChange w:id="{i()}" {A}><w:rPr/></w:rPrChange></w:rPr>' if rpc else ''
    return f'<w:ins w:id="{i()}" {A}><w:r>{rp}<w:t xml:space="preserve">{t}</w:t></w:r></w:ins>'
def delr(t, rpc=False):
    rp = f'<w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/><w:rPrChange w:id="{i()}" {A}><w:rPr/></w:rPrChange></w:rPr>' if rpc else ''
    return f'<w:del w:id="{i()}" {A}><w:r>{rp}<w:delText xml:space="preserve">{t}</w:delText></w:r></w:del>'
SZ = '<w:sz w:val="18"/><w:szCs w:val="18"/>'
def tok(kind, k):
    if kind == 'F': return fmt(f'F{k} ')
    if kind == 'I': return f'<w:ins w:id="{i()}" {A}><w:r><w:rPr>{SZ}</w:rPr><w:t xml:space="preserve">I{k} </w:t></w:r></w:ins>'
    return f'<w:del w:id="{i()}" {A}><w:r><w:rPr>{SZ}<w:rPrChange w:id="{i()}" {A}><w:rPr/></w:rPrChange></w:rPr><w:delText xml:space="preserve">D{k} </w:delText></w:r></w:del>'
def cnt(seq):
    n = {}
    for c in seq.split():
        n[c] = n.get(c, 0) + 1; yield c, n[c]
def P(seq):
    return '<w:p><w:pPr><w:spacing w:after="0"/></w:pPr>' + plain('Before. ') + ''.join(tok(c, n) for c, n in cnt(seq)) + plain('After.') + '</w:p>'
SEQ = {'a': 'F I D I I I D I F', 'b': 'F I D D D D D I I D F', 'c': 'F I F', 'd': 'F I D F', 'e': 'F D I F',
       'f': 'F I D I I I D I F I D D D D D I I D F'}
V = {k: P(v) for k, v in SEQ.items()}
def doc(body):
    sect = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {NS}><w:body>{body}{sect}</w:body></w:document>'
STYLES = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles {NS}><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman"/><w:sz w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>'
SET = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings {NS}><w:trackRevisions/></w:settings>'
CT = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>'
RELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
DRELS = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>'
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for code, body in V.items():
    with zipfile.ZipFile(os.path.join(out, code + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/document.xml', doc(body)); z.writestr('word/styles.xml', STYLES)
        z.writestr('word/settings.xml', SET); z.writestr('word/_rels/document.xml.rels', DRELS)
print(len(V), 'docs')
