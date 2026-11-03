import zipfile,re,sys,os
src,out=sys.argv[1],sys.argv[2]; os.makedirs(out,exist_ok=True)
z=zipfile.ZipFile(src); F=[(i.filename,z.read(i.filename)) for i in z.infolist()]
def save(name,sheet):
    with zipfile.ZipFile(os.path.join(out,name+'.xlsx'),'w',zipfile.ZIP_DEFLATED) as o:
        for fn,b in F:
            if fn=='xl/worksheets/sheet1.xml': b=sheet.encode('utf8')
            if fn=='xl/calcChain.xml' and name!='a0': continue
            if fn=='[Content_Types].xml' and name!='a0': b=re.sub(rb'<Override[^>]*calcChain[^>]*/>',b'',b)
            if fn=='xl/_rels/workbook.xml.rels' and name!='a0': b=re.sub(rb'<Relationship [^>]*calcChain[^>]*/>',b'',b)
            o.writestr(fn,b)
S=dict(F)['xl/worksheets/sheet1.xml'].decode('utf8')
save('a0',S)
base=re.sub(r'<f[^>]*/>|<f[^>]*>.*?</f>','',S)
base=re.sub(r'<row r="(\d+)".*?</row>',lambda m:m.group(0) if int(m.group(1))<=21 else '',base,flags=re.S)
base=base.replace('A1:C721','A1:C21')
save('a',base)
save('b',base.replace('defaultRowHeight="12.75"','defaultRowHeight="15"'))
save('c',re.sub(r'<sheetFormatPr[^>]*/>','',base))
def data(s,f): return re.sub(r'<c r="([A-C])(\d+)" s="3"( t="s")?>',lambda m:f(m) if int(m.group(2))>1 else m.group(0),s)
# d: text cells
d=re.sub(r'<c r="([A-C])(\d+)" s="3"><v>([^<]*)</v></c>',lambda m:'<c r="%s%s" t="str"><v>%s</v></c>'%(m.group(1),m.group(2),m.group(3)),base)
d=d.replace(' style="3"','')
save('d',d)
e=base.replace(' s="3"','').replace(' style="3"','')
save('e',e)
f=base.replace(' s="1" customFormat="1"','').replace(' s="2"','')
save('f',f)
print(sorted(os.listdir(out)))
