# Lab zde: zh-de97afa7's first body paragraph alone, one change at a time.
import re, zipfile, sys, glob
src = glob.glob('/data/s/amd-5/starling/test/corpus/docx/**/zh-de97afa7*.docx', recursive=True)[0]
z = zipfile.ZipFile(src)
files = {n: z.read(n) for n in z.namelist()}
doc = files['word/document.xml'].decode('utf8')
ps = list(re.finditer(r'<w:p[ >].*?</w:p>', doc, re.S))
para = ps[4].group(0)
sect = re.findall(r'<w:sectPr.*?</w:sectPr>', doc, re.S)[-1]
head = doc[:doc.index('<w:body>') + 8]
def build(name, para=para, sect=sect, settings=None):
    d = head + para + sect + '</w:body></w:document>'
    out = dict(files); out['word/document.xml'] = d.encode('utf8')
    if settings: out['word/settings.xml'] = settings(files['word/settings.xml'].decode('utf8')).encode('utf8')
    with zipfile.ZipFile(f'/data/s/amd-5/labw/test/labs/zde/{name}.docx', 'w', zipfile.ZIP_DEFLATED) as o:
        for n, b in out.items(): o.writestr(n, b)
build('zde-a-real')
build('zde-b-nogrid', sect=sect.replace('<w:docGrid w:type="lines" w:linePitch="312"/>', ''))
build('zde-c-all16', para=para.replace('w:val="30"', 'w:val="32"'))
build('zde-d-songti', para=para.replace('仿宋_GB2312', '宋体'))
build('zde-e-left', para=para.replace('<w:jc w:val="both"/>', '<w:jc w:val="left"/>'))
build('zde-f-14pt', para=para.replace('w:val="30"', 'w:val="28"').replace('w:val="32"', 'w:val="28"'))
build('zde-g-nocompress', settings=lambda s: s.replace('compressPunctuation', 'doNotCompress'))
build('zde-h-autoline', para=para.replace('w:line="600" w:lineRule="exact"', 'w:line="240" w:lineRule="auto"'))
build('zde-i-nogrid-songti-left', para=para.replace('仿宋_GB2312', '宋体').replace('<w:jc w:val="both"/>', '<w:jc w:val="left"/>'), sect=sect.replace('<w:docGrid w:type="lines" w:linePitch="312"/>', ''))
build('zde-j-noindent', para=para.replace('<w:ind w:firstLineChars="200" w:firstLine="640"/>', ''))
