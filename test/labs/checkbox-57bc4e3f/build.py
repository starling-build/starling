# Lab cbx57: legacy FORMCHECKBOX advance by font and size (lo-57bc4e3f: Word 1.30 em in MS Gothic, ours 1.15 em).
# One paragraph per (font, size): [box] then "MMMMMMMMMM" so the text start x gives the box advance.
# Print it in Word for Windows; read each paragraph's second run x minus the first.
import zipfile, sys, glob
src = glob.glob('test/corpus/docx/lo/docs/lo-57bc4e3f*.docx')[0]
fonts = ['MS Gothic', 'Times New Roman', 'Arial', 'Calibri', 'SimSun', 'MS Mincho']
sizes = [10, 12, 16, 24]
def para(f, sz, n):
    rp = f'<w:rPr><w:rFonts w:ascii="{f}" w:hAnsi="{f}" w:eastAsia="{f}"/><w:sz w:val="{sz*2}"/><w:szCs w:val="{sz*2}"/></w:rPr>'
    return (f'<w:p><w:r>{rp}<w:fldChar w:fldCharType="begin"><w:ffData><w:name w:val="cb{n}"/><w:enabled/><w:calcOnExit w:val="0"/><w:checkBox><w:sizeAuto/></w:checkBox></w:ffData></w:fldChar></w:r>'
            f'<w:r>{rp}<w:instrText xml:space="preserve"> FORMCHECKBOX </w:instrText></w:r><w:r>{rp}<w:fldChar w:fldCharType="separate"/></w:r>'
            f'<w:r>{rp}<w:fldChar w:fldCharType="end"/></w:r><w:r>{rp}<w:t>MMMMMMMMMM {f} {sz}</w:t></w:r></w:p>')
zi = zipfile.ZipFile(src)
F = {n: zi.read(n) for n in zi.namelist()}
x = F['word/document.xml'].decode()
a = x.index('<w:body>') + 8; b = x.index('<w:sectPr')
body = ''.join(para(f, s, i * 10 + j) for i, f in enumerate(fonts) for j, s in enumerate(sizes))
sect = '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:left="1134" w:right="1134" w:top="720" w:bottom="720" w:header="0" w:footer="0" w:gutter="0"/></w:sectPr></w:body></w:document>'
out = x[:a] + body + sect
zo = zipfile.ZipFile('test/labs/checkbox-57bc4e3f/cbx57.docx', 'w', zipfile.ZIP_DEFLATED)
for n, d in F.items():
    zo.writestr(n, out.encode() if n == 'word/document.xml' else d)
zo.close()
