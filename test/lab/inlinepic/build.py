#!/usr/bin/env python3
"""Lab inlinepic (Windows, for lenovo-2): why Word puts 4.5-10.7 pt of extra gap after each inline picture of zh-e5eb092a pp8-10 (ours ~0).
usage: build.py SRC.docx OUTDIR   SRC = test/corpus/docx/docs/zh-e5eb092a....docx
The two paragraphs that hold the 8 inline pictures (one picture per line, 12pt Microsoft YaHei UI runs, docGrid lines 15.6pt, effectExtent b 0.05-1.45pt)
are kept alone in the body. Variants (each doc: pictures are read from the PDF by meas.py as image boxes):
 real       the two paragraphs as in the corpus document
 nogrid     docGrid removed        | grid_lc: docGrid type linesAndChars      | snapoff: snapToGrid 0 in both paragraphs
 tiny       the picture runs' font size 2pt (descent of the line's font)       | sim: runs in SimSun 12pt (Latin face Times New Roman)
 noext      every effectExtent set to 0                                       | noext_nogrid both
 h<H>       every picture H pt high (H = 100,111,122,133,144,155,166,177), real settings: line pitch vs height
 p2         one paragraph, no spacing run (w:spacing val 8 removed) | lsingle: paragraph line spacing exact 20pt (should crop/ignore pictures)"""
import sys, os, re, zipfile
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); files = [(i.filename, z.read(i.filename)) for i in z.infolist() if not i.filename.endswith('/')]
D = dict(files)['word/document.xml'].decode('utf8')
ps = re.findall(r'<w:p[ >].*?</w:p>', D, re.S)
pics = [p for p in ps if '<w:drawing>' in p]
assert len(pics) == 2, len(pics)
head = D[:D.index('<w:body>') + len('<w:body>')]
sect = re.search(r'<w:sectPr.*?</w:sectPr>', D, re.S).group(0)
def save(name, body):
    with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as zz:
        for fn, b in files: zz.writestr(fn, (head + body + sect + '</w:body></w:document>').encode('utf8') if fn == 'word/document.xml' else b)
body = ''.join(pics)
save('real', body)
def sect_edit(name, f):
    global sect
    s0 = sect; sect = f(sect); save(name, body); sect = s0
sect_edit('nogrid', lambda s: re.sub(r'<w:docGrid[^>]*/>', '', s))
sect_edit('grid_lc', lambda s: re.sub(r'<w:docGrid w:type="lines"', '<w:docGrid w:type="linesAndChars"', s))
save('snapoff', body.replace('<w:pPr>', '<w:pPr><w:snapToGrid w:val="0"/>'))
save('tiny', body.replace('<w:sz w:val="24"/><w:szCs w:val="24"/>', '<w:sz w:val="4"/><w:szCs w:val="4"/>'))
save('sim', re.sub(r'<w:rFonts [^>]*/>', '<w:rFonts w:hint="eastAsia" w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="SimSun" w:cs="Times New Roman"/>', body))
noext = re.sub(r'<wp:effectExtent [^>]*/>', '<wp:effectExtent l="0" t="0" r="0" b="0"/>', body)
save('noext', noext)
sect_edit('noext_nogrid', lambda s: re.sub(r'<w:docGrid[^>]*/>', '', s)) if False else None
s0 = sect; sect = re.sub(r'<w:docGrid[^>]*/>', '', sect); save('noext_nogrid', noext); sect = s0
save('p2', body.replace('<w:spacing w:val="8"/>', ''))
save('lsingle', body.replace('<w:spacing w:before="0" w:beforeAutospacing="0" w:after="0" w:afterAutospacing="0"/>', '<w:spacing w:before="0" w:after="0" w:line="400" w:lineRule="exact"/>'))
for H in (100, 111, 122, 133, 144, 155, 166, 177):
    e = int(H * 12700)
    b = re.sub(r'(<wp:extent cx="\d+" cy=")\d+(")', lambda m: m.group(1) + str(e) + m.group(2), body)
    b = re.sub(r'(<a:ext cx="\d+" cy=")\d+(")', lambda m: m.group(1) + str(e) + m.group(2), b)
    save('h%d' % H, b)
print(sorted(os.listdir(out)))
