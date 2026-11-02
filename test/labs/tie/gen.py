#!/usr/bin/env python3
"""Lab tie (Windows 01QbbApP, for amd-opus): which side of exact equality does Word fall on when the line holds Latin.
16pt (or 12pt) 宋体, jc both, characterSpacingControl doNotCompress, compat mode 12 / 15, run spacing 0.3pt (w:spacing 6) on every run.
Paragraph = N ideographs + 'GB/T14885-2010' (omitted in variant b) + X(的) + 24 more ideographs.  Right indent is chosen so that
natural(L+X) - W = d for d in -0.2 -0.1 -0.05 0 0.05 0.1 0.2 pt.
usage: gen.py cal OUT      -> calibration docs (left aligned, very wide page, one paragraph each)
       gen.py test OUT CAL.json -> test docs;  CAL.json maps variant name -> natural width of L+X (pt)
variants: a (N=18, Latin, 16pt)  b (N=26, no Latin, 16pt)  c (a with docGrid charSpace 4127, N=8)  d (a at 12pt)"""
import sys, os, json, zipfile

W_ = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
IDEO = '我们每天都在学习新知识并且努力工作生活'  # no 的
REST = '测试文字继续排版内容用来检查换行位置结果如何观察'
V = {  # nid, latin, size(half-points), grid
    'a': (18, True, 32, False), 'b': (26, False, 32, False), 'c': (8, True, 32, True), 'd': (18, True, 24, False)}
D = [-0.2, -0.1, -0.05, 0, 0.05, 0.1, 0.2]
TEXTW = 11906 / 20 - 144  # pt, margins 1440


def run(t, sz):
    rpr = ('<w:rFonts w:ascii="宋体" w:hAnsi="宋体" w:eastAsia="宋体" w:hint="eastAsia"/><w:spacing w:val="6"/><w:sz w:val="%d"/><w:szCs w:val="%d"/><w:lang w:eastAsia="zh-CN"/>' % (sz, sz))
    return '<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, t)


def para(var, rind, jc):
    nid, latin, sz, grid = V[var]
    ide = (IDEO * 3)[:nid]
    runs = run(ide, sz) + (run('GB/T14885-2010', sz) if latin else '') + run('的', sz) + run(REST, sz)
    return '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="400" w:lineRule="exact"/><w:ind w:left="0" w:right="%d"/><w:jc w:val="%s"/></w:pPr>%s</w:p>' % (rind, jc, runs)


def pkg(path, var, mode, body, wide):
    nid, latin, sz, grid = V[var]
    pw = 40000 if wide else 11906
    gd = '<w:docGrid w:type="linesAndChars" w:linePitch="312" w:charSpace="4127"/>' if grid else '<w:docGrid w:linePitch="312"/>'
    sect = '<w:sectPr><w:pgSz w:w="%d" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>%s</w:sectPr>' % (pw, gd)
    doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s%s</w:body></w:document>' % (W_, body, sect)
    sty = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles %s><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:eastAsia="宋体" w:hAnsi="Times New Roman" w:cs="Times New Roman"/>'
           '<w:sz w:val="%d"/><w:szCs w:val="%d"/><w:lang w:val="en-US" w:eastAsia="zh-CN" w:bidi="ar-SA"/></w:rPr></w:rPrDefault></w:docDefaults>'
           '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>' % (W_, sz, sz))
    st = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:characterSpacingControl w:val="doNotCompress"/><w:compat><w:useFELayout/>'
          '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="%d"/></w:compat></w:settings>' % (W_, mode))
    ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
    root = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    dr = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, v in (('[Content_Types].xml', ct), ('_rels/.rels', root), ('word/document.xml', doc), ('word/styles.xml', sty), ('word/settings.xml', st), ('word/_rels/document.xml.rels', dr)):
            z.writestr(n, v)


if __name__ == '__main__':
    kind, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for var in V:
        for mode in (12, 15):
            if kind == 'cal':
                # N ideographs + latin + X, then one more char, no wrap on a 40000-twip page; left aligned
                pkg(os.path.join(out, 'cal-%s-m%d.docx' % (var, mode)), var, mode, para(var, 0, 'left'), True)
            else:
                cal = json.load(open(sys.argv[3]))
                nat = cal['%s-m%d' % (var, mode)]
                body = ''
                rs = []
                for d in D:
                    w = nat - d
                    r = round((TEXTW - w) * 20)
                    ach = nat - (TEXTW - r / 20)
                    rs.append((d, r, round(ach, 3)))
                    body += para(var, r, 'both')
                pkg(os.path.join(out, 'tie-%s-m%d.docx' % (var, mode)), var, mode, body, False)
                json.dump(rs, open(os.path.join(out, 'tie-%s-m%d.json' % (var, mode)), 'w'))
    print('ok')
