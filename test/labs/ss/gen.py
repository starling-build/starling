import re,sys,shutil,os,zipfile
SRC=os.path.expanduser('~/tmp/ss/src')
OUT=sys.argv[1]
os.makedirs(OUT,exist_ok=True)
BODY="以上各项补贴申请材料经人力资源社会保障部门审核通过后，对个人申请的补贴，按规定优先发放到申请者本人社会保障卡银行账户"
PREFIX="高技能人才培养补助重点用于高技能人才培训基地建"  # filled below to 24 chars
PREFIX=PREFIX[:22]
def rpr(bold,ea,hint=None,latin=False):
    h=f' w:hint="{hint}"' if hint else ' w:hint="default"'
    b='<w:b/>' if bold else '<w:bCs/>'
    return f'<w:rPr><w:rFonts{h} w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="{ea}" w:cs="Times New Roman"/>{b}<w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr>'
def run(t,bold,ea,hint=None):
    return f'<w:r>{rpr(bold,ea,hint)}<w:t xml:space="preserve">{t}</w:t></w:r>'
def para(runs,r):
    ind=f'<w:ind w:right="{r}" w:firstLine="643" w:firstLineChars="200"/>' if r else '<w:ind w:firstLine="643" w:firstLineChars="200"/>'
    return f'<w:p><w:pPr><w:overflowPunct w:val="0"/><w:adjustRightInd w:val="0"/><w:snapToGrid w:val="0"/><w:spacing w:line="580" w:lineRule="exact"/>{ind}<w:jc w:val="both"/></w:pPr>{runs}</w:p>'
VARS="ABCDEFGHJ"
NUM="甲乙丙丁戊己庚辛壬"
STEP="一二三四五六七八九"
def build(ea):
    ps=[]
    for vi,v in enumerate(VARS):
        for si in range(9):
            r=si*10
            head=f"第{NUM[vi]}{STEP[si]}条"
            R=lambda t,b,hint=None: run(t,b,ea,hint)
            if v=='A': x=R(head,1)+R('  ',1)+R(BODY,0)
            elif v=='B': x=R(head,0)+R('  ',0)+R(BODY,0)
            elif v=='C': x=R(head,1)+R('  ',0)+R(BODY,0)
            elif v=='D': x=R(head,0)+R('  ',1)+R(BODY,0)
            elif v=='E': x=R(head,1)+R(' ',1)+R(BODY,0)
            elif v=='F': x=R(PREFIX,0)+R(head,1)+R('  ',1)+R(BODY,0)
            elif v=='G': x=R(head,1)+R('  ',1)+run('AB',0,ea)+R(BODY[2:],0)
            elif v=='H': x=R(head,1)+R('  ',1,'eastAsia')+R(BODY,0)
            elif v=='J': x=R(head,1)+R('  ',1)+R(BODY,1)
            ps.append(para(x,r))
    return ''.join(ps)
def make(name,ea,compat=14,balance=True):
    d=f'{OUT}/_{name}'
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(SRC,d)
    doc=open(f'{d}/word/document.xml',encoding='utf8').read()
    m=re.search(r'<w:body>(.*)(<w:sectPr.*</w:sectPr>)\s*</w:body>',doc,flags=re.S)
    doc=doc[:m.start(1)]+build(ea)+m.group(2)+'</w:body>'+doc[m.end():]
    open(f'{d}/word/document.xml','w',encoding='utf8').write(doc)
    s=open(f'{d}/word/settings.xml',encoding='utf8').read()
    s=s.replace('w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="14"',f'w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="{compat}"')
    if not balance: s=s.replace('<w:balanceSingleByteDoubleByteWidth/>','')
    open(f'{d}/word/settings.xml','w',encoding='utf8').write(s)
    z=zipfile.ZipFile(f'{OUT}/{name}.docx','w',zipfile.ZIP_DEFLATED)
    ct=f'{d}/[Content_Types].xml'; z.write(ct,'[Content_Types].xml')
    for root,_,fs in os.walk(d):
        for f in fs:
            p=os.path.join(root,f); a=os.path.relpath(p,d)
            if a!='[Content_Types].xml': z.write(p,a)
    z.close(); shutil.rmtree(d)
make('ss-c14-fs','仿宋_GB2312')
make('ss-c15-fs','仿宋_GB2312',15)
make('ss-c14-fangsong','仿宋')
make('ss-c14-simsun','宋体')
make('ss-c14-fs-nobal','仿宋_GB2312',14,False)
