#!/usr/bin/env python3
"""Lab wsc (for amd-opus): what pitch Word for Windows gives East Asian text under a character scale (w:w).

zh-4e5fe46f (mode 14, compressPunctuation, 仿宋_GB2312 10.5pt cells, runs at w:w 95 with spacing -5/-7 twips): on
lines that break where ours does, Word's print sets the w95 spacing -7 run 9.225pt apart (77,77,...,76 of 1/600in),
ours 9.275; the w95 run with no spacing 9.92, ours 9.975. Unscaled runs agree to 0.003. So the cell's p9 first line
"…应有 基本的" fits in Word and ours breaks one character early. Question: what width does Word give a scaled
character, by font, size, scale and spacing?
  wsc-a  after the control, one paragraph per combination, each a single left-aligned line of 12 ideographs
         "行政处罚决定执行完毕执法":
           font 仿宋_GB2312, 宋体; size 10.5, 12, 16; w:w 100, 99, 95, 90, 80, 150; spacing 0, -7 twips
         (72 paragraphs, in that nesting order: font outermost, spacing innermost)
  wsc-b  the control's cell alone, its width stepped 5870 .. 6070 twips by 10 (21 one-cell tables), the
         paragraph as in the document: which character ends the first line at each width
The control (both documents) is the p9 cell paragraph "一般应有行政强制审批表…" in a one-cell table of the
document's width 5970, cell margins 0: compare its lines with the corpus print before trusting the lab.
  wsc-c  (follow-up) 宋体 at 9, 10, 10.5, 14, 18, 22, 28pt x w:w 99, 95, 90, 80, no spacing, 8 ideographs a line (28 lines)
gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, 'zh-4e5fe46f*.docx'))[0])
doc = z.read('word/document.xml').decode('utf-8')
ps = [m.group(0) for m in re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S)]
src = [p for p in ps if '一般应有行政强制审批表' in text(p)][0]
mar = '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="0" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar>'
def table(w, p):
    return ('<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblInd w:w="5" w:type="dxa"/><w:tblLayout w:type="fixed"/>%s</w:tblPr>'
            '<w:tblGrid><w:gridCol w:w="%d"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>%s</w:tc></w:tr></w:tbl>'
            '<w:p><w:pPr><w:spacing w:after="120"/></w:pPr></w:p>') % (mar, w, w, p)
def write(body, name):
    own = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc, flags=re.S).group(0)
    own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', own)
    out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + body + own, doc, count=1, flags=re.S)
    path = os.path.join(outdir, name + '.docx')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            zo.writestr(n, out.encode('utf-8') if n == 'word/document.xml' else z.read(n))
    print(name, '->', path)
ctl = table(5970, src)
line = '行政处罚决定执行完毕执法'
paras = []
for font in ('仿宋_GB2312', '宋体'):
    for sz in (21, 24, 32):
        for w in (100, 99, 95, 90, 80, 150):
            for sp in (0, -7):
                rpr = '<w:rPr><w:rFonts w:ascii="%s" w:hAnsi="%s" w:eastAsia="%s"/>%s%s<w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr>' % (
                    font, font, font, '<w:spacing w:val="%d"/>' % sp if sp else '', '<w:w w:val="%d"/>' % w if w != 100 else '', sz, sz)
                paras.append('<w:p><w:pPr><w:jc w:val="left"/><w:spacing w:after="60" w:line="240" w:lineRule="auto"/></w:pPr><w:r>%s<w:t>%s</w:t></w:r></w:p>' % (rpr, line))
write(ctl + ''.join(paras), 'wsc-a')

# wsc-c: more sizes, SimSun only, no spacing (follow-up: zh-7773163d's 18pt and zh-fe536967's 22pt runs looked unrounded)
paras = []
for sz in (18, 20, 21, 28, 36, 44, 56):
    for w in (99, 95, 90, 80):
        rpr = '<w:rPr><w:rFonts w:ascii="宋体" w:hAnsi="宋体" w:eastAsia="宋体"/><w:w w:val="%d"/><w:sz w:val="%d"/><w:szCs w:val="%d"/></w:rPr>' % (w, sz, sz)
        paras.append('<w:p><w:pPr><w:jc w:val="left"/><w:spacing w:after="60" w:line="240" w:lineRule="auto"/></w:pPr><w:r>%s<w:t>%s</w:t></w:r></w:p>' % (rpr, line[:8]))
write(''.join(paras), 'wsc-c')
write(ctl + ''.join(table(w, src) for w in range(5870, 6071, 10)), 'wsc-b')
