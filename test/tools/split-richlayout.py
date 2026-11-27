#!/usr/bin/env python3
"""test/tools/split-richlayout.py — split apps/OfficeApp/Sources/OfficeText/RichLayout.swift into several files.

WHY: RichLayout.swift was one 22k-line file; a non-whole-module build compiles one file per
frontend job, so every build waited ~245 s for that one job (type-check 84 s, SIL 82 s, LLVM 79 s)
while 190 cores idled. Cut into extensions of 1.3-5k lines (one function, _paginate, is 4.5k alone),
the jobs run side by side: a body edit in two parts rebuilds in ~46 s.

A PURE MOVE: the class keeps its header, stored properties, initialisers and nested types;
every other class-level declaration moves, in order and byte for byte, into
`extension RichLayout { ... }` in RichLayout+<Part>.swift. The only edits are access words:
`private` / `fileprivate` on class-level (and top-level) declarations become internal, because a
private member is invisible to an extension in another file.

DETERMINISTIC, so any session can run it on its own branch and then rebase onto the split office:
the cut points are named declarations (PARTS below), not line numbers, and the chunking is a
function of the text. Usage (repo root):   test/tools/split-richlayout.py
Refuses when the file is already split.   --check: print the plan only.
"""
import re,sys,os
import re,sys
def depths(src):
    """depth of ({[ nesting at the START of each line (code only: comments and strings skipped)"""
    n=len(src); i=0; depth=0; line_depth=[0]
    stack=[]            # contexts: ('str',multi) or ('interp',paren_depth_at_entry)
    comment=0           # nested /* */
    while i<n:
        c=src[i]
        top=stack[-1] if stack else None
        if comment:
            if src.startswith('*/',i): comment-=1; i+=2; continue
            if src.startswith('/*',i): comment+=1; i+=2; continue
            if c=='\n': line_depth.append(depth)
            i+=1; continue
        if top and top[0]=='str':
            multi=top[1]
            if c=='\\' and i+1<n:
                if src[i+1]=='(':
                    stack.append(('interp',depth)); depth+=1; i+=2; continue
                i+=2; continue
            if multi and src.startswith('"""',i): stack.pop(); i+=3; continue
            if (not multi) and c=='"': stack.pop(); i+=1; continue
            if c=='\n': line_depth.append(depth)
            i+=1; continue
        # code
        if src.startswith('//',i):
            j=src.find('\n',i); i=n if j<0 else j; continue
        if src.startswith('/*',i): comment+=1; i+=2; continue
        if src.startswith('"""',i): stack.append(('str',True)); i+=3; continue
        if c=='"': stack.append(('str',False)); i+=1; continue
        if c in '({[': depth+=1
        elif c in ')}]':
            depth-=1
            if top and top[0]=='interp' and depth==top[1]: stack.pop()
        elif c=='\n': line_depth.append(depth)
        i+=1
    return line_depth
DECL=re.compile(r'^    (?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|static|class|lazy|weak|unowned|override|mutating|nonisolated(?:\([^)]*\))?|required|convenience|indirect|@\w+)\s+)*(?:func|var|let|init|deinit|struct|enum|class|typealias|subscript|protocol|extension|actor)\b')
def chunks(lines,d,start,end):
    """start..end: 0-based line indexes of the class body; returns list of (first,last) line index ranges"""
    out=[]; cur=None; pending=[]; ifdepth=0
    def flush_pending_into(c):
        pass
    i=start
    res=[]   # list of [first,last]
    pend_first=None
    for i in range(start,end):
        L=lines[i]; st=L.strip()
        if d[i]!=1:                      # inside a declaration
            if res and pend_first is None: res[-1][1]=i
            elif pend_first is not None: pend_first=pend_first  # inside after pending? can't
            continue
        if st.startswith('#if'):
            ifdepth+=1
            if ifdepth==1:
                res.append([pend_first if pend_first is not None else i,i]); pend_first=None
            else: res[-1][1]=i
            continue
        if ifdepth>0:
            res[-1][1]=i
            if st.startswith('#endif'): ifdepth-=1
            continue
        if st=='' or st.startswith('//') or st.startswith('/*') or st.startswith('*'):
            if pend_first is None: pend_first=i
            continue
        if st.startswith('@') and not DECL.match(L):
            if pend_first is None: pend_first=i
            continue
        if DECL.match(L):
            res.append([pend_first if pend_first is not None else i,i]); pend_first=None
            continue
        # continuation line at class level
        if pend_first is not None and res: res[-1][1]=i-1 if False else res[-1][1]
        if res:
            if pend_first is not None: pend_first=None
            res[-1][1]=i
    if pend_first is not None and res: res[-1][1]=end-1
    # make ranges contiguous: extend each chunk's last to just before next first
    for k in range(len(res)-1): res[k][1]=res[k+1][0]-1
    return res

