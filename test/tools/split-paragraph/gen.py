#!/usr/bin/env python3
"""Split RichLayout._layoutParagraphBody into a frame class + chunk methods (mechanical).
usage: gen.py ast.out OUTDIR   (reads/rewrites RichLayout+Paragraph.swift in the checkout)"""
import re,sys,os
AST,ROOT=sys.argv[1],sys.argv[2]
D=ROOT+'/apps/OfficeApp/Sources/OfficeText/'
F=D+'RichLayout+Paragraph.swift'
CH=int(os.environ.get('CHUNK','260'))
L=open(F).read().split('\n')
s=next(i for i,l in enumerate(L) if l.startswith('    func _layoutParagraphBody'))
e=next(i for i in range(s+1,len(L)) if L[i]=='    }')
A=open(AST,errors='replace').read().split('\n')
st=next(i for i,l in enumerate(A) if '(func_decl' in l and '"_layoutParagraphBody(' in l)
j=st+1
while not re.match(r'^ {0,4}\(',A[j]): j+=1
sub=A[st:j]
ctx=re.search(r'decl_context=(0x\w+)',sub[2]).group(1)
# --- fields: indent-8 var_decls
fields={}
for l in sub:
    m=re.match(r'^( {8})\(var_decl decl_context=(0x\w+) range=\[[^:]+:(\d+):\d+.*?"([^"]+)" interface_type="((?:[^"\\]|\\.)*)"',l)
    if m and m.group(2)==ctx:
        fields[m.group(4)]=(m.group(5).replace('\\"','"'),int(m.group(3)))
# --- function-level returns
rets=[];stack=[];seen={}
for l in sub[8:]:
    m=re.match(r'^( *)\((\w+)',l)
    if not m: continue
    ind=len(m.group(1));
    while stack and stack[-1][0]>=ind: stack.pop()
    if m.group(2)=='return_stmt':
        mm=re.search(r'range=\[[^:]+:(\d+):(\d+)',l); loc=(int(mm.group(1)),int(mm.group(2)))
        nested=any(k in('closure_expr','autoclosure_expr','func_decl') for _,k in stack)
        seen[loc]=seen.get(loc,False) or nested
    stack.append((ind,m.group(2)))
crng=[]
for l in sub:
    m=re.match(r'^ *\((closure_expr|func_decl)\b.*?range=\[[^:]+:(\d+):(\d+) - line:(\d+):(\d+)\]',l)
    if m: crng.append(tuple(int(x) for x in m.groups()[1:]))
def incl(k):
    return any((a,b)<=k<=(c,d) for a,b,c,d in crng)
rets=[k for k,v in seen.items() if not v and not incl(k)]
retset=set(rets)
# --- items (from the AST ranges: the old local funcs keep their body at the func's own indent)
def ind(l): return len(l)-len(l.lstrip(' '))
rng=[]
for l in sub[8:]:
    m=re.match(r'^ {8}\((\w+)[^\n]*?range=\[[^:]+:(\d+):\d+ - (?:line:)?(\d+):',l)
    if m and m.group(1)!='var_decl': rng.append((int(m.group(2))-1,int(m.group(3))))
rng.sort()
items=[];prev_end=s+1
for a,z in rng:
    b=a
    while b-1>=prev_end and L[b-1].strip().startswith('//'): b-=1
    for x in range(prev_end,b):
        assert not L[x].strip(),('uncovered line',x+1,L[x])
    items.append((b,z)); prev_end=z
for x in range(prev_end,e): assert not L[x].strip(),('tail',x+1)
def kind(a,z):
    t=next(x for x in L[a:z] if not x.strip().startswith('//') and x.strip())
    t=t.strip()
    if re.match(r'(@\w+(\([^)]*\))? )*func ',t): return 'func'
    if re.match(r'(let|var) ',t): return 'decl'
    return 'stmt'
def conv_decl(txt_lines):
    t=txt_lines
    # first non-comment line
    for i,x in enumerate(t):
        if x.strip() and not x.strip().startswith('//'): break
    x=t[i]
    m=re.match(r'^(\s*)(let|var) (\(.*?\)|\w+)(\s*:\s*[^=]+?)? = (.*)$',x)
    if m and m.group(3)=='p' and m.group(5).strip()=='p': return t[:i]+t[i+1:]
    if m:
        t[i]=m.group(1)+m.group(3)+' = '+m.group(5); return t
    m=re.match(r'^(\s*)(let|var) (\w+)\s*:\s*[^=]+$',x)
    if m and (i+1>=len(t) or True) and not x.rstrip().endswith('{'):
        return t[:i]+t[i+1:]
    raise SystemExit('unhandled decl: '+x)
