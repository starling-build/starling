# -*- coding: utf-8 -*-
"""Lab gothline (Windows 01QbbApP, for amd-3): last line of a 1.5-spaced Chinese paragraph made of punctuation only (MS Gothic), then a bold heading.
Package = zh-5450d509 (styles, settings, landscape A4 margins 1800/1440, docGrid lines 312, embedded fonts) with the body replaced.
Paragraph: pStyle 5, rFonts ascii/eastAsia 仿宋_GB2312 (absent on the box), 12pt, before/after 0, line L auto; text = 116 hans (two 58-char lines) + TAIL.
Heading: bold, single spacing, same font, text 一、总体要求.  Docs g360, g240, g480 (line=L); pages: 1 tail 引》）。  2 tail 总体要求。  3 tail 。  4 tail ABC.
usage: mk.py OUT  (cwd lab/goth)"""
import zipfile, os, sys, re
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile('orig.docx')
f = {n: z.read(n) for n in z.namelist() if not n.endswith('/')}
d = f['word/document.xml'].decode('utf-8')
bs = d.index('<w:body>') + len('<w:body>')
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', d, re.S)[-1]
head = d[:bs]
FILL = ('春风又绿江南岸明月何时照我还落霞与孤鹜齐飞秋水共长天一色山重水复疑无路柳暗花明又一村'
        '海内存知己天涯若比邻会当凌绝顶一览众山小野旷天低树江清月近人白日依山尽黄河入海流')
FILL = (FILL * 3)[:116]
assert len(FILL) == 116
RF = '<w:rFonts w:ascii="仿宋_GB2312" w:eastAsia="仿宋_GB2312"/>'
RFH = '<w:rFonts w:hint="eastAsia" w:ascii="仿宋_GB2312" w:eastAsia="仿宋_GB2312"/>'
TAILS = ['引》）。', '总体要求。', '。', 'ABC']


def para(text, line, first):
    pb = '' if first else '<w:pageBreakBefore/>'
    return ('<w:p><w:pPr><w:pStyle w:val="5"/>%s<w:shd w:val="clear" w:color="auto" w:fill="FFFFFF"/><w:spacing w:before="0" w:beforeAutospacing="0" w:after="0" w:afterAutospacing="0" w:line="%d" w:lineRule="auto"/><w:rPr>%s</w:rPr></w:pPr>'
            '<w:r><w:rPr>%s</w:rPr><w:t>%s</w:t></w:r></w:p>' % (pb, line, RF, RFH, text))


def heading():
    return ('<w:p><w:pPr><w:pStyle w:val="5"/><w:shd w:val="clear" w:color="auto" w:fill="FFFFFF"/><w:spacing w:before="0" w:beforeAutospacing="0" w:after="0" w:afterAutospacing="0"/><w:rPr>%s<w:b/><w:bCs/></w:rPr></w:pPr>'
            '<w:r><w:rPr>%s<w:b/><w:bCs/></w:rPr><w:t>一、总体要求</w:t></w:r></w:p>' % (RF, RFH))


for line in (360, 240, 480):
    body = ''
    for k, t in enumerate(TAILS):
        body += para(FILL + t, line, k == 0) + heading()
    s = head + body + sect + '</w:body></w:document>'
    g = dict(f)
    g['word/document.xml'] = s.encode('utf-8')
    with zipfile.ZipFile(os.path.join(out, 'g%d.docx' % line), 'w', zipfile.ZIP_DEFLATED) as o:
        for k, v in g.items():
            o.writestr(k, v)
print('ok')
