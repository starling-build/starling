import json, re, sys, collections
S=sys.argv[1]
r={}
for f in ("f756.json","flo.json"): r.update(json.load(open(f"{S}/{f}")))
# scores
sc={}
for set_,fn in (("756","test/corpus/docx/scores/linux/756.combined"),("lo","test/corpus/docx/scores/linux/lo.combined")):
    for l in open(fn):
        m=re.match(r"\s*([\d.]+)%\s+lines (\d+)/(\d+)\s+pages (\d+)/(\d+)\s+(\S+)",l)
        if m: sc[m[6]]=(set_,float(m[1]),int(m[5]))
def b(v,cuts):
    for i,c in enumerate(cuts):
        if v<c: return i
    return len(cuts)
SKIP={"bytes","paragraphs","styles","page_w","size_pt_min","size_pt_max","grid_line","empty_paragraphs","fonts","fonts_embedded","compat","list_formats","list_levels","langs","grids","footer_types","header_types","font_parts","lang_stated","header_parts","footer_parts"}
def toks(k,row,fonts=True):
    t=set()
    for n,v in row.items():
        if n in SKIP: continue
        if isinstance(v,bool):
            if v: t.add(n)
        elif isinstance(v,(int,float)):
            if n in("mode",): t.add(f"mode={v}")
            elif n in("columns","sections","table_depth"): t.add(f"{n}>={[1,2,3][min(2,b(v,[2,3]))]}" if v>1 else "") 
            elif v>0: t.add(n)
        elif isinstance(v,str): t.add(f"{n}={v}")
        elif isinstance(v,list):
            for x in v: t.add(f"{n}:{x}")
    for x in row.get("header_types",[]): t.add("hdr:"+x)
    for x in row.get("footer_types",[]): t.add("ftr:"+x)
    if row.get("fonts_embedded"): t.add("fonts_embedded")
    if fonts:
        for x in row.get("fonts",[]): t.add("font:"+x.strip())
    t.discard("")
    return frozenset(t)
keys=[k for k in r if k in sc]
def run(fonts):
    T={k:toks(k,r[k],fonts) for k in keys}
    order=sorted(keys,key=lambda k:(-len(T[k]),-sc[k][2],k))
    kept=[]; drop={}
    for k in order:
        sup=next((j for j in kept if T[k]<=T[j]),None)
        if sup is None: kept.append(k)
        else: drop[k]=sup
    # protect: <100 score
    prot=[k for k in drop if sc[k][1]<100]
    # tokens with witnesses
    cnt=collections.Counter(t for k in keys for t in T[k])
    out=collections.Counter((sc[k][0], "kept") for k in kept)
    for k in drop: out[(sc[k][0],"drop<100" if sc[k][1]<100 else "drop100")]+=1
    dup=len(keys)-len(set(T.values()))
    print(f"fonts={fonts} tokens={len(cnt)} distinct-fingerprints={len(set(T.values()))} of {len(keys)}  {dict(out)}")
    # zh only
    zk=[k for k in keys if k.startswith("zh-")]
    print("  zh distinct", len(set(T[k] for k in zk)), "of", len(zk), " zh kept", sum(1 for k in kept if k.startswith('zh-')), " zh drop@100", sum(1 for k in drop if k.startswith('zh-') and sc[k][1]>=100))
    return T,cnt,kept,drop
for f in (False,True): T,cnt,kept,drop=run(f)
json.dump({"drop":drop,"kept":kept},open(f"{S}/census-out.json","w"))
# thin features: tokens with <=2 witnesses (no fonts)
T,cnt,_,_=run(False)
thin=[t for t,c in cnt.items() if c<=2]
print("tokens with <=2 witnesses:",len(thin))
feat=["rtl","vertical_text","ruby","dropcaps","equations","smartart","charts","wordart","frames","tracked","comments","endnotes","footnotes","columns>=2","columns>=3","tables_floating","table_depth>=2","jc_distribute","even_odd","title_page","sdt","vml","wps_shapes","textboxes","fonts_embedded","landscape","mode=15","mode=14","mode=12","mode=11","grid=lines","grid=linesAndChars","grid=snapToChars","hf_textboxes","column_breaks","symbols","hyperlinks"]
for s in ("756","lo"):
    c=collections.Counter(t for k in keys if sc[k][0]==s for t in T[k])
    print(s, " ".join(f"{t}:{c.get(t,0)}" for t in feat))
sc_all=collections.Counter(t.split(':')[1] for k in keys for t in T[k] if t.startswith('scripts:'))
print("scripts", dict(sc_all))
print("langs_ea", collections.Counter(t.split(':')[1] for k in keys for t in T[k] if t.startswith('langs_ea:')).most_common(15))
print("pages", sum(v[2] for v in sc.values()), "docs", len(sc), "zh pages", sum(v[2] for k,v in sc.items() if k.startswith('zh-')))
