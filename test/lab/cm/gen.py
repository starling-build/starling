#!/usr/bin/env python3
"""Lab cm (for amd-opus): a body line whose last character comes with a mark (a comma or 、 after it, or an
opening bracket or quote before it), Word for Windows. Same method as cend/cend2: the paragraph copied once
per row, cut so the line is its FIRST line (a paragraph's own first line keeps its first-line indent and
numbering), the right indent stepped by 10 twips (0.5pt); row "k" is the paragraph's own width; rows a..j
wider, l..y narrower, shifted by each case's offset so the switch falls inside.
  Word REFUSES the pair at its own width, ours takes it (rows run wider, to find where Word takes):
    cm-fei   zh-3c055c9b "…日、餐|費、"   cm-ze  zh-6d402586 "…管理原|則，"   cm-fa  zh-c2c92639 "…起吊方|法、"
    cm-fang zh-c2cd4b3f "…“黑作|坊”"
  Word TAKES it, ours refuses (rows run narrower, to find where Word refuses):
    cm-wu    zh-aa3f29a0 "…「便民服務」|"  cm-jiu zh-bdae17c0 "…趨勢的探究：|"  cm-guan zh-c25d08c5 "…政府（管|"
Read: per row, line 1's last two characters and line 2's head (as cend2's meas.py); for row k the
per-character x origin of line 1.
usage: gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
L = 'abcdefghijklmnopqrstuvwxy'; U = L.upper(); N = [str(i) for i in range(1, 26)]
LEFT = {'zh-3c055c9b': 1393}
def build(doc_id, para_key, line_start, variants, name):
    z = zipfile.ZipFile(glob.glob(os.path.join(src_dir, doc_id + '*.docx'))[0])
    doc = z.read('word/document.xml').decode('utf-8')
    # locate the paragraph whose plain text contains para_key
    for m in re.finditer(r'<w:p[ >].*?</w:p>', doc, flags=re.S):
        plain = ''.join(re.findall(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', m.group(0)))
        if para_key in plain and '<w:tbl' not in m.group(0): break
    else: raise SystemExit('paragraph not found: ' + para_key)
    P = m.group(0)
    plain = ''.join(re.findall(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', P))
    cut = plain.find(line_start)
    assert cut >= 0, line_start
    def cut_text(p, n):  # drop the first n characters of text
        left = [n]
        def f(mt):
            t = mt.group(2)
            if left[0] <= 0: return mt.group(0)
            d = min(left[0], len(t)); left[0] -= d
            return mt.group(1) + t[d:] + '</w:t>'
        return re.sub(r'(<w:t(?: [^>]*)?>)([^<]*)</w:t>', f, p)
    base = cut_text(P, cut)
    first = cut == 0
    # numbering off (the line is not the first one), first line at the continuation lines'
    if not first:
        base = re.sub(r'<w:numPr>.*?</w:numPr>', '', base, flags=re.S)
        # (numbering from the style too: numId 0 cancels it)
        base = base.replace('<w:pPr>', '<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="0"/></w:numPr>', 1) if '<w:pPr>' in base else base
    ind = re.search(r'<w:ind\b[^>]*/>', base)
    left = right = 0
    if ind:
        g = lambda a: int((re.search(r'w:%s="(-?\d+)"' % a, ind.group(0)) or [0, 0])[1])
        left, right = g('left') or g('start'), g('right') or g('end')
    # (an indent the cancelled numbering gave: zh-3c055c9b's style 3, level 2, left 1393)
    left = LEFT.get(doc_id, left)
    fl = ' w:firstLineChars="0" w:firstLine="0"'
    if first and ind:
        k = re.search(r'w:(firstLine|hanging)="(\d+)"', ind.group(0))
        kc = re.search(r'w:(firstLineChars|hangingChars)="(\d+)"', ind.group(0))
        fl = (' w:%s="%s"' % kc.groups() if kc else '') + (' w:%s="%s"' % k.groups() if k else '')
    def row(p, step):
        # (Character-unit indents zeroed: a style's leftChars beats w:left — zh-12db188f's List Paragraph
        # has leftChars 200, which its paragraph cancels with leftChars 0.)
        newind = '<w:ind w:leftChars="0" w:left="%d" w:rightChars="0" w:right="%d"%s/>' % (left, right + step * 10, fl)
        if ind: p = p.replace(ind.group(0), newind, 1)
        elif '<w:pPr>' in p: p = p.replace('<w:pPr>', '<w:pPr>' + newind, 1)
        else: p = re.sub(r'(<w:p[ >][^>]*>|<w:p>)', lambda k: k.group(1) + '<w:pPr>' + newind + '</w:pPr>', p, count=1)
        return p
    out = []
    for labels, fn, off in variants:
        v = fn(base)
        for i, lab in enumerate(labels):
            out.append(row(v, i - 10 + off))
    doc = doc.replace(P, ''.join(out), 1)
    with zipfile.ZipFile(os.path.join(outdir, name), 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in z.namelist():
            zo.writestr(n, doc.encode('utf-8') if n == 'word/document.xml' else z.read(n))
    print(name, len(out), 'rows; ind left', left, 'right', right)

def same(p): return p
A = [L[:25]]
build('zh-3c055c9b', '廳負責人同意', '廳負責人同意', [(L, same, -8)], 'cm-fei.docx')
build('zh-6d402586', '為加強醫療機構因應', '為加強醫療機構因應', [(L, same, -8)], 'cm-ze.docx')
build('zh-c2c92639', '应对屋面板', '除；施工前，应对屋面板', [(L, same, -8)], 'cm-fa.docx')
build('zh-c2cd4b3f', '举报生产假冒伪劣食品的地下', '（二）举报', [(L, same, -8)], 'cm-fang.docx')
build('zh-aa3f29a0', '亦得至保訓會全球資訊網站', '郵寄保訓會辦理，亦得至', [(L, same, 8)], 'cm-wu.docx')
build('zh-bdae17c0', '公共行政學發展趨勢的探究', '範例1', [(L, same, 8)], 'cm-jiu.docx')
build('zh-c25d08c5', '按职责分工负责；各县', '交通运输、公安等部门按职责分工负责', [(L, same, 8)], 'cm-guan.docx')
