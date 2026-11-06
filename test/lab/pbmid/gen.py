# lab pbmid (for amd-perf): a MID-PAGE page break. N text lines ('line i'), then a paragraph whose FIRST run is a page break followed by 'x'.
# Variants: sh = shaded CCE5FF + box border + spacing before 60pt (like sbox b2) | pl = plain, spacing before 60pt | nb = shaded + box, no spacing before.
# N = 1, 5, 20 lines before. Each in compat 14 and 15. Question: what Word paints on page 1 for the pre-break fragment (strip of shade/border?) and where the box top is on page 2.
# gen.py OUTDIR
# lab sbox (for amd-perf): a paragraph with spacing before 60pt, shading CCE5FF and a box border (sz 24, top/bottom space 1, left/right space 4), text "x".
# Cases: a first paragraph | b1 after a page break held by the previous paragraph (b1e: previous empty, b1t: previous has text) | b2 the break is the first run of the paragraph itself
# | c1 after a column break (c1e/c1t) in 2 columns | c2 top of column 2 by flow | d first on page 2 by natural overflow | e after a nextPage section break (ee/et).
# Each in compat 14 and 15 (suffix -14/-15); cs0 = contextualSpacing val=0 explicit on the paragraph (compat 15 only).
# gen.py OUTDIR
import sys, os, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pkg
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
def compat(m): return '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="%d"/></w:compat>' % m
def PBDR(): return '<w:pBdr>' + ''.join('<w:%s w:val="single" w:sz="24" w:space="%d" w:color="000000"/>' % (s, 1 if s in ('top', 'bottom') else 4) for s in ('top', 'left', 'bottom', 'right')) + '</w:pBdr>'
def P(cs0=False): return '<w:p><w:pPr>%s<w:shd w:val="clear" w:color="auto" w:fill="CCE5FF"/><w:spacing w:before="1200"/>%s</w:pPr><w:r><w:t>x</w:t></w:r></w:p>' % (PBDR(), '<w:contextualSpacing w:val="0"/>' if cs0 else '')
def plain(t='', extra=''): return '<w:p><w:r>%s%s</w:r></w:p>' % (extra, '<w:t>%s</w:t>' % t if t else '')
PB = '<w:br w:type="page"/>'; CB = '<w:br w:type="column"/>'
NEXT = '<w:p><w:pPr><w:sectPr><w:type w:val="nextPage"/><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:pPr>%s</w:p>'
def cols(n): return '<w:cols w:num="%d" w:space="720"/>' % n

def Q(var):
    sh = '<w:shd w:val="clear" w:color="auto" w:fill="CCE5FF"/>'
    bd = PBDR()
    sp = '<w:spacing w:before="1200"/>'
    ppr = {'sh': bd + sh + sp, 'pl': sp, 'nb': bd + sh}[var]
    return '<w:p><w:pPr>%s</w:pPr><w:r><w:br w:type="page"/><w:t>x</w:t></w:r></w:p>' % ppr
def build(name, n, var, mode):
    b = ''.join(plain('line %d' % i) for i in range(1, n + 1)) + Q(var)
    sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
    d = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (pkg.NS, b, sect)
    st = pkg.settings(False, 0).replace('</w:settings>', compat(mode) + '</w:settings>')
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', pkg.CT); z.writestr('_rels/.rels', pkg.RELS); z.writestr('word/document.xml', d)
        z.writestr('word/styles.xml', pkg.STYLES); z.writestr('word/_rels/document.xml.rels', pkg.DRELS); z.writestr('word/settings.xml', st)
k = 0
for n in (1, 5, 20):
    for var in ('sh', 'pl', 'nb'):
        for m in (14, 15): build('n%d-%s-%d' % (n, var, m), n, var, m); k += 1
print(k, 'docs')
