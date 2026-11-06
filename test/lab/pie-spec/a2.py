from load import *
from collections import defaultdict
D=defaultdict(list)
for r in rows(): D[r['doc']].append(r)
for doc,rs in D.items():
    r0=rs[0]; s=f"{doc:11s} n{r0['n']} R{r0['R']:5.1f} cx{r0['pcx']:6.1f} |"
    for r in rs:
        if r['io']!='OUT': s+=f" {r['th']:5.1f}:in   "; continue
        x,y=closest(r['dx'],r['dy'],r['w'],r['h']); ph=math.degrees(math.atan2(x,-y))%360
        s+=f" {r['th']:5.1f}:{(ph-r['th']+180)%360-180:+5.1f}/{math.hypot(x,y)-r['R']:+4.1f}"
    print(s)
