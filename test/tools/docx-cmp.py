#!/usr/bin/env python3
# cmp.py NEW.match OLD.match [thr] — per-document movers (any change ≥ thr, default 0.05), means over docs WITH text and all docs
import re,sys
def load(p):
    d={}
    for l in open(p):
        m=re.match(r'\s*([\d.]+)%\s+lines (\d+)/(\d+)\s+pages (\d+)/(\d+)\s+(\S+)',l)
        if m: d[m.group(6)]=(float(m.group(1)),int(m.group(2)),int(m.group(3)),int(m.group(4)),int(m.group(5)))
    return d
def mean(d,keys,text):
    v=[d[k][0] for k in keys if k in d and (not text or d[k][2]>0)]
    return (sum(v)/len(v) if v else 0.0),len(v)
a,b=load(sys.argv[1]),load(sys.argv[2]); thr=float(sys.argv[3]) if len(sys.argv)>3 else 0.05
keys=sorted(set(a)&set(b))
for n,d in(("NEW",a),("OLD",b)):
    t=mean(d,keys,True);al=mean(d,keys,False)
    print(f"{n}: {len(keys)} docs, mean with text {t[0]:.3f} (n={t[1]}), all {al[0]:.3f}, >=95 {sum(1 for k in keys if d[k][0]>=95)}, 100% {sum(1 for k in keys if d[k][0]>=99.95)}, pages equal {sum(1 for k in keys if d[k][3]==d[k][4])}")
# a mover is any change in matched lines / total lines / pages matched (the printed percentage is rounded to 0.1)
def r(d,k): return d[k][0]
mv=[k for k in keys if a[k]!=b[k]]
up=[(r(a,k)-r(b,k),k) for k in mv if r(a,k)>r(b,k) or (r(a,k)==r(b,k) and (a[k][1],a[k][3])>(b[k][1],b[k][3]))]; dn=[(r(a,k)-r(b,k),k) for k in mv if (r(a,k)<r(b,k)) or (r(a,k)==r(b,k) and (a[k][1],a[k][3])<(b[k][1],b[k][3]))]
other=[k for k in mv if k not in {x[1] for x in up}|{x[1] for x in dn}]
pg=[k for k in keys if a[k][3]!=b[k][3] or a[k][4]!=b[k][4]]
print(f"up {len(up)}  down {len(dn)}  pagecount-changed {len(pg)}  missing-in-new {len(set(b)-set(a))}")
for dv,k in sorted(dn): print(f"  DOWN {b[k][0]:6.1f} -> {a[k][0]:6.1f}  lines {b[k][1]}/{b[k][2]} -> {a[k][1]}/{a[k][2]}  {k}")
for dv,k in sorted(up,reverse=True): print(f"  UP   {b[k][0]:6.1f} -> {a[k][0]:6.1f}  lines {b[k][1]}/{b[k][2]} -> {a[k][1]}/{a[k][2]}  {k}")
for k in other: print(f"  CHANGED(same ratio) {k}: {b[k][1:]} -> {a[k][1:]}")
for k in pg: print(f"  PAGES {k}: {b[k][3]}/{b[k][4]} -> {a[k][3]}/{a[k][4]}")
