# -*- coding: utf-8 -*-
"""Lab gothface (Windows 01QbbApP, for amd-3): which chars Word draws in MS Gothic vs Microsoft JhengHei, zh-5450d509 package, 12pt.
Docs gf_fs (eastAsia/ascii 仿宋_GB2312), gf_song (宋体), gf_jh (微軟正黑體), gf_jh2 (Microsoft JhengHei): page 1 = the paragraph in context (pStyle 5, line 360, hint eastAsia run),
page 2 = every char of it alone in its own table cell paragraph (28 columns, row-major in text order).  usage: mkface.py OUT (cwd lab/goth)"""
import zipfile, os, sys, re
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile('orig.docx')
f = {n: z.read(n) for n in z.namelist() if not n.endswith('/')}
d = f['word/document.xml'].decode('utf-8')
bs = d.index('<w:body>') + len('<w:body>')
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', d, re.S)[-1]
head = d[:bs]
TEXT = '部署，为推动全国食品药品监管领域基层政务公开标准化规范化，提升基层政务公开和政务服务水平，在总结各县（区、市）市场监管部门试点经验的基础上，特编制《食品药品监管领域基层政务公开标准指引》（以下简称《指引》）。'
COLS = 28
CFG = {'gf_fs': '仿宋_GB2312', 'gf_song': '宋体', 'gf_jh': '微軟正黑體', 'gf_jh2': 'Microsoft JhengHei', 'gf_nh': '仿宋_GB2312'}
NOHINT = {'gf_nh'}


def rf(face, hint):
    return '<w:rFonts%s w:ascii="%s" w:eastAsia="%s"/>' % (' w:hint="eastAsia"' if hint else '', face, face)


def ctx(face, hint=1):
    return ('<w:p><w:pPr><w:pStyle w:val="5"/><w:shd w:val="clear" w:color="auto" w:fill="FFFFFF"/><w:spacing w:before="0" w:beforeAutospacing="0" w:after="0" w:afterAutospacing="0" w:line="360" w:lineRule="auto"/><w:rPr>%s</w:rPr></w:pPr>'
            '<w:r><w:rPr>%s</w:rPr><w:t>%s</w:t></w:r></w:p>' % (rf(face, 0), rf(face, hint), TEXT))


def table(face, hint=1):
    w = 498
    rows = ''
    for r in range(0, len(TEXT), COLS):
        cells = ''
        for ch in TEXT[r:r + COLS]:
            cells += ('<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr><w:p><w:pPr><w:pStyle w:val="5"/><w:spacing w:before="0" w:beforeAutospacing="0" w:after="0" w:afterAutospacing="0" w:line="240" w:lineRule="auto"/><w:jc w:val="center"/><w:rPr>%s</w:rPr></w:pPr>'
                      '<w:r><w:rPr>%s</w:rPr><w:t>%s</w:t></w:r></w:p></w:tc>' % (w, rf(face, 0), rf(face, hint), ch))
        rows += '<w:tr><w:trPr><w:trHeight w:val="400"/></w:trPr>%s</w:tr>' % cells
    return ('<w:tbl><w:tblPr><w:tblW w:w="%d" w:type="dxa"/><w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>%s</w:tblGrid>%s</w:tbl>'
            % (w * COLS, '<w:gridCol w:w="%d"/>' % w * COLS, rows))


for name, face in CFG.items():
    h_ = 0 if name in NOHINT else 1
    body = ctx(face, h_) + '<w:p><w:pPr><w:pageBreakBefore/></w:pPr></w:p>' + table(face, h_) + '<w:p/>'
    s = head + body + sect + '</w:body></w:document>'
    g = dict(f)
    g['word/document.xml'] = s.encode('utf-8')
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for k, v in g.items():
            o.writestr(k, v)
# gf_orig: the original paragraph verbatim (two runs: hinted, then not), page 1 only
i = d.find('部署，为推动'); a = d.rfind('<w:p>', 0, i); b = d.find('</w:p>', i) + 6
sx = head + d[a:b] + sect + '</w:body></w:document>'
g = dict(f); g['word/document.xml'] = sx.encode('utf-8')
with zipfile.ZipFile(os.path.join(out, 'gf_orig.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
    for k, v in g.items():
        o.writestr(k, v)
print('ok', len(TEXT))
