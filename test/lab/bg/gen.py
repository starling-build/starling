# lab bg (for amd-perf): w:background variants, with/without <w:displayBackgroundShape/>. gen.py OUTDIR
import sys, os, zipfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'sqz'))
import pkg
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
NSA = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
def clr(n, v): return '<a:%s><a:srgbClr val="%s"/></a:%s>' % (n, v, n)
THEME = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme %s name="Office Theme"><a:themeElements><a:clrScheme name="Office">' % NSA
  + clr('dk1','000000') + clr('lt1','FFFFFF') + clr('dk2','44546A') + clr('lt2','E7E6E6') + clr('accent1','4472C4') + clr('accent2','ED7D31')
  + clr('accent3','A5A5A5') + clr('accent4','FFC000') + clr('accent5','5B9BD5') + clr('accent6','70AD47') + clr('hlink','0563C1') + clr('folHlink','954F72')
  + '</a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
  '<a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
  '<a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>'
  '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
  '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>')
V = {
 'v1': 'w:color="FFFFFF" w:themeColor="accent2"',
 'v2': 'w:color="FFFFFF" w:themeColor="accent2" w:themeTint="66"',
 'v3': 'w:color="FFFFFF" w:themeColor="accent2" w:themeShade="BF"',
 'v4': 'w:color="FFFFFF" w:themeColor="accent2" w:themeTint="99" w:themeShade="BF"',
 'v5a': 'w:color="FFFFFF" w:themeColor="text2"',
 'v5b': 'w:color="FFFFFF" w:themeColor="background2"',
 'v5c': 'w:color="FFFFFF" w:themeColor="accent5"',
 'v6': 'w:color="FF0000" w:themeColor="accent2"',
 'v7': 'w:color="FFCC99"',
}
def build(name, attrs, dbs):
    body = '<w:p><w:r><w:t>x</w:t></w:r></w:p>'
    d = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:background %s/><w:body>%s%s</w:body></w:document>' % (pkg.NS, attrs, body, pkg.SECT)
    st = pkg.settings(False, 0)
    if dbs: st = st.replace('<w:autoHyphenation', '<w:displayBackgroundShape/><w:autoHyphenation')
    ct = pkg.CT.replace('</Types>', '<Override PartName="/word/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/></Types>')
    dr = pkg.DRELS.replace('</Relationships>', '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/></Relationships>')
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', ct); z.writestr('_rels/.rels', pkg.RELS); z.writestr('word/document.xml', d)
        z.writestr('word/styles.xml', pkg.STYLES); z.writestr('word/_rels/document.xml.rels', dr); z.writestr('word/settings.xml', st); z.writestr('word/theme/theme1.xml', THEME)
for k, a in V.items():
    build(k + 'on', a, True); build(k + 'off', a, False)
print(len(V) * 2, 'docs')
