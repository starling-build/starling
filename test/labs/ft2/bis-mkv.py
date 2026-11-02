import zipfile,re,sys,os
src='orig.docx'; out=sys.argv[1]; os.makedirs(out,exist_ok=True)
def rd():
    z=zipfile.ZipFile(src); return {n:z.read(n) for n in z.namelist()}
def wr(name,f):
    with zipfile.ZipFile(os.path.join(out,name+'.docx'),'w',zipfile.ZIP_DEFLATED) as z:
        for n,v in f.items(): z.writestr(n,v)
def S(f,n): return f[n].decode('utf8')
V={}
f=rd(); wr('a',f)
f=rd()
for h in ('header2','header3'):
    s=S(f,'word/%s.xml'%h); s=re.sub(r'<w:r><w:rPr><w:noProof/></w:rPr><w:drawing>.*?</w:drawing></w:r>','',s,flags=re.S); f['word/%s.xml'%h]=s.encode()
wr('b',f)
f=rd(); d=S(f,'word/document.xml'); i=d.find('<w:tc>'); j=d.find('</w:tc>')
cell=d[i:j]; ps=[m.start() for m in re.finditer(r'<w:p[ >]',cell)]
cell2=cell[:ps[2]]  # keep first two paragraphs
f['word/document.xml']=(d[:i]+cell2+d[j:]).encode(); wr('c',f)
f=rd(); d=S(f,'word/document.xml'); j=d.find('</w:tbl>')
tail=d[j:]; tail=tail.replace('<w:pStyle w:val="Estilo"/>','<w:pStyle w:val="Normal"/>',2)
f['word/document.xml']=(d[:j]+tail).encode(); wr('d',f)
f=rd(); d=S(f,'word/document.xml'); k=d.find('<v:rect'); a=d.rfind('<w:p ',0,k); b=d.find('</w:p>',k)+6
print('removed para len',b-a, 'has tbl' , '<w:tbl>' in d[a:b])
f['word/document.xml']=(d[:a]+d[b:]).encode(); wr('e',f)
