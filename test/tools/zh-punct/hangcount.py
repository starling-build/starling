import pymupdf,glob,os,unicodedata,collections,sys
W='/home/starling/dev/starling-lo5/test/corpus/docx/word-win'; O=os.path.expanduser('~/tmp/lo5/full-base19/pdf')
CL=set('”’」』）》〕】')
def hangs(path):
    d=pymupdf.open(path); out=collections.Counter(); tot=collections.Counter()
    for pg in d:
        ls=[]
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(s['text'] for s in l['spans']).rstrip()
                if len(t)>5: ls.append((l['bbox'][2],t))
        if len(ls)<5: continue
        c=collections.Counter(round(r) for r,_ in ls); m=c.most_common(1)[0][0]
        for r,t in ls:
            ch=unicodedata.normalize('NFKC',t[-1])
            ch=t[-1]
            if ch in CL:
                tot[ch]+=1
                if r>m+1.0: out[ch]+=1
    return out,tot
wh=collections.Counter(); wt=collections.Counter(); oh=collections.Counter(); ot=collections.Counter()
for wp in sorted(glob.glob(W+'/zh-*-orig.pdf')):
    k=os.path.basename(wp)[:-9]; op=f"{O}/{k}.pdf"
    if not os.path.exists(op): continue
    try: a,b=hangs(wp); c,d=hangs(op)
    except Exception: continue
    wh+=a; wt+=b; oh+=c; ot+=d
for ch in CL: print(ch,'Word hang/ends',wh[ch],wt[ch],' ours',oh[ch],ot[ch])
