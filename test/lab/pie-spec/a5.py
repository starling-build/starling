from load import *
import sys
docs=sys.argv[1:]
R={d:{} for d in docs}
for r in rows():
    if r['doc'] in docs: R[r['doc']][round(r['th'],1)]=r
for th in sorted(set().union(*[set(v) for v in R.values()])):
    s=f"{th:6.1f} "
    for d in docs:
        r=R[d].get(th)
        s+= f"| {d[4:]:6s} k{r['k']} ({r['dx']:+6.1f},{r['dy']:+6.1f}){'i' if r['io']=='in' else ' '}" if r else "|            -            "
    print(s)
