#!/usr/bin/env python3
"""Lab bsp (for amd-opus): does Word for Windows, before 2013's layout (mode 14), narrow a typed space to take the next
character at a line's end — and which spaces? zh-6c447317's "第三十八条 一次性职业介绍补贴、新就业形态灵活就业人员…"
(mode 14, compressPunctuation, balanceSingleByteDoubleByteWidth, FangSong_GB2312 16pt, justified): Word's print takes
"业" 9.19pt over with its one mark "、" at half (8.0) and the bold space after "第三十八条" drawn 6.84 for 8 — but the
same document's "第四条 就业补助资金…" (space in the regular run) leaves a character 9.04 over with one "、". Word also
draws the two bold spaces of "第二十二条  " 6.84 + 6.96 on lines that need no room at all.
Variants (one file each), the paragraph's own runs, its section, its settings:
  a  as it is, "、" made "和" (no mark on the line): the bold space, a run of its own
  b  as a, the space moved into the regular run (not bold)
  c  as a, the space inside the bold run "第三十八条 "
  d  as a, two bold spaces
  e  as b, two regular spaces
  f  as it is (with "、")
  g  as f, the space moved into the regular run
Right indent stepped so the line's first character past the margin stands T pt past it (T from ours at right 0):
a-e T = -0.4 .. 3.6 by 0.2; f, g T = 7.0 .. 11.0 by 0.2 (21 paragraphs each).
Read: for each paragraph in order, the last character of Word's FIRST line, and the x of the bold space(s)' ends.
gen.py SRC.docx OUTDIR OVER.tsv   (OVER.tsv: variant<TAB>overhang at right 0, as ours measures; pass /dev/null for 0)"""
import sys, re, zipfile, os
src, outdir, overf = sys.argv[1], sys.argv[2], sys.argv[3]
over0 = {l.split('\t')[0]: float(l.split('\t')[1]) for l in open(overf) if '\t' in l}
os.makedirs(outdir, exist_ok=True)
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
text = lambda s: ''.join(re.findall(r'<w:t[^>]*>([^<]*)', s))
paras = list(re.finditer(r'<w:p[ >](?:(?!<w:p[ >]).)*?</w:p>', doc, flags=re.S))
para = [m.group(0) for m in paras if text(m.group(0)).startswith('第三十八条')][0]
m = re.match(r'(<w:p[^>]*>)(<w:pPr>.*?</w:pPr>)(.*)</w:p>$', para, flags=re.S)
ppr, body0 = m.group(2), m.group(3)
runs = re.findall(r'<w:r>.*?</w:r>', body0, flags=re.S)
assert len(runs) == 3 and text(runs[0]) == '第三十八条' and text(runs[1]) == ' ', [text(r) for r in runs]
head, space, rest = runs
def variant(name):
    h, s, r = head, space, rest
    if name in 'abcde':
        r = r.replace('补贴、新', '补贴和新', 1)
    if name in 'beg':
        s = ''
        r = r.replace('<w:t>', '<w:t xml:space="preserve">' + (' ' if name != 'e' else '  '), 1)
    if name == 'c':
        s = ''
        h = h.replace('<w:t>第三十八条</w:t>', '<w:t xml:space="preserve">第三十八条 </w:t>', 1)
    if name == 'd':
        s = s.replace('> </w:t>', '>  </w:t>', 1)
    return h + s + r
steps = {k: [round(-0.4 + 0.2 * i, 2) for i in range(21)] for k in 'abcde'}
steps.update({k: [round(7.0 + 0.2 * i, 2) for i in range(21)] for k in 'fg'})
own = re.search(r'<w:sectPr[ >].*?</w:sectPr>', doc[doc.index(para):], flags=re.S).group(0)
for name in 'abcdefg':
    body = variant(name)
    ps = []
    for T in steps[name]:
        right = round((T - over0.get(name, 0.0)) * 20)
        p = re.sub(r'<w:ind ([^>]*?)/>', lambda k: '<w:ind w:right="%d" ' % right + k.group(1) + '/>', ppr, count=1)
        assert 'w:right=' in p
        ps.append('<w:p>%s%s</w:p>' % (p, body))
    d = re.sub(r'(<w:body>).*(</w:body>)', lambda k: k.group(1) + ''.join(ps) + own + k.group(2), doc, count=1, flags=re.S)
    path = os.path.join(outdir, 'bsp-%s.docx' % name)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            zo.writestr(n, d.encode('utf-8') if n == 'word/document.xml' else z.read(n))
    print(name, len(ps), 'paragraphs ->', path)
