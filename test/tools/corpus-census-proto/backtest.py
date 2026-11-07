import json,re,subprocess,sys,collections
S=sys.argv[1]; d=json.load(open(f"{S}/census-out.json")); drop=d["drop"]; kept=set(d["kept"])
def parse(txt):
    o={}
    for l in txt.splitlines():
        m=re.match(r"\s*([\d.]+)%\s+lines.*?(\S+)\s*$",l)
        if m: o[m[2]]=float(m[1])
    return o
tot=collections.Counter(); hidden=collections.Counter(); solo=collections.Counter(); events=0; blind=0
for f in ("756.v2","lo.v2"):
    p=f"test/corpus/docx/scores/linux/{f}"
    revs=subprocess.run(["git","log","--format=%H","--",p],capture_output=True,text=True).stdout.split()[::-1]
    prev=None
    for rv in revs:
        cur=parse(subprocess.run(["git","show",f"{rv}:{p}"],capture_output=True,text=True).stdout)
        if prev:
            mv=[k for k in cur if k in prev and abs(cur[k]-prev[k])>=0.05]
            if mv:
                events+=1
                km=[k for k in mv if k in kept]
                for k in mv:
                    tot[k]+=1
                    if k in drop:
                        if drop[k] not in mv: hidden[k]+=1   # keeper did not move with it
                if not km: blind+=1   # the reduced set would have seen nothing at all
        prev=cur
print("events",events,"events the reduced set misses entirely",blind)
print("dropped docs that ever moved",sum(1 for k in drop if tot[k]),"of",len(drop),"; moved without their keeper",len(hidden))
print("top:",hidden.most_common(12))
# list blind events with the commit subject and whether it names a mover
for f in ("756.v2","lo.v2"):
    p=f"test/corpus/docx/scores/linux/{f}"
    revs=subprocess.run(["git","log","--format=%H","--",p],capture_output=True,text=True).stdout.split()[::-1]
    prev=None
    for rv in revs:
        cur=parse(subprocess.run(["git","show",f"{rv}:{p}"],capture_output=True,text=True).stdout)
        if prev:
            mv=[k for k in cur if k in prev and abs(cur[k]-prev[k])>=0.05]
            if mv and not [k for k in mv if k in kept]:
                subj=subprocess.run(["git","log","-1","--format=%s",rv],capture_output=True,text=True).stdout.strip()
                body=subprocess.run(["git","log","-12","--format=%s",rv],capture_output=True,text=True).stdout
                named=[k[:11] for k in mv if k[:11] in body or k[:8] in body]
                print(rv[:9], f, [(k[:11],prev[k],cur[k]) for k in mv], "named-in-recent-commits:",named, "|", subj[:90])
        prev=cur
