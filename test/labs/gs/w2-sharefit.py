import sys,re,unicodedata,importlib.util
sys.stdout.reconfigure(encoding="utf-8")
spec=importlib.util.spec_from_file_location("lm","test/docx-line-match.py"); lm=importlib.util.module_from_spec(spec); spec.loader.exec_module(lm)
trace,ref=sys.argv[1],sys.argv[2]; CELL=float(sys.argv[3]) if len(sys.argv)>3 else 17.007568359375
norm=lambda t:"".join(c for c in unicodedata.normalize("NFKC",t) if not c.isspace()).replace("￼","")
# paragraphs: list of pieces with decisions
paras=[];cur=None
for l in open(trace,encoding="utf-8"):
    if l.startswith("width"): cur={"col":float(re.search(r"column ([\d.]+)",l).group(1)),"pieces":[]}; paras.append(cur)
    elif l.startswith("fit ["):
        m=re.match(r"fit \[(.*)\] w ([-\d.e]+) x ([-\d.e]+) of ([\d.]+) fits (\w+)",l); cur["pieces"].append({"t":m.group(1),"w":float(m.group(2)),"x":float(m.group(3)),"fits":m.group(5)=="true"})
    elif l.startswith("    over"):
        m=re.search(r"over ([-\d.e]+) hang ([-\d.e]+) need ([-\d.e]+) room ([-\d.e]+) of (\d+) marks.*taken (\w+) — (\d+) characters of ([\d.]+) ems, (\d+) spaces, other (\w+)",l)
        cur["pieces"][-1].update(dict(over=float(m.group(1)),hang=float(m.group(2)),need=float(m.group(3)),room=float(m.group(4)),marks=int(m.group(5)),taken=m.group(6)=="true",n=int(m.group(7)),ems=float(m.group(8)),gaps=int(m.group(9)),other=m.group(10)=="true"))
seen=set(); uniq=[]
for p in paras:
    t="".join(x["t"] for x in p["pieces"])
    if t in seen or not p["pieces"]: continue
    seen.add(t); p["text"]=t; uniq.append(p)
W=[norm(r[3]) for r in lm.lines(None,ref)]
def wbreaks(P):
    for i,t in enumerate(W):
        q=next((q for q in range(0,7) if len(t)-q>=4 and P.startswith(t[q:])),None)
        if q is not None:
            o=len(t)-q; br={o}; j=i+1; skips=0
            while o<len(P) and j<len(W) and skips<4:
                if W[j] and P.startswith(W[j],o): o+=len(W[j]); br.add(o); skips=0
                else: skips+=1
                j+=1
            return br
    return None
rows=[]
for p in uniq:
    P=norm(p["text"])
    if len(P)<8: continue
    br=wbreaks(P)
    if br is None: continue
    breaks=br; at=0
    off=0; linestart=0
    for xi,x in enumerate(p["pieces"]):
        L=len(norm(x["t"]))
        nxt=p["pieces"][xi+1] if xi+1<len(p["pieces"]) else None
        x["taken"]=bool(nxt and nxt["x"]>=p["col"]-0.01) if "need" in x else x.get("taken")
        if "need" in x and x.get("room",0)>0 and x["over"]>0.01:
            # our line starts at linestart; Word must agree
            if linestart==0 or (at+linestart) in breaks:
                if (at+off) in breaks: wv=False
                elif any((at+off+k) in breaks for k in range(1,L+1)) or True: wv=not ((at+off) in breaks)
                mark_room=x["room"]-x["gaps"]*CELL/8
                stretch=p["col"]-x["x"]
                lhs=x["need"]*(x["ems"]*(x["n"]-1)/x["n"]/64+x["gaps"]*CELL/4*0.44); rhs=mark_room*stretch
                rows.append((x["t"],x["need"],x["room"],mark_room,x["marks"],x["gaps"],stretch,lhs/rhs if rhs>0 else 99,x["taken"],wv,p["text"][max(0,off-6):off]))
        if x["fits"]==False and "need" in x:
            linestart = off if not x.get("taken") else off+L
        off+=L
for r in sorted(rows,key=lambda r:r[7]):
    print(f"{r[7]:6.3f} ours {'T' if r[8] else 'R'} word {'T' if r[9] else 'R'} {'  ' if r[8]==r[9] else '!!'} need {r[1]:6.2f} room {r[2]:6.2f} mk {r[3]:6.2f}/{r[4]} gaps {r[5]} str {r[6]:6.2f}  …{r[10]}[{r[0]}]")
