#!/usr/bin/env python3
"""Labs sqp and bxr (for amd-opus): two Word line ends that ours sets differently from Word for Windows.

sqp  zh-424775e4 p5 (mode 12, compressPunctuation, balance, SimSun 12, 408pt column). Word takes "机，" on
     "这一回答大出他们所料。”金立群接着说：“不要隐瞒我们中国的国际政治动机，" by squeezing the marks (the "。”"
     and "：“" pairs print 15pt each, ours 24 and 18) and hanging the comma; ours wraps "机，". Question: how much
     does each mark give at a line end under squeeze, by mode? The paragraph starts at that line (no first-line
     indent), cut after two more lines, the right indent stepped T = -10 .. +26 pt by 0.5 (73 paragraphs):
       sqp-a  as the document (mode 12, compressPunctuation)
       sqp-b  compatibilityMode 15
       sqp-c  mode 12, characterSpacingControl doNotCompress
       sqp-d  mode 12, the pairs single: "。”" -> "。", "：“" -> "："
bxr  zh-bdae17c0's reference "範例2  Bozeman, B. (1993). Introduction: Two concepts of public management. …"
     (mode 15, compressPunctuation, balance, Times New Roman / 標楷體 14, jc both). "範", "例", "2" are three runs, each
     with a single box border. Word refuses "concepts" ~5pt over (ours; Word sets the box tighter: 3.5pt between
     "例" and "2" where ours has 7). Question: what may the spaces give, and does the border change it? The right
     indent stepped T = -12 .. +14 pt by 0.5 from the document's 84 twips (53 paragraphs):
       bxr-a  as the document
       bxr-b  no border on the label runs
       bxr-c  the three label runs removed (the line starts with the two spaces)
Each document starts with the source paragraph exactly as in the corpus (control: compare its lines with the corpus
print before trusting the lab; lab bsp found a lab machine whose Times space differed from the corpus printer).
gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))

def load(doc_id):
    z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, doc_id + '*.docx'))[0])
    return z, z.read('word/document.xml').decode('utf-8'), z.read('word/settings.xml').decode('utf-8')

def para(doc, key):
    ps = [m.group(0) for m in re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S)]
    return [p for p in ps if key in text(p)][0]

def write(z, doc, settings, body, name):
    own = re.search(r'<w:sectPr[ >](?:(?!<w:sectPr[ >]).)*?</w:sectPr>\s*</w:body>', doc, flags=re.S).group(0)
    own = re.sub(r'<w:(headerReference|footerReference)[^>]*/>', '', own)
    out = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + body + own, doc, count=1, flags=re.S)
    path = os.path.join(outdir, name + '.docx')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            data = z.read(n)
            if n == 'word/document.xml': data = out.encode('utf-8')
            elif n == 'word/settings.xml': data = settings.encode('utf-8')
            zo.writestr(n, data)
    print(name, '->', path)

def right(ppr, twips):
    if '<w:ind ' in ppr:
        ppr = re.sub(r'<w:ind ([^>]*?)/>', lambda k: '<w:ind ' + re.sub(r'\s*w:right="-?\d+"', '', k.group(1)).rstrip() + ' w:right="%d"/>' % twips, ppr, count=1)
    else:
        ppr = ppr.replace('<w:pPr>', '<w:pPr><w:ind w:right="%d"/>' % twips, 1)
    return ppr

# ---- sqp
z, doc, st = load('zh-424775e4')
src = para(doc, '这一回答大出他们所料')
ppr = re.search(r'<w:pPr>.*?</w:pPr>', src, flags=re.S).group(0).replace('<w:ind w:firstLine="420"/>', '')
rpr = '<w:rPr><w:rFonts w:hint="eastAsia"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr>'
line = '这一回答大出他们所料。”金立群接着说：“不要隐瞒我们中国的国际政治动机，堂堂正正地说出我们中国的国际政治目的。我们发起成立亚投行就是为了改变（改革）目前已有的全球治理机构。'
steps = [round(-10 + 0.5 * i, 1) for i in range(73)]
def sqp(name, settings, t):
    body = src + ''.join('<w:p>%s<w:r>%s<w:t>%s</w:t></w:r></w:p>' % (right(ppr, round(T * 20)), rpr, t) for T in steps)
    write(z, doc, settings, body, name)
sqp('sqp-a', st, line)
sqp('sqp-b', re.sub(r'(compatibilityMode"[^>]*w:val=")\d+', r'\g<1>15', st), line)
sqp('sqp-c', st.replace('compressPunctuation', 'doNotCompress'), line)
sqp('sqp-d', st, line.replace('。”', '。').replace('：“', '：'))

# ---- bxr
z, doc, st = load('zh-bdae17c0')
src = para(doc, 'Two concepts of public management')
m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)(.*)</w:p>$', src, flags=re.S)
ppr, runs = m.group(2), m.group(3)
r0 = int(re.search(r'w:right="(-?\d+)"', ppr).group(1))
rs = re.findall(r'<w:r[ >](?:(?!<w:r[ >]).)*?</w:r>', runs, flags=re.S)
label = [r for r in rs if '<w:bdr ' in r]
assert [text(r) for r in label] == ['範', '例', '2'], [text(r) for r in label]
steps = [round(-12 + 0.5 * i, 1) for i in range(53)]
def bxr(name, rr):
    body = src + ''.join('<w:p>%s%s</w:p>' % (right(ppr, r0 + round(T * 20)), rr) for T in steps)
    write(z, doc, st, body, name)
bxr('bxr-a', runs)
bxr('bxr-b', re.sub(r'<w:bdr [^>]*/>', '', runs))
bxr('bxr-c', ''.join(r for r in rs if r not in label))
