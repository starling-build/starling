import sys; sys.path.insert(0,'.')
from meas import lines
from collections import defaultdict
L=[t for _,t in lines('run/hyE-probes-orig.pdf')]
# paragraphs: line starting with 'i' run; probe words
frag=defaultdict(set); full=defaultdict(int)
for t in L:
    if t.endswith('-') and ' ' in t: frag[t.split(' ')[-1]].add(1)
print(sorted(frag))
import collections
c=collections.Counter(t.split(' ')[-1] for t in L if t.endswith('-') and ' ' in t)
print(c)
