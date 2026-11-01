#!/usr/bin/env python3
"""Lab vm4 builder: the empty continue paragraph of a merged pair, by what its mark says. usage: build.py OUTDIR"""
import sys, os, zipfile, itertools

FONTS = {  # code: (face, sz half-points)
    "Y": ("微软雅黑", 24),
    "S": ("仿宋_GB2312", 28),
}

def _m(rf='', extra=''):
    return ('<w:rPr>' + rf + extra + '</w:rPr>', False)
RF = lambda a=None, h=None, e=None, c=None: '<w:rFonts' + ''.join(f' w:{k}="{v}"' for k, v in (('ascii', a), ('hAnsi', h), ('eastAsia', e), ('cs', c)) if v) + '/>'
Y, S = "微软雅黑", "仿宋_GB2312"
SZ24 = '<w:sz w:val="24"/>'
MARKS = {
 'N1': _m(RF(Y, Y, Y, "宋体"), '<w:color w:val="000000"/><w:kern w:val="0"/>' + SZ24),   # the zh-eec0747a YaHei mark, whole
 'N2': _m(RF(Y, Y, Y), SZ24),                                                          # N1 without cs, color, kern
 'N3': _m(RF(S, S, S), SZ24),                                                          # all slots 仿宋, size 24 (M3 was 28)
 'N4': _m(RF(S, "Calibri", S), SZ24),                                                  # M1 with hAnsi Calibri (the document's theme face)
 'N5': _m(RF(S, None, S), SZ24),                                                       # ascii and eastAsia 仿宋, hAnsi not stated (inherits YaHei)
 'N6': _m(RF(S, Y, S), '<w:color w:val="000000"/><w:kern w:val="0"/>' + SZ24),         # M1 plus color and kern 0
 'N7': _m(RF(None, None, S), SZ24),                                                    # eastAsia 仿宋 alone
 'N8': _m(RF(S, None, None), SZ24),                                                    # ascii 仿宋 alone
 'N9': _m(RF("宋体"), ''),                                                             # ascii 宋体 alone (zh-eec0747a's third mark)
 'N10': _m('', '<w:kern w:val="0"/>'),                                                 # kern 0 alone
}

def doc_xml(font, grid, after, exact, mark='M0'):
    mrpr, valign = MARKS[mark]
    face, sz = FONTS[font]
    rf = f'<w:rFonts w:ascii="{face}" w:hAnsi="{face}" w:eastAsia="{face}" w:cs="{face}"/>'
    def para(text, restart):
        ppr = '<w:pPr><w:jc w:val="left"/>'
        mk = mrpr if (not text and not restart) else ''
        if restart and exact:
            ppr += '<w:spacing w:line="440" w:lineRule="exact"/>'
        ppr += mk + '</w:pPr>'
        if not text:
            return f'<w:p>{ppr}</w:p>'
        return f'<w:p>{ppr}<w:r><w:t>{text}</w:t></w:r></w:p>'
    def cell(w, merge, lines):
        mg = '<w:vMerge w:val="restart"/>' if merge == "R" else '<w:vMerge/>'
        if merge == "R":
            body = "".join(para("类别" if i == 0 else "分值", True) for i in range(lines))
        else:
            body = para("", False)
        return f'<w:tc><w:tcPr><w:tcW w:w="{w}" w:type="dxa"/>{mg}{'<w:vAlign w:val="center"/>' if valign else ''}</w:tcPr>{body}</w:tc>'
    def row(heights, k, span, lines):
        h = heights[k]
        trpr = f'<w:trPr><w:trHeight w:val="{h}" w:hRule="atLeast"/></w:trPr>' if h else ''
        m = "R" if k == 0 else "C"
        return f'<w:tr>{trpr}{cell(3000, m, lines)}{cell(3000, m, lines)}</w:tr>'
    def table(span, heights, lines):
        b = ''.join(f'<w:{s} w:val="single" w:sz="4" w:space="0" w:color="auto"/>' for s in ("top", "left", "bottom", "right", "insideH", "insideV"))
        rows = ''.join(row(heights, k, span, lines) for k in range(span))
        return (f'<w:tbl><w:tblPr><w:tblW w:w="6000" w:type="dxa"/><w:tblBorders>{b}</w:tblBorders>'
                f'<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/></w:tblGrid>{rows}</w:tbl>')
    specs = []  # (label, span, heights, lines)
    for lines in (1,):
        for hh in ((0, 0), (630, 0), (630, 630)):
            specs.append((f"S2-L{lines}-h{hh[0]}_{hh[1]}", 2, hh, lines))
    for hh in ((0, 0, 0), (630, 630, 630)):
        specs.append((f"S3-L1-h{hh[0]}_{hh[1]}_{hh[2]}", 3, hh, 1))
    body = ''
    for i, (label, span, hh, lines) in enumerate(specs, 1):
        pb = '<w:pageBreakBefore/>' if i > 1 else ''
        body += f'<w:p><w:pPr>{pb}<w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial"/><w:sz w:val="20"/></w:rPr><w:t>T{i:02d} {label}</w:t></w:r></w:p>'
        body += table(span, hh, lines)
        body += f'<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial"/><w:sz w:val="20"/></w:rPr><w:t>==T{i:02d}==</w:t></w:r></w:p>'
    gridxml = '<w:docGrid w:type="lines" w:linePitch="312"/>' if grid else ''
    sect = f'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="851" w:footer="992" w:gutter="0"/>{gridxml}</w:sectPr>'
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
                + body + sect + '</w:body></w:document>')
    styles = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
              f'<w:docDefaults><w:rPrDefault><w:rPr>{rf}<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/></w:rPr></w:rPrDefault>'
              f'<w:pPrDefault><w:pPr><w:spacing w:after="{160 if after else 0}" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
              '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>')
    settings = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                '<w:compat><w:adjustLineHeightInTable/><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="14"/></w:compat></w:settings>')
    return document, styles, settings

CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
         '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')

def main(out):
    os.makedirs(out, exist_ok=True)
    n = 0
    for g in (1,):
        for m in tuple(MARKS):
            n += 1
            name = f"vm4-{n:02d}-Y-{'grid' if g else 'nogrid'}-after8-{m}.docx"
            d, st_, se = doc_xml("Y", g, 1, 0, m)
            with zipfile.ZipFile(os.path.join(out, name), "w", zipfile.ZIP_DEFLATED) as z:
                z.writestr("[Content_Types].xml", CT); z.writestr("_rels/.rels", RELS)
                z.writestr("word/document.xml", d); z.writestr("word/styles.xml", st_)
                z.writestr("word/settings.xml", se); z.writestr("word/_rels/document.xml.rels", DRELS)
            print(name)

if __name__ == "__main__":
    main(sys.argv[1])
