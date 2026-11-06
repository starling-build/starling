import sys,os,json,glob,pymupdf
XS={'g':'工','q':'□','b':'■','o':'○'}
print('# variant\tX\tfirstW_stays(pt line width)\tnatural\tstays_below_natural_by\tbits(1=X on line 1 per 1pt step, from natural-36)')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    k=os.path.basename(f)[:-9]; Ws=json.load(open(f[:-9]+'.meta')); X=XS[k.split('-')[1]]
    lines=[]
    for p in pymupdf.open(f):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(c['c'] for s in l['spans'] for c in s['chars']).replace(' ','')
                lines.append((p.number,l['bbox'][1],t))
    paras=[t for _,_,t in sorted(lines) if t.startswith('政')]
    bits=''.join('1' if X in t else '0' for t in paras)
    i=bits.find('1'); nat=Ws[-1]
    print('%s\t%s\t%s\t%s\t%s\t%s'%(k,X,Ws[i] if i>=0 else 'none',nat,(nat-Ws[i]) if i>=0 else '',bits))
