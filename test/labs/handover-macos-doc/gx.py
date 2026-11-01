import sys,fitz
pdf,key=sys.argv[1],sys.argv[2]
doc=fitz.open(pdf)
for pn,pg in enumerate(doc):
    d=pg.get_text("rawdict")
    for b in d["blocks"]:
        for l in b.get("lines",[]):
            ch=[c for s in l["spans"] for c in s["chars"]]
            t="".join(c["c"] for c in ch)
            if key in t:
                print("page",pn+1,"y",round(l["bbox"][1],1),"size",l["spans"][0]["size"],l["spans"][0]["font"])
                prev=None
                out=[]
                for c in ch:
                    x=c["origin"][0]
                    out.append(f'{c["c"]}{x:.2f}')
                print(" ".join(out))
                xs=[c["origin"][0] for c in ch]
                print("advances:"," ".join(f'{c["c"]}{(xs[i+1]-xs[i]):.2f}' for i,c in enumerate(ch[:-1])))
                raise SystemExit
