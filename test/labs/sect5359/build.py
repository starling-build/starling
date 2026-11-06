#!/usr/bin/env python3
"""zh-b5359de4's real section break (5th sectPr, no w:type = nextPage, 2 cols, landscape; the body's last sectPr is
continuous, 2 cols, top margin 1440 vs the break's 1531). Our single-column guard on the mark's space-after share is NOT Word's rule;
one change at a time to find what is. usage: build.py SRC.docx OUTDIR
orig; lastnext: last sectPr continuous->nextPage; lastcols1/breakcols1: that section 1 column; samemargin: last top margin 1531;
portrait: every pgSz portrait (w/h swapped, no orient); breakcont: break sectPr type continuous; mark-only changes otherwise none.
Print all pages; report baselines of every line on the pages around the break (we are 1.1 pt high on one page after it)."""
import sys,re,zipfile,os
src,out=sys.argv[1],sys.argv[2]; os.makedirs(out,exist_ok=True)
z=zipfile.ZipFile(src); d=z.read('word/document.xml').decode('utf8')
ms=list(re.finditer(r'<w:sectPr.*?</w:sectPr>',d,re.S)); assert len(ms)==6
brk=ms[4].group(0); last=ms[5].group(0)
def rep(r,old,new):
    i=r.index(old); return r[:i]+new+r[i+len(old):]
def v(**k):
    r=d
    if k.get('lastnext'): r=rep(r,last,last.replace('<w:type w:val="continuous"/>',''))
    if k.get('lastcols1'): r=rep(r,last,last.replace('w:num="2"','w:num="1"'))
    if k.get('breakcols1'): r=rep(r,brk,brk.replace('w:num="2"','w:num="1"'))
    if k.get('samemargin'): r=rep(r,last,last.replace('w:top="1440"','w:top="1531"'))
    if k.get('breakcont'): r=rep(r,brk,brk.replace('<w:pgSz','<w:type w:val="continuous"/><w:pgSz',1))
    if k.get('portrait'):
        r=r.replace('w:w="23820" w:h="16840" w:orient="landscape"','w:w="16840" w:h="23820"')
    return r
V={'orig':d,'lastnext':v(lastnext=1),'lastcols1':v(lastcols1=1),'breakcols1':v(breakcols1=1),'samemargin':v(samemargin=1),'breakcont':v(breakcont=1),'portrait':v(portrait=1)}
for k,x in V.items():
    dst=zipfile.ZipFile(os.path.join(out,f'sect5359-{k}.docx'),'w',zipfile.ZIP_DEFLATED)
    for i in z.infolist():
        b=z.read(i.filename)
        if i.filename=='word/document.xml': b=x.encode('utf8')
        dst.writestr(i.filename,b)
    dst.close()
