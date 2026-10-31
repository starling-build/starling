#!/usr/bin/env python3
"""Lab cq1: does Word hang a closing quote U+201D at a line's end, wrap it to the next line's start, or squeeze it -- and what
decides it (Linux lo5, 2026-11-01). Background: in the official 756 Word hangs a line-ending U+201D 186 times of 388 (48%) and
ours 301 of 447 (67%); for U+300D U+FF09 U+300B the two agree. Two documents show opposite answers:
  zh-b00fef0d (mode 12, rFonts hint=eastAsia, all four fonts 仿宋_GB2312, 16pt, jc both): "...条抓块统" + U+201D, and Word breaks
    BEFORE the quote -- the next line starts with U+201D (ours hangs it 8pt past the margin).
  zh-360c1df1 (mode 14, rFonts hint=default ascii/hAnsi Times New Roman, eastAsia 仿宋_GB2312, 16pt): "...金山银" fills the line,
    "山" + U+201D go down TOGETHER (ours keeps 山 and hangs the quote). There the quote is set in Times New Roman: 7.1pt wide.
Hypothesis: the run's font setting decides which font U+201D is set in, and so whether it is an East Asian mark (kinsoku, hangs/
squeezes) or a Latin quote (no kinsoku, a narrow glyph, no hang).
Page A4 11906 x 16838, margins top/bottom 1440, left = right = 2753 so the column is 6410 twips = 320.5pt = 20 ems of 16pt + 0.5pt.
Each document holds 20 test paragraphs, each followed by a marker paragraph '==NN=='. A test paragraph is K ideographs (K = 19 or
20) + U+201D + a tail; right indent R twips (0, -40, -100, -160, -240: negative = that much more room) ; tail A = 15 ideographs,
tail B = U+201C + 11 ideographs + U+201D + 4 ideographs. Room after the K ideographs is (20-K)*16 + 0.5 + |R|/20 pt.
Documents (NN-fontcode-mode-jc): fontcode F1 = hint eastAsia, ascii/hAnsi/eastAsia/cs all 仿宋_GB2312; F2 = hint default, ascii/hAnsi/cs
Times New Roman, eastAsia 仿宋_GB2312; F3 = no hint, same fonts as F2. All 16pt (sz 32), single spacing, no indents, jc both unless
'left'. Modes 12, 14, 15 (compatibilityMode); 'alt' adds w:useAltKinsokuLineBreakRules.
usage: build.py OUTDIR.  Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table. Report that table."""
import os, sys, zipfile
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
CH = "天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜金生丽水玉出昆冈剑号巨阙珠称夜光果珍李柰菜重芥姜"
FONTS = {
    'F1': '<w:rFonts w:hint="eastAsia" w:ascii="仿宋_GB2312" w:hAnsi="仿宋_GB2312" w:eastAsia="仿宋_GB2312" w:cs="仿宋_GB2312"/>',
    'F2': '<w:rFonts w:hint="default" w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="仿宋_GB2312" w:cs="Times New Roman"/>',
    'F3': '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="仿宋_GB2312" w:cs="Times New Roman"/>',
}
LANG = '<w:lang w:val="en-US" w:eastAsia="zh-CN"/>'
KS = (19, 20); RS = (0, -40, -100, -160, -240); TAILS = ('A', 'B')
def run(font, text):
    rpr = '%s<w:sz w:val="32"/><w:szCs w:val="32"/>%s' % (font, LANG)
    return '<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, text)
def para(font, text, jc, r=0):
    ppr = '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>%s<w:jc w:val="%s"/>' % ('<w:ind w:left="0" w:right="%d"/>' % r if r else '', jc)
    return '<w:p><w:pPr>%s<w:rPr>%s<w:sz w:val="32"/></w:rPr></w:pPr>%s</w:p>' % (ppr, font, run(font, text))
def marker(n):
    return ('<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:sz w:val="16"/></w:rPr>'
            '<w:t>==%02d==</w:t></w:r></w:p>' % n)
def body(font, jc):
    out = []; n = 0
    for k in KS:
        for r in RS:
            for t in TAILS:
                n += 1
                head = CH[:k]
                tail = CH[k:k + 15] if t == 'A' else '“' + CH[k:k + 11] + '”' + CH[k + 11:k + 15]
                out.append(para(font, head + '”' + tail, jc, r)); out.append(marker(n))
    return ''.join(out)
def doc(b):
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document %s><w:body>%s'
            '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="2753" w:bottom="1440" w:left="2753" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>' % (W, b))
CT = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>')
RELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
DRELS = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
         '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/></Relationships>')
def settings(mode, alt):
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:settings %s><w:compat>%s<w:compatSetting w:name="compatibilityMode" '
            'w:uri="http://schemas.microsoft.com/office/word" w:val="%d"/></w:compat></w:settings>' % (W, '<w:useAltKinsokuLineBreakRules/>' if alt else '', mode))
V = [(f, m, 'both', False) for f in ('F1', 'F2', 'F3') for m in (12, 14, 15)]
V += [(f, 15, 'left', False) for f in ('F1', 'F2', 'F3')] + [('F1', 14, 'both', True), ('F2', 14, 'both', True)]
for i, (f, m, jc, alt) in enumerate(V, 1):
    name = '%02d-%s-m%d-%s%s' % (i, f, m, jc, '-alt' if alt else '')
    fn = os.path.join(out, 'cq1-%s.docx' % name)
    with zipfile.ZipFile(fn, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CT); z.writestr('_rels/.rels', RELS)
        z.writestr('word/_rels/document.xml.rels', DRELS); z.writestr('word/settings.xml', settings(m, alt))
        z.writestr('word/document.xml', doc(body(FONTS[f], jc)))
    print(fn)
