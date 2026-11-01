#!/usr/bin/env python3
"""Lab pb (Windows 01QbbApP, for amd-4): where the text line stands after a page / column break that is the FIRST run of a bordered, shaded paragraph.
Package = lo-0b140d34be7df1a4 (styles, headers kept) with the body replaced. Page 5954x8392tw landscape, margins 1440, 2 columns, compat 11/14/15.
kind P: paragraph 1 as in the source (column break first run, text) then the tested paragraph (page break first run) -> new page.
kind C: the tested paragraph alone, FIRST in the section, column break first run -> column 2.
variants: a as is | b no border | c no shading, border kept | d before=0 with border | e before=1200 no border no shade | f before=600 as is | g border space 1 -> 8
usage: build.py SRC.docx OUTDIR"""
import sys, re, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode()
st = z.read('word/settings.xml').decode()
BORD = lambda sp: ('<w:pBdr><w:top w:val="single" w:sz="24" w:space="%d" w:color="auto"/><w:left w:val="single" w:sz="24" w:space="4" w:color="auto"/>'
                   '<w:bottom w:val="single" w:sz="24" w:space="%d" w:color="auto"/><w:right w:val="single" w:sz="24" w:space="4" w:color="auto"/></w:pBdr>') % (sp, sp)
SHD = '<w:shd w:val="clear" w:color="auto" w:fill="DEEAF6"/>'
def para(brk, text, border, shade, before, sp=1):
    pPr = (BORD(sp) if border else '') + (SHD if shade else '') + f'<w:spacing w:before="{before}"/><w:ind w:firstLine="1134"/>'
    return f'<w:p><w:pPr>{pPr}</w:pPr><w:r><w:br w:type="{brk}"/></w:r><w:r><w:t>{text}</w:t></w:r></w:p>'
VARS = {'a': (1, 1, 1200, 1), 'b': (0, 1, 1200, 1), 'c': (1, 0, 1200, 1), 'd': (1, 1, 0, 1), 'e': (0, 0, 1200, 1), 'f': (1, 1, 600, 1), 'g': (1, 1, 1200, 8)}
p1 = para('column', 'How is first line indent affected by a column break?', 1, 1, 1200)
sect = re.search(r'<w:sectPr.*?</w:sectPr>', doc, flags=re.S).group(0)
head = doc[:doc.index('<w:body>') + 8]
for compat in (11, 14, 15):
    stx = st.replace('w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="11"', f'w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{compat}"')
    for kind in 'PC':
        for v, (bd, sh, bf, sp) in VARS.items():
            if kind == 'P':
                body = p1 + para('page', 'How is first line indent affected by a page break?', bd, sh, bf, sp)
            else:
                body = para('column', 'How is first line indent affected by a column break?', bd, sh, bf, sp)
            d = head + body + sect + '</w:body></w:document>'
            name = f'pb-{kind}{v}-m{compat}'
            with zipfile.ZipFile(os.path.join(out, name + '.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
                for it in z.infolist():
                    if it.is_dir(): continue
                    data = z.read(it.filename)
                    if it.filename == 'word/document.xml': data = d
                    elif it.filename == 'word/settings.xml': data = stx
                    o.writestr(it.filename, data)
            print(name)
