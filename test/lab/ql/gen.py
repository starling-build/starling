"""Lab ql: does Word hang / squeeze a line-final closing quote set in the Latin slot (hint default)?
Paragraph = zh-e61c3dff p1's "...基础，依托“科技特派团”、“科技副总”" (mode 14, compressPunctuation, justified,
16pt 仿宋_GB2312). H = as the document (the last run hint=default); E = that run hint=eastAsia.
Right margin 1474 + d twips*10 for d = 0..24 pt step 0.5: the line's overflow grows by d.
Read: for each file the text of the line that holds "科技副总" (does it end at ” or at 总, does the next line open with ” ?)
and the x of every mark on that line (origin to origin)."""
import zipfile,glob,re,sys
src=glob.glob(sys.argv[1] if len(sys.argv)>1 else 'test/corpus/docx/docs/zh-e61c3dff*.docx')[0]
z=zipfile.ZipFile(src); d=z.read('word/document.xml').decode()
i=d.find('强化制造业高质量发展基础'); j=max(d.rfind('<w:p>',0,i),d.rfind('<w:p ',0,i)); k=d.find('</w:p>',i)+6
para=d[j:k]; head=d[:d.find('<w:body>')+8]
sect=re.findall(r'<w:sectPr.*?</w:sectPr>',d,re.S)[-1]
def build(kind,dd):
    p=para if kind=='H' else para.replace('w:hint="default"','w:hint="eastAsia"')
    s=sect.replace('w:right="1474"',f'w:right="{1474+dd*10}"')
    body=head+p+s+'</w:body></w:document>'
    out=f'test/lab/ql/ql-{kind}-{dd:03d}.docx'
    zo=zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)
    for n in z.namelist(): zo.writestr(n, body.encode() if n=='word/document.xml' else z.read(n))
    zo.close()
for kind in 'HE':
    for dd in range(0,245,5): build(kind,dd)
