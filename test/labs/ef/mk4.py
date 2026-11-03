import re,zipfile,sys
src=[l for l in __import__('glob').glob('/data/s/amd-3/starling/test/corpus/docx/lo/docs/lo-eb12e7d4*.docx')][0]
z=zipfile.ZipFile(src)
x=z.read('word/document.xml').decode('utf8')
bs=x.index('<w:body>')+8
# find start of paragraph 166 at top level (count <w:p after body start, skipping table paragraphs by using regex positions)
ms=list(re.finditer(r'<w:p[ >]',x))
# paragraph list index consistent with earlier regex findall
k=x.index('Alle ribbeblokjes zitten nu goed'); k2=x.index('We zullen in hoofdstuk V',k); st=[m.start() for m in ms if m.start()<k2][-1]
head,body=x[:bs],'<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="2844" w:lineRule="exact"/></w:pPr></w:p>'+x[st:]
def paras(b): return [m.start() for m in re.finditer(r'<w:p[ >]',b)]
def cut(b,i):  # remove paragraph i (relative, 0 = para 166)
    ps=paras(b); s=ps[i]; e=b.index('</w:p>',s)+6; return b[:s]+b[e:]
def nopic(b,i):
    ps=paras(b); s=ps[i]; e=b.index('</w:p>',s)+6
    seg=re.sub(r'<w:r>(?:(?!</w:r>).)*?<w:drawing>.*?</w:drawing></w:r>','',b[s:e],flags=re.S)
    return b[:s]+seg+b[e:]
def variant(name,fn):
    b=fn(body)
    out=head+b
    zo=zipfile.ZipFile(name,'w',zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        zo.writestr(it.filename, out.encode('utf8') if it.filename=='word/document.xml' else z.read(it.filename))
    zo.close()
W=[i for i,p in enumerate(paras(body)) if body[p:p+3000].split('</w:p>')[0].find('We zullen in hoofdstuk V')>=0][0]
print('W',W)
variant('ef4a.docx',lambda b:b)
variant('ef4b.docx',lambda b:nopic(nopic(b,W+6),W+5))          # no anchors 171,172
variant('ef4c.docx',lambda b:b.replace('<w:numPr><w:ilvl w:val="1"/><w:numId w:val="3"/></w:numPr><w:spacing w:line="360" w:lineRule="auto"/><w:rPr><w:spacing w:val="1"/><w:sz w:val="22"/>','<w:spacing w:line="360" w:lineRule="auto"/><w:rPr><w:spacing w:val="1"/><w:sz w:val="22"/>',1))
variant('ef4d.docx',lambda b:cut(nopic(nopic(b,W+6),W+5),W+4))   # also no para 170
