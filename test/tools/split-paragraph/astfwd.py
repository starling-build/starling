import re,sys
AST=sys.argv[1]; names=set(open(sys.argv[2]).read().split())
decls={}
trx=re.compile(r'^ {4}\((struct_decl|enum_decl|class_decl|typealias) [^\n]*?"(\w+)"')
types=set()
rx=re.compile(r'^ {4}\((var_decl|func_decl) [^\n]*?range=\[([^:\]]*RichLayout[^:\]]*\.swift):(\d+):(\d+)[^\]]*\] "([^"]+)" (?:[^\n]*?)interface_type="((?:[^"\\]|\\.)*)"([^\n]*)')
for l in open(AST,errors='replace'):
    mt=trx.match(l)
    if mt and mt.group(2) in names: types.add(mt.group(2))
    m=rx.match(l)
    if not m: continue
    k,pth,ln,cl,n,t,rest=m.groups()
    base=n.split('(')[0]
    if base not in names: continue
    decls.setdefault(base,[]).append((k,n,t,rest,pth,int(ln),int(cl)))
def split_top(s):
    out=[];d=0;cur=''
    for ch in s:
        if ch in '([<': d+=1
        if ch in ')]>' and not (ch=='>' and cur.endswith('-')): d-=1
        if ch==',' and d==0: out.append(cur.strip());cur=''
        else: cur+=ch
    if cur.strip(): out.append(cur.strip())
    return out
out=[];miss=[]
for n in sorted(names):
    if n in types: out.append(f'    typealias {n} = RichLayout.{n}'); continue
    if n not in decls: miss.append(n); continue
    seen=set()
    for k,nm,t,rest,pth,ln,cl in decls[n]:
        if (nm,t) in seen: continue
        seen.add((nm,t))
        if k=='var_decl':
            ro=' let ' in rest or 'immutable' in rest or 'get ' in rest
            if 'static' in rest: continue
            out.append(f'    var {n}: {t} {{ get {{ rl.{n} }}'+('' if ro else ' set { rl.%s = newValue }'%n)+' }')
        else:
            if not t.startswith('(RichLayout) -> '): continue
            if 'static' in rest: continue
            src=open('/data/s/amd-perf/sp/orig.swift' if pth.endswith('RichLayout+Paragraph.swift') else pth).read().split('\n')
            txt='\n'.join(src[ln-1:ln+12])
            m2=re.search(r'func '+re.escape(n)+r'\b',txt)
            if not m2: miss.append(n+'?src'); continue
            k0=m2.end()
            gen=''
            if txt[k0]=='<':
                d=0
                for q in range(k0,len(txt)):
                    if txt[q]=='<': d+=1
                    if txt[q]=='>': 
                        d-=1
                        if d==0: break
                gen=txt[k0:q+1]; k0=q+1
            assert txt[k0]=='(',(n,txt[k0:k0+20])
            d=0
            for q in range(k0,len(txt)):
                if txt[q]=='(': d+=1
                if txt[q]==')':
                    d-=1
                    if d==0: break
            params=txt[k0+1:q]
            rest2=txt[q+1:]
            mm=re.match(r'([^{]*?)\s*(?:where [^{]*)?\{',rest2,re.S)
            tail=re.sub(r'\s+',' ',mm.group(1)).strip() if mm else ''
            ps=split_top(re.sub(r'//[^\n]*','',params)) if params.strip() else []
            dp=[];call=[]
            for j,p in enumerate(ps):
                p=re.sub(r'\s+',' ',p)
                mp=re.match(r'^(\w+)(?: (\w+))?\s*:\s*(.*)$',p)
                lb,nm2,rest3=mp.group(1),mp.group(2) or mp.group(1),mp.group(3)
                inout=rest3.startswith('inout ')
                dp.append(f'{lb} a{j}: {rest3}' if lb!='_' else f'_ a{j}: {rest3}')
                a_=('&' if inout else '')+f'a{j}'
                call.append(a_ if lb=='_' else f'{lb}: {a_}')
            thr=' throws' in tail
            out.append(f'    func {n}{gen}({", ".join(dp)}) {tail} {{ {"try " if thr else ""}rl.{n}({", ".join(call)}) }}')
print('\n'.join(out))
sys.stderr.write('MISSING: '+' '.join(miss)+'\n')
