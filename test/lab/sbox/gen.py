# lab sbox (for amd-perf): a paragraph with spacing before 60pt, shading CCE5FF and a box border (sz 24, top/bottom space 1, left/right space 4), text "x".
# Cases: a first paragraph | b1 after a page break held by the previous paragraph (b1e: previous empty, b1t: previous has text) | b2 the break is the first run of the paragraph itself
# | c1 after a column break (c1e/c1t) in 2 columns | c2 top of column 2 by flow | d first on page 2 by natural overflow | e after a nextPage section break (ee/et).
# Each in compat 14 and 15 (suffix -14/-15); cs0 = contextualSpacing val=0 explicit on the paragraph (compat 15 only).
# gen.py OUTDIR
import sys, os, zipfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sqz'))
import pkg
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
def compat(m): return '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="%d"/></w:compat>' % m
def PBDR(): return '<w:pBdr>' + ''.join('<w:%s w:val="single" w:sz="24" w:space="%d" w:color="000000"/>' % (s, 1 if s in ('top', 'bottom') else 4) for s in ('top', 'left', 'bottom', 'right')) + '</w:pBdr>'
def P(cs0=False): return '<w:p><w:pPr>%s<w:shd w:val="clear" w:color="auto" w:fill="CCE5FF"/><w:spacing w:before="1200"/>%s</w:pPr><w:r><w:t>x</w:t></w:r></w:p>' % (PBDR(), '<w:contextualSpacing w:val="0"/>' if cs0 else '')
def plain(t='', extra=''): return '<w:p><w:r>%s%s</w:r></w:p>' % (extra, '<w:t>%s</w:t>' % t if t else '')
PB = '<w:br w:type="page"/>'; CB = '<w:br w:type="column"/>'
NEXT = '<w:p><w:pPr><w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:pPr>%s</w:p>'
def cols(n): return '<w:cols w:num="%d" w:space="720"/>' % n
def body(case, cs0):
    p = P(cs0)
    if case == 'a': return p, 1
    if case == 'b1e': return plain('', PB) + p, 1
    if case == 'b1t': return plain('prev', PB) + p, 1
    if case == 'b2': return '<w:p><w:pPr>%s<w:shd w:val="clear" w:color="auto" w:fill="CCE5FF"/><w:spacing w:before="1200"/></w:pPr><w:r>%s<w:t>x</w:t></w:r></w:p>' % (PBDR(), PB), 1
    if case in ('c1e', 'c1t'): return (plain('' if case == 'c1e' else 'prev', CB) + p), 2
    if case == 'c2': return ''.join(plain('line %d' % i) for i in range(1, 51)) + p, 2
    if case == 'd': return ''.join(plain('line %d' % i) for i in range(1, 51)) + p, 1
    if case in ('ee', 'et'): return (NEXT % ('<w:r><w:t>prev</w:t></w:r>' if case == 'et' else '')) + p, 1
    raise SystemExit(case)
def build(name, case, mode, cs0=False):
    b, nc = body(case, cs0)
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>%s</w:sectPr>' % (cols(nc) if nc > 1 else '')
    d = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (pkg.NS, b, sect)
    st = pkg.settings(False, 0).replace('</w:settings>', compat(mode) + '</w:settings>')
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', pkg.CT); z.writestr('_rels/.rels', pkg.RELS); z.writestr('word/document.xml', d)
        z.writestr('word/styles.xml', pkg.STYLES); z.writestr('word/_rels/document.xml.rels', pkg.DRELS); z.writestr('word/settings.xml', st)
CASES = ['a', 'b1e', 'b1t', 'b2', 'c1e', 'c1t', 'c2', 'd', 'ee', 'et']
n = 0
for c in CASES:
    for m in (14, 15): build('%s-%d' % (c, m), c, m); n += 1
for c in CASES: build('%s-cs0' % c, c, 15, True); n += 1
print(n, 'docs')
