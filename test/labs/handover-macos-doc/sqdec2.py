import re,sys,unicodedata,fitz
tr=open(sys.argv[1],errors='replace').read().split('\n')
doc=fitz.open(sys.argv[2])
nf=lambda s: unicodedata.normalize("NFKC",s)
lines=set(); 
for pg in doc:
    for b in pg.get_text("dict")["blocks"]:
        for l in b.get("lines",[]):
            t="".join(s["text"] for s in l["spans"]).replace(" ","").replace("　","")
            lines.add(nf(t))
lines=sorted(lines)
def starts(p): return any(l.startswith(p) for l in lines)
def eq(p): return any(l==p for l in lines)
hist=[];lastx=-1;W=0
out=[]
for l in tr:
    m=re.match(r'width [\d.]+: column ([\d.]+)pt',l)
    if m: W=float(m.group(1)); hist=[]; lastx=-1; continue
    m=re.match(r'fit \[(.*)\] w ([\d.]+) x ([\d.]+) of ([\d.]+) fits (true|false) marks (\d+)\+(\d+)',l)
    if m:
        x=float(m.group(3))
        if x<lastx-0.5: hist=[]
        lastx=x
        hist.append((m.group(1),float(m.group(2)),x,float(m.group(4)),m.group(5)))
        continue
    m=re.match(r'\s+over ([\d.]+) hang ([\d.]+) need ([\d.]+) room ([\d.]+) of (\d+) marks, lead ([\d.]+) set ([\d.]+) taken (true|false) — (\d+) characters of ([\d.]+) ems, (\d+) spaces',l)
    if m and hist:
        cand=nf(hist[-1][0].replace(" ",""))
        prefix=nf("".join(h[0] for h in hist[:-1]).replace(" ",""))
        tk=m.group(8)=='true'
        wtook=starts(prefix+cand); wend=eq(prefix) or (starts(prefix) and not wtook)
        sr=hist[-1][3]-hist[-1][2]
        verdict = 'OK' if (tk==wtook) else ('OURS-TOO-LONG' if tk else 'WORD-LONGER')
        if not wtook and not wend: verdict='??'
        out.append((verdict,float(m.group(3)),float(m.group(4)),int(m.group(5)),round(sr,2),int(m.group(9)),int(m.group(11)),tk,cand,prefix[-8:]))
import collections
print(collections.Counter(o[0] for o in out))
for o in sorted(set(out),key=lambda o:(o[0],o[1])): 
    if o[0] in ('OURS-TOO-LONG','WORD-LONGER') or '-v' in sys.argv: print(*o)
