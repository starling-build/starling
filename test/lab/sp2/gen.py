#!/usr/bin/env python3
"""Lab sp2 (lenovo-2, 2026-11-07): sp showed Word fits one more ideograph after a heading when the spaces can narrow, plain spaces
narrow to 6.5 (0.4 em) but bold ones stayed 8.04 in the lab and 6.84 in zh-6c447317. Sweep the right indent (0..16 pt, 0.5 steps)
so the first line overflows by every amount; variants: A bold 2 spaces, C plain 2, R real-like (bold 2 + body run kern=2 + lang +
paragraph-mark rPr as in zh-6c447317), B bold 1, D plain 1. Base package = zh-6c447317."""
import zipfile,re,sys,glob
src=glob.glob('../../corpus/docx/docs/zh-6c447317*.docx')[0]
z=zipfile.ZipFile(src); doc=z.read('word/document.xml').decode()
sect=re.search(r'<w:sectPr.*?</w:sectPr>',doc,re.S).group(0); head=doc[:doc.index('<w:body>')+8]
RF='<w:rFonts w:hint="default" w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="仿宋_GB2312" w:cs="Times New Roman"/>'
def run(t,b=False,extra=''):
    return f'<w:r><w:rPr>{RF}{"<w:b/>" if b else "<w:bCs/>"}{extra}<w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr><w:t xml:space="preserve">{t}</w:t></w:r>'
REAL='<w:kern w:val="2"/>'; LANG='<w:lang w:val="en-US" w:eastAsia="zh-CN" w:bidi="ar-SA"/>'
body='以上各项补贴申请材料经人力资源社会保障部门审核通过后，对个人申请的补贴，按规定优先发放到申请者本人社会保障卡银行账户。'
H='第二十七条'
def para(runs,right,mark=False):
    pm=f'<w:rPr>{RF}<w:bCs/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr>' if mark else ''
    return f'<w:p><w:pPr><w:overflowPunct w:val="0"/><w:adjustRightInd w:val="0"/><w:snapToGrid w:val="0"/><w:spacing w:line="580" w:lineRule="exact"/><w:ind w:right="{right}" w:firstLine="643" w:firstLineChars="200"/>{pm}</w:pPr>{"".join(runs)}</w:p>'
V={'A':lambda:([run(H+'  ',True),run(body)],False),
   'C':lambda:([run(H+'  '),run(body)],False),
   'R':lambda:([run(H+'  ',True),run(body,False,REAL).replace('</w:rPr>',LANG+'</w:rPr>',1)],True),
   'B':lambda:([run(H+' ',True),run(body)],False),
   'D':lambda:([run(H+' '),run(body)],False)}
ps=[]
for k,f in V.items():
    for s in range(33):   # right indent 0..16 pt in 0.5 pt steps = 0..320 twips
        r,m=f(); ps.append(para(r,s*10,m))
out=sys.argv[1] if len(sys.argv)>1 else 'sp2.docx'
zo=zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)
for i in z.infolist():
    d=z.read(i.filename)
    if i.filename=='word/document.xml': d=(head+''.join(ps)+sect+'</w:body></w:document>').encode()
    zo.writestr(i,d)
zo.close(); print(out,len(ps))
