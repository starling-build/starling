import pymupdf,sys
for n,f in (("ours",sys.argv[1]),("word",sys.argv[2])):
    d=pymupdf.open(f); print(n,len(d),"pages")
    for p in d:
        for b in p.get_text("dict")["blocks"]:
            for l in b.get("lines",[]):
                t="".join(s["text"] for s in l["spans"])
                if t.strip(): print(p.number+1,[round(x,1) for x in l["bbox"]],t[:50])
