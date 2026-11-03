import re,zipfile,shutil,os
SRC='/data/s/amd-5/starling/test/corpus/docx/lo/docs/lo-a197b7a87126ba68.docx'
z=zipfile.ZipFile(SRC)
x=z.read('word/document.xml').decode('utf8')
tb=[m.start() for m in re.finditer('<w:tbl>',x)]
te=[m.end() for m in re.finditer('</w:tbl>',x)]
A,B=tb[5],te[5]
T=x[A:B]
def labels(t,f):
    return re.sub(r'<w:p [^>]*>(?:(?!</w:p>).)*?framePr(?:(?!</w:p>).)*</w:p>',lambda m:f(m.group(0)),t)
V={}
V['style']=labels(T,lambda p:p.replace('AlertLabelinList1','AlertLabel'))
V['noframe']=labels(T,lambda p:p.replace('<w:framePr w:wrap="notBeside"/>',''))
V['tblstyle']=T.replace('<w:tblStyle w:val="ProcedureTable"/>','',1)
V['mar']=T.replace('<w:tblLook','<w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar><w:tblLook',1)
V['tcw']=T.replace('<w:tcW w:w="8856" w:type="dxa"/>','<w:tcW w:w="8280" w:type="dxa"/>',1)
V['shd']=T.replace('<w:tcW w:w="8856" w:type="dxa"/>','<w:tcW w:w="8856" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>',1)
V['rpr']=labels(T,lambda p:p.replace('<w:r><w:t xml:space="preserve">','<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">'))
# label first in cell: move the first label paragraph to the start of the cell
def first(t):
    m=re.search(r'<w:p [^>]*>(?:(?!</w:p>).)*?framePr(?:(?!</w:p>).)*</w:p>',t)
    p=m.group(0); t=t[:m.start()]+t[m.end():]
    i=t.index('</w:tcPr>')+len('</w:tcPr>')
    return t[:i]+p+t[i:]
V['first']=first(T)
V['width0']=T.replace('<w:tblW w:w="0" w:type="auto"/>','<w:tblW w:w="8856" w:type="dxa"/>',1)
os.makedirs('out',exist_ok=True)
for k,t in V.items():
    assert t!=T,k
    nx=x[:A]+t+x[B:]
    o=zipfile.ZipFile(f'out/lbl-{k}.docx','w',zipfile.ZIP_DEFLATED)
    for i in z.infolist():
        o.writestr(i.filename,nx.encode('utf8') if i.filename=='word/document.xml' else z.read(i.filename))
    o.close()
print(sorted(V))
