# -*- coding: utf-8 -*-
"""Lab gothface2 (Windows 01QbbApP, for amd-3). Package = zh-5450d509 (styles/theme/docDefaults/settings kept; themeFontLang eastAsia zh-CN).
One page per doc: 9 paragraphs (style 5, 12pt), each ONE char in ONE run: 部 署 ， 上 特 引 》 ） 。, then the same 9 chars in one run in a single paragraph.
Docs gf2_<face>_<lang>_<emb>: face = fs (仿宋_GB2312, absent from the box), song (宋体), jh (微軟正黑體), yahei (微软雅黑), none (no rFonts: docDefaults minorEastAsia theme = 等线, embedded full), fz (方正小标宋_GBK, embedded 27-glyph subset);
lang = cn (w:lang eastAsia zh-CN) / tw (zh-TW); emb = keep / strip (the <w:embedRegular> elements removed from fontTable.xml).
usage: mk.py OUT (cwd lab/goth2; needs ../goth/orig.docx)"""
import zipfile, os, sys, re
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile('../goth/orig.docx'); f = {n: z.read(n) for n in z.namelist() if not n.endswith('/')}
d = f['word/document.xml'].decode('utf-8')
bs = d.index('<w:body>') + len('<w:body>'); sect = re.findall(r'<w:sectPr.*?</w:sectPr>', d, re.S)[-1]; head = d[:bs]
CH = '部署，上特引》）。'
FACES = {'fs': '仿宋_GB2312', 'song': '宋体', 'jh': '微軟正黑體', 'yahei': '微软雅黑', 'none': None, 'fz': '方正小标宋_GBK'}
LANG = {'cn': 'zh-CN', 'tw': 'zh-TW'}


def run(face, lang, t):
    rf = '' if face is None else '<w:rFonts w:eastAsia="%s"/>' % face
    return '<w:r><w:rPr>%s<w:lang w:eastAsia="%s"/></w:rPr><w:t>%s</w:t></w:r>' % (rf, LANG[lang], t)


def para(r):
    return '<w:p><w:pPr><w:pStyle w:val="5"/><w:spacing w:before="0" w:beforeAutospacing="0" w:after="0" w:afterAutospacing="0" w:line="360" w:lineRule="auto"/></w:pPr>%s</w:p>' % r


ft0 = f['word/fontTable.xml'].decode('utf-8')
for fk, face in FACES.items():
    for lk in LANG:
        for emb in ('keep', 'strip'):
            body = ''.join(para(run(face, lk, c)) for c in CH) + para(run(face, lk, CH))
            g = dict(f); g['word/document.xml'] = (head + body + sect + '</w:body></w:document>').encode('utf-8')
            if emb == 'strip':
                g['word/fontTable.xml'] = re.sub(r'<w:embed\w+ [^>]*/>', '', ft0).encode('utf-8')
            with zipfile.ZipFile(os.path.join(out, 'gf2_%s_%s_%s.docx' % (fk, lk, emb)), 'w', zipfile.ZIP_DEFLATED) as o:
                for n, v in g.items(): o.writestr(n, v)
print(len(os.listdir(out)))
