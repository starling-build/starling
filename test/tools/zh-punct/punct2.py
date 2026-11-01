import sys, os, unicodedata, fitz, glob, collections
W='/home/starling/dev/starling-lo5/test/corpus/docx/word-win'; O=os.path.expanduser('~/tmp/lo5/full-base13/pdf')
P=set('，。、；：！？）》」』】〕”’…—·')
Q=set('（《「『【〔“‘')
def lines(path):
    d=fitz.open(path); out=[]
    for pn,pg in enumerate(d):
        ls=[]
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(s['text'] for s in l['spans'])
                t=unicodedata.normalize('NFKC',t); t=''.join(t.split())
                if t: ls.append((round(l['bbox'][3]),t))
        ls.sort(); out.append([t for _,t in ls])
    return out
rows=[]
for wp in sorted(glob.glob(W+'/zh-*.pdf')):
    k=os.path.basename(wp)[:-4].replace("-orig",""); op=os.path.join(O,k+".pdf")
    if not os.path.exists(op): continue
    try: a=lines(wp); b=lines(op)
    except Exception: continue
    for pn,(pa,pb) in enumerate(zip(a,b)):
        for x,y in zip(pa,pb):
            if x==y: continue
            s,l=(x,y) if len(x)<len(y) else (y,x)
            if 0<len(l)-len(s)<=2 and l.startswith(s):
                extra=l[len(s):]; last=s[-1]
                if any(c in P or c in Q for c in extra+last):
                    who='WORD_LONGER' if len(x)>len(y) else 'OURS_LONGER'
                    rows.append((k[:11],pn,who,s[-6:],extra))
c=collections.Counter((r[2]) for r in rows); print(c)
docs=collections.defaultdict(list)
for r in rows: docs[r[0]].append(r)
print(len(docs),'documents')
for k,v in sorted(docs.items(),key=lambda x:-len(x[1])):
    print(k,len(v),collections.Counter(r[2] for r in v))
print()
for r in rows[:60]: print(r)