PATH='apps/OfficeApp/Sources/OfficeText/RichLayout.swift'
# (file suffix, regex that the FIRST class-level declaration of the part matches)
PARTS=[
  ('Layout',     None),
  ('Paginate',   r'func _paginate\('),
  ('Paragraph',  r'func _layoutParagraphOnce\('),
  ('Span',       r'func _span\(for p: RichParagraph'),
  ('Lines',      r'func _strut\(_ span: TextSpan'),
  ('EastAsian',  r'func _fitEastAsianLines\('),
  ('Paint',      r'static var objectPainter'),
  ('HeaderFooter', r'struct _HeaderFooter'),
]
KEEP_HEAD=re.compile(r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|weak|unowned|lazy|nonisolated(?:\([^)]*\))?)\s+)*(?:(var|let)\b|init\b|deinit\b|struct\b|enum\b|class\b|typealias\b|protocol\b)')
STATIC=re.compile(r'\bstatic\b')
def head_of(lines,a,b):
    for i in range(a,b+1):
        if DECL.match(lines[i]) or lines[i].strip().startswith('#if'): return i
    return a
def is_kept(lines,d,a,b):
    h=head_of(lines,a,b); L=lines[h]
    if L.strip().startswith('#if'): return False
    if STATIC.search(L.split('=')[0].split('{')[0]) and not re.match(r'^\s*(?:\w+\s+)*(?:struct|enum|class)\b',L): return False   # static: movable (static stored properties are fine in an extension)
    m=KEEP_HEAD.match(L)
    if not m: return False
    if m.group(1):                                   # var / let: stored unless computed
        t=L[m.end():]
        j=t.find('='); k=t.find('{')
        if k>=0 and (j<0 or k<j):
            # a property with observers and no initial value is still stored
            blk='\n'.join(lines[h:b+1])
            return bool(re.search(r'\{\s*(?:didSet|willSet)\b',blk)) and not re.search(r'\b(?:get|set)\s*[{(]',blk)
        return True
    return True
ACC=re.compile(r'^(\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|open|final|static|class|lazy|weak|unowned|override|mutating|nonisolated(?:\([^)]*\))?|nonisolated\(unsafe\))\s+)*)(?:private|fileprivate)(\(set\))?\s+')
def open_access(line):
    # `private` / `fileprivate` -> internal (nothing); `public private(set)` -> `public internal(set)`
    m=ACC.match(line)
    if not m: return line
    pre=m.group(1)
    if m.group(2): return pre+'internal(set) '+line[m.end():]
    return pre+line[m.end():]
def main():
    check='--check' in sys.argv
    src=open(PATH,encoding='utf8').read()
    if os.path.exists(os.path.join(os.path.dirname(PATH),'RichLayout+Paginate.swift')): sys.exit('already split')
    lines=src.split('\n'); d=depths(src)
    cls=next(i for i,l in enumerate(lines) if l.startswith('public final class RichLayout'))
    end=len(lines)-1
    while lines[end].strip()!='}': end-=1
    ch=chunks(lines,d,cls+1,end)
    starts=[0]
    for name,rx in PARTS[1:]:
        r=re.compile(rx)
        idx=[k for k,(a,b) in enumerate(ch) if r.search(lines[head_of(lines,a,b)])]
        if len(idx)!=1: sys.exit('anchor %s matches %d chunks'%(name,len(idx)))
        starts.append(idx[0])
    if starts!=sorted(starts): sys.exit('anchors out of order')
    part_of=[max(p for p,s in enumerate(starts) if s<=k) for k in range(len(ch))]
    kept=[]; moved={p:[] for p in range(len(PARTS))}
    for k,(a,b) in enumerate(ch):
        text=lines[a:b+1]
        text=[open_access(l) if d[a+i]==1 else l for i,l in enumerate(text)]
        (kept if is_kept(lines,d,a,b) else moved[part_of[k]]).append((k,text))
    if check:
        print('chunks',len(ch),'kept',len(kept),sum(len(t) for _,t in kept),'lines')
        for p,(n,_) in enumerate(PARTS): print(n,len(moved[p]),'chunks',sum(len(t) for _,t in moved[p]),'lines')
        return
    imports=[l for l in lines[:cls] if l.startswith('import ')]
    top=[open_access(l) if (d[i]==0 and re.match(r'^(?:private|fileprivate)\s',l)) else l for i,l in enumerate(lines[:cls+1])]
    out=top+[l for _,t in kept for l in t]+['}','']
    dirn=os.path.dirname(PATH)
    for p,(n,_) in enumerate(PARTS):
        if not moved[p]: continue
        body=[l for _,t in moved[p] for l in t]
        txt=['// Copyright the Starling authors','// SPDX-License-Identifier: Apache-2.0','',
             '// RichLayout, part "%s": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that'%n,
             '// the parts compile side by side).','']+imports+['','extension RichLayout {']+body+['}','']
        open(os.path.join(dirn,'RichLayout+%s.swift'%n),'w',encoding='utf8').write('\n'.join(txt))
    open(PATH,'w',encoding='utf8').write('\n'.join(out))
main()