def fix_ret(a,z):
    out=[]
    for n in range(a,z):
        x=L[n]
        for (rl,rc) in [r for r in retset if r[0]==n+1]:
            seg=x[rc-1:rc-1+6]
            assert seg=='return',(n+1,x)
            nxt=x[rc-1+6:rc-1+7]
            assert nxt in('',' ','}'),(n+1,x)
            x=x[:rc-1]+'return true'+x[rc-1+6:]
        out.append(x)
    return out,any(r[0]-1>=a and r[0]-1<z for r in retset)
def selfsub(x): return re.sub(r'\bSelf\b','RichLayout',re.sub(r'(?<![.\w])self\b','rl',x))
funcs=[];chunks=[];cur=[];curn=0;cur_ret=False
def flush():
    global cur,curn,cur_ret
    if cur: chunks.append((cur,cur_ret)); cur=[];curn=0;cur_ret=False
for a,z in items:
    kd=kind(a,z)
    if kd=='func':
        funcs.append([selfsub(x) for x in L[a:z]]); continue
    tx,hr=fix_ret(a,z)
    if kd=='decl': tx=conv_decl(tx)
    tx=[selfsub(x) for x in tx]
    cur+=tx;curn+=z-a;cur_ret|=hr
    if curn>=CH: flush()
flush()
# strip trailing blank lines in funcs
def is_opt(t):
    if not t.endswith('?'): return False
    d=0
    for k,ch in enumerate(t):
        if ch in '([<': d+=1
        elif ch in ')]': d-=1
        elif ch=='>' and t[k-1]!='-': d-=1
        elif ch=='>' and t[k-1]=='-' and d==0: return False
    return True
def fld(n,t):
    if is_opt(t): return f'    var {n}: {t}'
    return (f'    var _{n}_: ({t})?\n'
            f'    var {n}: {t} {{ get {{ _{n}_.unsafelyUnwrapped }} set {{ _{n}_ = newValue }} _modify {{ yield &_{n}_! }} }}')
HDR='''// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "%s": %s
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation
'''
fwd=open(os.environ.get('FWD','/dev/null')).read() if os.environ.get('FWD') and os.path.exists(os.environ['FWD']) else ''
fr=[HDR%('Paragraph+Frame','the state of one `_layoutParagraphBody` call (its locals), as a class, so its steps can be methods in separate files.'),
 'final class _ParaFrame {','    unowned let rl: RichLayout','    let i: Int','    let document: RichDocument','    var p: RichParagraph']
for n,(t,_) in sorted(fields.items(),key=lambda kv:kv[1][1]):
    if n in('p',): continue
    fr.append(fld(n,t))
fr+=['','    init(_ rl: RichLayout, _ i: Int, _ p: RichParagraph, _ document: RichDocument) {','        self.rl = rl; self.i = i; self.p = p; self.document = document','    }','']
fr+=['    func go() {']
for n,(c,hr) in enumerate(chunks):
    fr.append(f'        if c{n}() {{ return }}' if hr else f'        c{n}()')
fr+=['    }','}','']
fr+=['extension _ParaFrame {','// FWD-BEGIN',fwd.rstrip('\n'),'// FWD-END','}','']
open(D+'RichLayout+Paragraph+Frame.swift','w').write('\n'.join(fr))
# chunk files: group chunks ~ one file each 
for n,(c,hr) in enumerate(chunks):
    o=[HDR%(f'Paragraph+Body{n}',f'step {n} of `_layoutParagraphBody`.'),'extension _ParaFrame {',f'    func c{n}() -> {"Bool" if hr else "Void"} {{']+c
    if hr: o.append('        return false')
    o+=['    }','}','']
    open(D+f'RichLayout+Paragraph+Body{n}.swift','w').write('\n'.join(o))
o=[HDR%('Paragraph+Funcs','the local functions of `_layoutParagraphBody`, as methods of its frame.'),'extension _ParaFrame {']
for f in funcs: o+=f
o+=['}','']
open(D+'RichLayout+Paragraph+Funcs.swift','w').write('\n'.join(o))
new=L[:s+1]+['        let f = _ParaFrame(self, i, p, document)','        f.go()']+L[e:]
open(F,'w').write('\n'.join(new))
print('items',len(items),'chunks',len(chunks),'funcs',len(funcs),'fields',len(fields),'rets',len(rets))
for r in rets: print("RET",r,L[r[0]-1][:100])
