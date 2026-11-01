# test/tools/word-width-diff.py OURS_PDF_DIR WORD_PDF_DIR ID_PREFIX ascii|ide|all — per-character advance, ours vs Word, on lines whose text matches.
# ascii = both characters printable ASCII (a pure font-width test, no autospace/squeeze); ide = both ideographs. Lists (char, size, face) rows differing by >0.01 em.
# amd-6, 2026-11-01: on the 756 zh set the only ASCII row above 0.03 em was the embedded 方正仿宋_GBK "." (fixed, 9f4867d92).
import pymupdf,sys,glob,os,collections,unicodedata
od,wd,pre,MODE=sys.argv[1:5]
def lines(f):
    out=[]
    d=pymupdf.open(f)
    for p in d:
        W=p.rect.width
        L=[]
        for b in p.get_text("rawdict")["blocks"]:
            for l in b.get("lines",[]):
                cs=[(c["c"],c["origin"][0],sp["font"],sp["size"]) for sp in l["spans"] for c in sp["chars"]]
                if len(cs)>=3: L.append((p.number,round(l["bbox"][1]),round(l["bbox"][0]),l["bbox"][2],cs))
        mr=max([x[3] for x in L],default=0)
        for x in L: out.append((x,mr))
    return out
stat=collections.defaultdict(lambda:[0,0.0,0.0,set()])  # key->count,sumdiff,sumword
for wf in sorted(glob.glob(wd+'/'+pre+'*-orig.pdf')):
    k=os.path.basename(wf)[:-9]; of=os.path.join(od,k+'.pdf')
    if not os.path.exists(of): continue
    try: W=lines(wf); O=lines(of)
    except Exception: continue
    om={}
    for (pg,y,x,r,cs),mr in O: om[(pg,y,x)]=(r,cs)
    for (pg,y,x,r,cs),mr in W:
        if r>mr-3*cs[0][3]: pass
        # ragged only: line ends well short of the widest right edge on the page
        pass
        o=None
        for dy in (0,-1,1,-2,2):
            for dx in (0,-1,1):
                if (pg,y+dy,x+dx) in om: o=om[(pg,y+dy,x+dx)];break
            if o: break
        if not o: continue
        ocs=o[1]
        if "".join(c[0] for c in cs)!="".join(c[0] for c in ocs): continue
        for i in range(len(cs)-1):
            ch,x0,fw,sz=cs[i]; wadv=cs[i+1][1]-x0; oadv=ocs[i+1][1]-ocs[i][1]
            nx=cs[i+1][0]
            asc=lambda c: 0x21<=ord(c)<0x7f
            ide=lambda c: 0x4E00<=ord(c)<0xA000
            if MODE=='ascii' and not (asc(ch) and asc(nx)): continue
            if MODE=='ide' and not (ide(ch) and ide(nx)): continue
            d=(oadv-wadv)/sz
            if abs(d)>0.01:
                key=(ch,round(sz,1),fw.split('+')[-1][:22],ocs[i][2].split('+')[-1][:22])
                s=stat[key]; s[0]+=1; s[1]+=d; s[2]+=wadv/sz; s[3].add(k[:11])
            else:
                s=stat[(ch,round(sz,1),'=',cs[i][2].split('+')[-1][:22])]; s[0]+=1
rows=[(v[0],k,v) for k,v in stat.items() if k[2]!='=']
rows.sort(key=lambda r:-r[0])
print('count\tchar\tU+\tsize\tword_face\tour_face\tmean(ours-word)/em\tword_adv/em\tdocs')
for n,k,v in rows[:150]:
    print('%d\t%s\t%04X\t%s\t%s\t%s\t%+.3f\t%.3f\t%d'%(n,k[0],ord(k[0]),k[1],k[2],k[3],v[1]/n,v[2]/n,len(v[3])))
