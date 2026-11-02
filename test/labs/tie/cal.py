import pymupdf, json, sys
V={'a':(18,True),'b':(26,False),'c':(8,True),'d':(18,True)}
out={}
for var,(n,lat) in V.items():
    for m in (12,15):
        p=pymupdf.open('cal/cal-%s-m%d-orig.pdf'%(var,m))[0]
        ch=[]
        for b in p.get_text('rawdict')['blocks']:
            if b['type']==0:
                for l in b['lines']:
                    for s in l['spans']:
                        ch+=[(c['c'],c['origin'][0]) for c in s['chars']]
        # find X (的) then next char
        k=[i for i,c in enumerate(ch) if c[0]=='的'][0]
        nat=ch[k+1][1]-ch[0][1]
        out['%s-m%d'%(var,m)]=nat
        print(var,m,len(ch),'first',round(ch[0][1],3),'X',round(ch[k][1],3),'next',round(ch[k+1][1],3),'nat',round(nat,3), 'pitch ideo', round(ch[1][1]-ch[0][1],3))
json.dump(out,open('cal.json','w'))
