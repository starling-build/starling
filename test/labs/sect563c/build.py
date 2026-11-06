#!/usr/bin/env python3
"""Does Word keep the section mark's space-after share for columns, or for a page-opening break?
From lo-563123f3 (heading "C", 12pt before, break paragraph after 10). usage: build.py SRC.docx OUTDIR
Variants of the break's sectPr: orig (continuous, 1 col: Word C=111.9), cols2 (continuous, 2 cols),
nextpage (nextPage, 1 col), cols2next (nextPage, 2 cols), evenpage-free: oddpage is skipped.
Measure the baseline of heading "C" (page 1 or 2: say which) and its page."""
import sys,re,zipfile,os
src,out=sys.argv[1],sys.argv[2]; os.makedirs(out,exist_ok=True)
z=zipfile.ZipFile(src); d=z.read('word/document.xml').decode('utf8')
sect=re.search(r'<w:sectPr.*?</w:sectPr>',d,re.S).group(0)
assert 'continuous' in sect and '<w:cols w:space="720"/>' in sect
def v(t,c):
    s=sect.replace('<w:type w:val="continuous"/>','' if t=='next' else sect and '<w:type w:val="continuous"/>')
    if t=='nextPage': s=sect.replace('<w:type w:val="continuous"/>','<w:type w:val="nextPage"/>')
    if c==2: s=s.replace('<w:cols w:space="720"/>','<w:cols w:num="2" w:space="720"/>')
    return d.replace(sect,s,1)
V={'orig':d,'cols2':v('continuous',2),'nextpage':v('nextPage',1),'cols2next':v('nextPage',2)}
for k,x in V.items():
    dst=zipfile.ZipFile(os.path.join(out,f'sect563c-{k}.docx'),'w',zipfile.ZIP_DEFLATED)
    for i in z.infolist():
        b=z.read(i.filename)
        if i.filename=='word/document.xml': b=x.encode('utf8')
        dst.writestr(i.filename,b)
    dst.close()
