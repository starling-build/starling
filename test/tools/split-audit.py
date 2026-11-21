#!/usr/bin/env python3
"""Hunk audit for the RichLayout+Paragraph split: every non-blank line of the ORIGINAL Paragraph.swift (git ref in argv[1],
default origin/main) must be present, as a multiset, in the split files (self/rl/Self/RichLayout prefixes are normalised).
Usage: test/tools/split-audit.py [ref]   (run from the checkout holding the split files)"""
import re,subprocess,sys,glob,collections
ref=sys.argv[1] if len(sys.argv)>1 else 'origin/main'
D='apps/OfficeApp/Sources/OfficeText/'
orig=subprocess.check_output(['git','show',ref+':'+D+'RichLayout+Paragraph.swift'],text=True).split('\n')
new=[]
for f in glob.glob(D+'RichLayout+Paragraph*.swift'): new+=open(f).read().split('\n')
def n(l):
    s=re.sub(r'\b(self|rl|Self|RichLayout)\.','',re.sub(r'return true\b','return',l)).strip()
    m=re.match(r'^(?:var |let )?\w+(?:: [^=]+?)? = (.*)$',s)   # a local declaration became a field assignment: compare the right side
    return '= '+m.group(1) if m else s
c=collections.Counter(n(l) for l in new if l.strip())
miss=[]
for i,l in enumerate(orig,1):
    if not l.strip(): continue
    k=n(l)
    if c[k]>0: c[k]-=1
    else: miss.append((i,l.strip()[:100]))
print('original lines missing from the split:',len(miss))
for m in miss[:20]: print(m)
sys.exit(1 if miss else 0)
