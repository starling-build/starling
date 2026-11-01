import sys,fitz,collections,statistics
def isc(c): return '一'<=c<='鿿'
def isd(c): return c.isascii() and c.isdigit()
def isl(c): return c.isascii() and c.isalpha()
def run(pdf,base):
    doc=fitz.open(pdf); out=collections.defaultdict(list)
    for pg in doc:
        for b in pg.get_text("rawdict")["blocks"]:
            for l in b.get("lines",[]):
                ch=[(c["c"],c["origin"][0]) for s in l["spans"] for c in s["chars"]]
                for i in range(len(ch)-3):
                    c,x=ch[i]
                    if not isc(c): continue
                    n=ch[i+1]; n2=ch[i+2]; n3=ch[i+3]
                    if isd(n[0]) and isc(n2[0]):
                        out['C D C: C adv'].append(n[1]-x-base)
                        out['C D C: D adv'].append(n2[1]-n[1])
                    elif isd(n[0]) and n2[0]==' ' and isc(n3[0]):
                        out['C D _ C: C adv'].append(n[1]-x-base)
                        out['C D _ C: D adv'].append(n2[1]-n[1])
                        out['C D _ C: _ adv'].append(n3[1]-n2[1])
                    elif isd(n[0]) and isd(n2[0]) and isc(n3[0]):
                        out['C DD C: C adv'].append(n[1]-x-base)
                    elif isl(n[0]) and isc(n2[0]):
                        out['C L C: C adv'].append(n[1]-x-base)
    for k,v in sorted(out.items()):
        print(f'  {k:18s} n={len(v):4d} median={statistics.median(v):6.2f}  min={min(v):6.2f} max={max(v):6.2f}')
base=float(sys.argv[2])
print('WORD'); run(sys.argv[1],base)
print('OURS'); run(sys.argv[3],base)
