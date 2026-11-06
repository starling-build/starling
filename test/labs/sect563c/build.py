#!/usr/bin/env python3
"""Does Word keep the section mark's space-after share for columns, or for a page-opening break?
From lo-563123f3 (heading "C", 12pt before, break paragraph after 10). usage: build.py SRC.docx OUTDIR
orig (Word C=111.9); cols2: the section the mark ends has 2 columns; nextpage: the section after the mark starts a new page (last sectPr type nextPage); cols2next: both.
Measure the baseline of heading "C" (page 1 or 2: say which) and its page."""
import sys,re,zipfile,os
src,out=sys.argv[1],sys.argv[2]; os.makedirs(out,exist_ok=True)
z=zipfile.ZipFile(src); d=z.read('word/document.xml').decode('utf8')
sect=re.search(r'<w:sectPr.*?</w:sectPr>',d,re.S).group(0)
assert 'continuous' in sect and '<w:cols w:space="720"/>' in sect
ms=list(re.finditer(r'<w:sectPr.*?</w:sectPr>',d,re.S))
last=ms[-1].group(0)
def v(nextpage,cols2):
    r=d
    if cols2: r=r.replace(sect,sect.replace('<w:cols w:space="720"/>','<w:cols w:num="2" w:space="720"/>'),1)
    if nextpage:
        l2=last.replace('<w:type w:val="continuous"/>','') if '<w:type' in last else last
        l2=l2.replace('<w:pgSz','<w:type w:val="nextPage"/><w:pgSz',1)
        r=r[:r.rindex(last)]+l2+r[r.rindex(last)+len(last):]
    return r
V={'orig':d,'cols2':v(0,1),'nextpage':v(1,0),'cols2next':v(1,1)}
for k,x in V.items():
    dst=zipfile.ZipFile(os.path.join(out,f'sect563c-{k}.docx'),'w',zipfile.ZIP_DEFLATED)
    for i in z.infolist():
        b=z.read(i.filename)
        if i.filename=='word/document.xml': b=x.encode('utf8')
        dst.writestr(i.filename,b)
    dst.close()
