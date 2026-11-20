from load import *
from collections import defaultdict
D=defaultdict(dict)
for r in rows():
    if r['doc']!='pl3-rev': D[r['doc']][round(r['th'],1)]=r
for d,m in sorted(D.items()):
    if 157.5 not in m or 202.5 not in m or m[157.5]['io']!='OUT': continue
    a=m[157.5]; b=m[202.5]; c=m.get(247.5); w=a['w']; h=a['h']
    legtop=a['leg']-a['pcy']
    g6 = (a['dy']-h/2) - (c['dy']+c['h']/2) if c else float('nan')
    print(f"{d:10s} R{a['R']:5.1f} w{w:4.1f} | 4:({a['dx']:+5.1f},{a['dy']:+5.1f}) 5:({b['dx']:+5.1f},{b['dy']:+5.1f}) dy5-dy4 {b['dy']-a['dy']:+5.1f} | gap45 {2*(a['dx']-w/2):5.1f} legGap {legtop-a['dy']-h/2:5.1f} gap6 {g6:5.1f} 6:{c['io'] if c else '-'} 6dy {c['dy'] if c else 0:+5.1f} | 5 right-anchor {b['dx']+w/2+a['R']*math.sin(math.radians(22.5)):+5.1f}")
