import zipfile,os,sys,re
out=sys.argv[1];os.makedirs(out,exist_ok=True)
z=zipfile.ZipFile('orig.docx');f={n:z.read(n) for n in z.namelist()}
d=f['word/document.xml'].decode()
def tbl_span(pos):
    s=d.rfind('<w:tbl>',0,pos); e=d.find('</w:tbl>',pos)+8
    assert d.count('<w:tbl>',s+1,e)==0
    return s,e
A=tbl_span(79598); B=tbl_span(112851)
fr_re=re.compile(r'<w:framePr w:hSpace="180" w:wrap="around" w:vAnchor="text" w:hAnchor="text" w:y="1"/>')
def mk(name,rmframe=False,rmA=False,rmB=False):
    s=d
    spans=[]
    if rmA: spans.append(A)
    if rmB: spans.append(B)
    for a,b in sorted(spans,reverse=True): s=s[:a]+s[b:]
    if rmframe:
        # only frames in W row 2 (positions 76876..79240)
        lo,hi=76876,79240
        seg=d[lo:hi]; assert seg.count('<w:framePr')==5
        seg2=fr_re.sub('',seg); assert seg2.count('<w:framePr')==0
        # reapply: build from s with positions shifted -> do replace on first occurrence block of the 5 paragraphs
        i=s.find(seg); assert i>0
        s=s[:i]+seg2+s[i+len(seg):]
    g=dict(f);g['word/document.xml']=s.encode()
    with zipfile.ZipFile(os.path.join(out,name+'.docx'),'w',zipfile.ZIP_DEFLATED) as o:
        for k,v in g.items(): o.writestr(k,v)
mk('v1');mk('v2',rmframe=True);mk('v3',rmA=True);mk('v4',rmB=True);mk('v5',rmA=True,rmB=True)
print('ok')
