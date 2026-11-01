import re,sys
def load(f):
    d={}
    for l in open(f):
        m=re.match(r'\s*([\d.]+)%\s+lines\s+(\d+)/(\d+).*?\s(\S+)$',l)
        if m: d[m.group(4)]=float(m.group(1))
    return d
new=load(sys.argv[1]); old=load("/tmp/docx-pair-mac/fix/756.v2")
up=down=0;rows=[]
for k,v in new.items():
    o=old.get(k)
    if o is None: continue
    if abs(v-o)>=0.05: rows.append((v-o,k[:11],o,v))
    up+=v>o+0.04; down+=v<o-0.04
print("docs",len(new),"up",up,"down",down)
for r in sorted(rows): print("  %+.2f %s %.1f -> %.1f"%r)
