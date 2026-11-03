#!/usr/bin/env python3
"""Lab wsp (for amd-opus): do letter-spaced word spaces give at a justified line's end in Word for Windows' mode-14
layout? zh-06c46ba9's reference "範例2  Iyengar, S., & S. Jackman (2004). Technology …" (mode 14, balance,
compressPunctuation, Times New Roman / 標楷體 14, jc both; its spaces are runs spaced +37 twips) takes "Technology"
in Word's print with the spaces drawn ~4.4 (5.35 with the spacing); ours, where mode-14 spaces give nothing,
leaves it ~4.9pt over once the boxed label is set at Word's width (lab bxr). The right indent stepped T = -8 .. +16pt
by 0.5 (49 paragraphs) after the corpus paragraph itself (control):
  wsp-a  zh-06c46ba9's Iyengar reference as it is
  wsp-b  the same, every run's w:spacing removed
  wsp-c  as a, compatibilityMode 15
  wsp-d  zh-bdae17c0's "範例5 Van Ledebur …" reference as it is (mode 15 document, for comparison)
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
steps = [round(-8 + 0.5 * i, 1) for i in range(49)]
def stepped(z, doc, st, key, name, runs_fn=lambda r: r):
    src = para(doc, key)
    m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)(.*)</w:p>$', src, flags=re.S)
    ppr, runs = m.group(2), runs_fn(m.group(3))
    r0 = int(re.search(r'w:right="(-?\d+)"', ppr).group(1))
    body = src + ''.join('<w:p>%s%s</w:p>' % (re.sub(r'w:right="-?\d+"', 'w:right="%d"' % (r0 + round(T * 20)), ppr, count=1), runs) for T in steps)
    write(z, doc, st, body, name)
z, doc, st = load('zh-06c46ba9')
stepped(z, doc, st, 'Iyengar', 'wsp-a')
stepped(z, doc, st, 'Iyengar', 'wsp-b', lambda r: re.sub(r'<w:spacing w:val="-?\d+"/>', '', r))
stepped(z, doc, re.sub(r'(compatibilityMode"[^>]*w:val=")\d+', r'\g<1>15', st), 'Iyengar', 'wsp-c')
z, doc, st = load('zh-bdae17c0')
stepped(z, doc, st, 'Van Ledebur', 'wsp-d')
