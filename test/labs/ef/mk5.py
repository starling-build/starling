import re,zipfile
exec(open('mk.py').read().split("variant('ef4a.docx'")[0])
def tbl(b,fn):
    s=b.index('<w:tbl>',b.index('Als twe')); e=b.index('</w:tbl>',s)+8
    return b[:s]+fn(b[s:e])+b[e:]
def dr(t,which):  # which 0 square, 1 tb
    ds=list(re.finditer(r'<w:r>(?:(?!</w:r>).)*?<w:drawing>.*?</w:drawing></w:r>',t,flags=re.S))
    m=ds[which]; return t[:m.start()]+t[m.end():]
def wrapnone(t,which):
    ds=list(re.finditer(r'<wp:wrap(Square[^>]*|TopAndBottom)/?>',t)); m=ds[which]
    return t[:m.start()]+'<wp:wrapNone/>'+t[m.end():]
def inline(t,which):
    ds=list(re.finditer(r'<wp:anchor [^>]*>.*?<wp:docPr',t,flags=re.S)); m=ds[which]
    seg=m.group(0)
    ext=re.search(r'<wp:extent [^>]*/>',seg).group(0)
    new='<wp:inline distT="0" distB="0" distL="0" distR="0">'+ext+'<wp:docPr'
    t=t[:m.start()]+new+t[m.end():]
    # closing tag: first </wp:anchor> after
    i=t.index('</wp:anchor>',m.start()); return t[:i]+'</wp:inline>'+t[i+12:]
V={'ef5a':lambda b:tbl(b,lambda t:dr(t,0)),            # only tb kept
   'ef5b':lambda b:tbl(b,lambda t:dr(t,1)),            # only square kept
   'ef5c':lambda b:tbl(b,lambda t:wrapnone(wrapnone(t,0),0) if False else wrapnone(t,0)),  # square -> no wrap (tb kept)
   'ef5d':lambda b:tbl(b,lambda t:inline(inline(t,1),0))} # both inline
for n,f in V.items(): variant(n+'.docx',f)
