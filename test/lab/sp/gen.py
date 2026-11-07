#!/usr/bin/env python3
"""Lab sp: when does Word narrow the spaces after a heading on a justified first line?
Base package (settings, styles, fonts, sectPr) = zh-6c447317. One docx, 12 variants x 3 body lengths.
Each paragraph: spacing exact 29pt, firstLine 643 (200 chars), justified, 16pt, as the real one."""
import zipfile,re,sys,glob
src=glob.glob('../../corpus/docx/docs/zh-6c447317*.docx')[0]
z=zipfile.ZipFile(src)
doc=z.read('word/document.xml').decode()
sect=re.search(r'<w:sectPr.*?</w:sectPr>',doc,re.S).group(0)
head=doc[:doc.index('<w:body>')+8]
def rf(ea,asc='Times New Roman'): return f'<w:rFonts w:hint="default" w:ascii="{asc}" w:hAnsi="{asc}" w:eastAsia="{ea}" w:cs="Times New Roman"/>'
def run(t,ea='仿宋_GB2312',b=False,asc='Times New Roman'):
    return f'<w:r><w:rPr>{rf(ea,asc)}{"<w:b/>" if b else "<w:bCs/>"}<w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r>'
body0='以上各项补贴申请材料经人力资源社会保障部门审核通过后，对个人申请的补贴，按规定优先发放到申请者本人社会保障卡银行账户，无社会保障卡的发放到个人其他银行账户；对培训机构、企业、培训单位申领的，按规定发放到其在银行开立的基本账户。'
def para(runs,first=643,jc=None):
    pj=f'<w:jc w:val="{jc}"/>' if jc else ''
    return f'<w:p><w:pPr><w:overflowPunct w:val="0"/><w:adjustRightInd w:val="0"/><w:snapToGrid w:val="0"/><w:spacing w:line="580" w:lineRule="exact"/><w:ind w:firstLine="{first}" w:firstLineChars="200"/>{pj}</w:pPr>{"".join(runs)}</w:p>'
H='第二十七条'
V={ # name -> function(body)->runs
 'A-b2':      lambda b:[run(H+'  ',b=True),run(b)],
 'B-b1':      lambda b:[run(H+' ',b=True),run(b)],
 'C-n2':      lambda b:[run(H+'  '),run(b)],
 'D-n1':      lambda b:[run(H+' '),run(b)],
 'E-h2sep':   lambda b:[run(H,ea='黑体',b=True),run('  ',b=True),run(b)],
 'F-h1sep':   lambda b:[run(H,ea='黑体',b=True),run(' ',b=True),run(b)],
 'G-lead2':   lambda b:[run('  '+b)],
 'H-lead2b':  lambda b:[run('  ',b=True),run(b)],
 'I-mid2b':   lambda b:[run('甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉'),run(H+'  ',b=True),run(b)],
 'J-mid2n':   lambda b:[run('甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉'),run(H+'  '),run(b)],
 'K-fs2b':    lambda b:[run(H+'  ',ea='仿宋',b=True,asc='Times New Roman'),run(b,ea='仿宋')],
 'L-b3':      lambda b:[run(H+'   ',b=True),run(b)],
}
paras=[]
for k,f in V.items():
    for cut in (0,3,7):   # three body starts: different slack on the first line
        paras.append(para(f(body0[cut:])))
        if k=='A-b2' and cut==0: paras.append(para(f(body0[cut:]),jc='left'))  # same, left aligned: control
xml=head+''.join(paras)+sect+'</w:body></w:document>'
out=sys.argv[1] if len(sys.argv)>1 else 'sp.docx'
zo=zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)
for i in z.infolist():
    d=z.read(i.filename)
    if i.filename=='word/document.xml': d=xml.encode()
    zo.writestr(i,d)
zo.close()
print(out,len(paras),'paragraphs')
