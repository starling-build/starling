import re,os,shutil,zipfile,sys
SRC=os.path.expanduser('~/tmp/pc/src'); OUT=sys.argv[1]; os.makedirs(OUT,exist_ok=True)
CH="天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜金生丽水玉出昆冈剑号巨阙珠称夜光果珍李柰菜重芥姜海咸河淡鳞潜羽翔龙师火帝鸟官人皇始制文字乃服衣裳推位让国有虞陶唐吊民伐罪周发殷汤坐朝问道垂拱平章爱育黎首臣伏戎羌遐迩一体率宾归王鸣凤在竹白驹食场化被草木赖及万方"
# types: punctuation pattern inserted after every 4 characters
TYPES={'T0':'','T1':'，','T2':'，','T3':'，','T4':'，、。','T5':'，）','T6':'（，'}
# T1: one comma at pos 6; T2: 3 commas; T3: every 4th char; T4: mix; T5: commas and closing brackets; T6: opening+comma
def text(kind,n=64):
    out=[];k=0
    for i in range(n):
        out.append(CH[i%len(CH)])
        p=i+1
        if kind=='T0': continue
        if kind=='T1' and p==20: out.append('，')
        if kind=='T2' and p in (8,20,32): out.append('，')
        if kind=='T3' and p%4==0 and p<44: out.append('，')
        if kind=='T4' and p%4==0 and p<44: out.append('，、。'[(p//4)%3])
        if kind=='T5' and p%4==0 and p<44: out.append('，）'[(p//4)%2])
        if kind=='T6' and p%4==0 and p<44:
            out.append('，')
        if kind=='T6' and p%4==3 and p<44: out.append('（')
    return ''.join(out)
def para(label,t,size,rind,fonts):
    hs=size*2
    rpr=f'<w:rPr><w:rFonts w:ascii="{fonts}" w:hAnsi="{fonts}" w:eastAsia="{fonts}" w:cs="{fonts}"/><w:sz w:val="{hs}"/><w:szCs w:val="{hs}"/></w:rPr>'
    ind=f'<w:ind w:right="{rind}"/>' if rind else ''
    return f'<w:p><w:pPr><w:spacing w:line="{int(size*20*1.6)}" w:lineRule="exact"/>{ind}<w:jc w:val="both"/>{rpr}</w:pPr><w:r>{rpr}<w:t>{label}</w:t></w:r><w:r>{rpr}<w:t>{t}</w:t></w:r></w:p>'
NUM="甲乙丙丁戊己庚辛壬癸"
def body(size,fonts):
    ps=[]
    step=int(size*20/10)  # twips: 1/10 of a character
    for ti,k in enumerate(TYPES):
        for si in range(11):
            lab=f'{NUM[ti]}{NUM[si%10]}{"子丑"[si//10]}'
            ps.append(para(lab,text(k),size,si*step,fonts))
    return ''.join(ps)
def make(name,size,fonts):
    d=f'{OUT}/_{name}'
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(SRC,d)
    doc=open(f'{d}/word/document.xml',encoding='utf8').read()
    m=re.search(r'<w:body>(.*)</w:body>',doc,flags=re.S)
    sect='<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" w:header="567" w:footer="567" w:gutter="0"/><w:cols w:space="425"/><w:docGrid w:type="lines" w:linePitch="312"/></w:sectPr>'
    doc=doc[:m.start(1)]+body(size,fonts)+sect+'</w:body>'+doc[m.end():]
    open(f'{d}/word/document.xml','w',encoding='utf8').write(doc)
    z=zipfile.ZipFile(f'{OUT}/{name}.docx','w',zipfile.ZIP_DEFLATED)
    z.write(f'{d}/[Content_Types].xml','[Content_Types].xml')
    for root,_,fs in os.walk(d):
        for f in fs:
            p=os.path.join(root,f); a=os.path.relpath(p,d)
            if a!='[Content_Types].xml': z.write(p,a)
    z.close(); shutil.rmtree(d)
make('pc-105-simsun',10.5,'宋体')
make('pc-16-fangsong',16,'仿宋')
