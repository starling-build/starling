import shlex,glob
a=shlex.split(open('/data/s/amd-perf/sp/dump.sh').read())
a=['-typecheck' if x=='-dump-ast' else x for x in a]
D='/data/s/amd-perf/starling/apps/OfficeApp/Sources/OfficeText/'
have=set(a)
for f in sorted(glob.glob(D+'RichLayout+Paragraph+*.swift')):
    if f not in have: a.insert(3,f)

o=[];i=0
while i<len(a):
    if a[i]=='-primary-file': i+=2; continue
    o.append(a[i]); i+=1
a=o
a.insert(3,D+'RichLayout+Paragraph.swift')
P=set(glob.glob(D+'RichLayout+Paragraph+*.swift'))
o=[]
for x in a:
    if x in P: o+=['-primary-file',x]
    else: o.append(x)
a=o
open('/data/s/amd-perf/sp/tc.sh','w').write(' '.join(shlex.quote(x) for x in a)+'\n')
