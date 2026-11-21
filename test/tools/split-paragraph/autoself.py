import re,sys,collections
d=collections.defaultdict(set)
for l in open(sys.argv[1]):
    m=re.match(r'(\S+\.swift):(\d+):(\d+): error: (reference to property|call to method) .* requires explicit use of .self.',l)
    if m: d[m.group(1)].add((int(m.group(2)),int(m.group(3))))
for f,s in d.items():
    L=open(f).read().split('\n')
    for ln,c in sorted(s,reverse=True):
        t=L[ln-1]; L[ln-1]=t[:c-1]+'self.'+t[c-1:]
    open(f,'w').write('\n'.join(L))
print(sum(len(s) for s in d.values()),'fixed')
