#!/usr/bin/env python3
"""Lab dig (for amd-opus / amd-7): is it the automatic spaces (CJK next to a digit) that make Word for Windows
refuse a last character 0.46-0.48 em over, in zh-9c162f26's mode-14 grid cells?  The paragraph is the document's
own p13 cell paragraph "4、装饰装修期间每3日巡查1 次现场，发现…违法违规行为的，应立即劝阻…", copied into a one-cell
fixed table of the cell's own width (7647 twips = 371.55pt text) and its own section (grid, settings).
Variants:  A as is;  B the digits "3" and "1" replaced by "三" and "一" (no digit boundary on the line);
           C only the "3" replaced.
The right indent is stepped so the overhang of "应" (the first line's last character, 9pt) walks from 0.38 to
0.52 em in 0.1pt (2 twip) steps.  OFFSETS gives, per variant, the right indent (twips) at which the overhang is
the 0.38 em start, computed from our own layout (see run.sh); the paragraphs after it add 2 twips each.
Read: for each paragraph, in order, the text of its FIRST line in Word's print (whether it ends with 应).
gen.py VARIANT SRC.docx OUT.docx START_TWIPS [N]   (VARIANT A | B | C; SRC zh-9c162f26)"""
import sys, re, zipfile
var, src, out, start = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
n = int(sys.argv[5]) if len(sys.argv) > 5 else 14
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
paras = list(re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S))
para = [m.group(0) for m in paras if '装饰装修期间每3日巡查1' in text(m.group(0))][0]
if var in 'BC': para = para.replace('每3日', '每三日')
if var == 'B': para = para.replace('巡查1 次', '巡查一 次')
m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)?(.*)</w:p>$', para, flags=re.S)
ppr = m.group(2); body = m.group(3)
i = doc.index(re.search(r'<w:p[ >](?:(?!<w:p[ >]).)*?装饰装修期间每3日巡查1', doc, flags=re.S).group(0)[:0] + '装饰装修期间每3日巡查1')
tb0 = doc.rindex('<w:tbl>', 0, i)
tblpr = re.search(r'<w:tblPr>.*?</w:tblPr>', doc[tb0:], flags=re.S).group(0)
tblpr = re.sub(r'<w:tblW [^>]*/>', '<w:tblW w:w="7647" w:type="dxa"/>', tblpr)
tblpr = re.sub(r'<w:tblInd [^>]*/>', '', tblpr)
tcp = '<w:tcPr><w:tcW w:w="7647" w:type="dxa"/></w:tcPr>'
out_paras = []
for k in range(n):
    right = start + 2 * k
    p = ppr.replace('<w:pPr>', '<w:pPr><w:ind w:right="%d"/>' % right, 1) if '<w:ind ' not in ppr else ppr
    one = '<w:p>%s%s</w:p>' % (p, body)
    out_paras.append('<w:tbl>%s<w:tblGrid><w:gridCol w:w="7647"/></w:tblGrid><w:tr><w:tc>%s%s</w:tc></w:tr></w:tbl><w:p/>' % (tblpr, tcp, one))
at = doc.index(para if var == 'A' else para.replace('每三日', '每3日').replace('巡查一 次', '巡查1 次'))
own = re.search(r'<w:sectPr[ >].*?</w:sectPr>', doc[at:], flags=re.S).group(0)
d = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + ''.join(out_paras) + own + k.group(2), doc, count=1, flags=re.S)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
    for nme in z.namelist():
        zo.writestr(nme, d.encode('utf-8') if nme == 'word/document.xml' else z.read(nme))
print(var, len(out_paras), 'paragraphs from right indent', start)
