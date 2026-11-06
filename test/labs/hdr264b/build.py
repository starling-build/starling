#!/usr/bin/env python3
"""Ablation of zh-264d7516's real header1.xml. usage: build.py SRC.docx OUTDIR
Paragraph 1 has three parts: logo (inline drawing run), bold text run, anchored line run (mc:AlternateContent run).
Variants: orig, nologo, notext, noline, logoonly, textonly, lineonly, none (para 1 empty). Para 2 (empty, style 6) always kept.
Measure page 21's first body baseline (and every line) in Word."""
import sys,re,zipfile,os
src,out=sys.argv[1],sys.argv[2]; os.makedirs(out,exist_ok=True)
z=zipfile.ZipFile(src); h=z.read('word/header1.xml').decode('utf8')
p1=re.search(r'<w:p>.*?</w:p>',h,re.S); para=p1.group(0)
runs=re.findall(r'<w:r>.*?</w:r>',para,re.S)
logo=[r for r in runs if '<wp:inline' in r]; line=[r for r in runs if 'mc:AlternateContent' in r]
text=[r for r in runs if '<w:t>' in r and r not in logo and r not in line]
rest=[r for r in runs if r not in logo+line+text]
print(len(runs),len(logo),len(text),len(line),len(rest))
head=para[:para.index(runs[0])]
def mk(keep):
    body=''.join(r for r in runs if (r in logo and 'logo' in keep) or (r in text and 'text' in keep) or (r in line and 'line' in keep) or r in rest)
    return h.replace(para,head+body+'</w:p>',1)
V={'orig':{'logo','text','line'},'nologo':{'text','line'},'notext':{'logo','line'},'noline':{'logo','text'},
   'logoonly':{'logo'},'textonly':{'text'},'lineonly':{'line'},'none':set()}
for k,keep in V.items():
    dst=zipfile.ZipFile(os.path.join(out,f'hdr264b-{k}.docx'),'w',zipfile.ZIP_DEFLATED)
    for i in z.infolist():
        d=z.read(i.filename)
        if i.filename=='word/header1.xml': d=mk(keep).encode('utf8')
        dst.writestr(i.filename,d)
    dst.close()
