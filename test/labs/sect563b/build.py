#!/usr/bin/env python3
"""Ablation of lo-563123f3's real page 1 (Word puts heading "C" at baseline 111.9, ours 109.9: 2.0 pt).
usage: build.py SRC.docx OUTDIR.  Parts before the heading: P1 = "On the Insert tab, the"+INDEX field start;
BRK = empty paragraph carrying the continuous sectPr. Removed/changed one at a time.
Measure the baseline of the heading "C" (and first line) in Word."""
import sys,re,zipfile,os
src,out=sys.argv[1],sys.argv[2]; os.makedirs(out,exist_ok=True)
z=zipfile.ZipFile(src); d=z.read('word/document.xml').decode('utf8')
ps=re.findall(r'<w:p [^>]*>.*?</w:p>',d,re.S)
p1,brk,head=ps[0],ps[1],ps[2]
assert 'On the Insert' in p1 and '<w:sectPr' in brk and '>C<' in head
sect=re.search(r'<w:sectPr.*?</w:sectPr>',brk,re.S).group(0)
def rep(*pairs):
    r=d
    for a,b in pairs: assert a in r; r=r.replace(a,b,1)
    return r
p1empty=re.sub(r'<w:r[ >].*</w:r>','',p1,flags=re.S)
V={'orig':d,
 'nobreak':rep((brk,'')),
 'nop1':rep((p1,'')),
 'p1empty':rep((p1,p1empty)),
 'sectinp1':rep((p1,p1.replace('</w:pPr>','')) if False else (p1,p1.replace('<w:pPr>','<w:pPr>'+sect,1) if '<w:pPr>' in p1 else re.sub(r'(<w:p [^>]*>)',r'\1<w:pPr>'+sect.replace('\\','\\\\')+'</w:pPr>',p1,1)),(brk,'')),
 'brk0':rep((brk,brk.replace('<w:pPr>','<w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>',1))),
 'nokeep':rep((head,head.replace('<w:keepNext/>',''))),
 'before0':rep((head,head.replace('<w:keepNext/>','<w:keepNext/><w:spacing w:before="0"/>',1))),
}
for k,x in V.items():
    dst=zipfile.ZipFile(os.path.join(out,f'sect563b-{k}.docx'),'w',zipfile.ZIP_DEFLATED)
    for i in z.infolist():
        b=z.read(i.filename)
        if i.filename=='word/document.xml': b=x.encode('utf8')
        dst.writestr(i.filename,b)
    dst.close()
