#!/usr/bin/env python3
"""Lab cm2 (for amd-opus), after lab cm: how far Word for Windows squeezes a body line to take a last
character together with the mark after it, per MARK. One line, zh-c2c92639 p28's "除；施工前，应对屋面板
(楼板)结构的承载能力及其加固措施、选用的拆除机械、机械的起吊方|法、" (11pt, compressPunctuation, four
marks before the pair), with only the mark after "法" swapped. Lab cm: with "、" Word takes the pair to row r
and refuses from s (s = the paragraph's own width).
  cm2.docx, 8 blocks of 25 rows, the right indent stepped by 10 twips (0.5pt), rows a..y each:
    block 1 "法、"  2 "法，"  3 "法。"  4 "法；"  5 "法："  6 "法”"  7 "法」"  8 "法）"
  (row s of each block is the paragraph's own width.)
Read: per row, line 1's last two characters and line 2's head (meas.py).
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

def sub(a, b): return lambda p: p.replace(a, b, 1) if a in p else (_ for _ in ()).throw(SystemExit('not in runs: ' + a))
V = [(L, sub('起吊方法、', '起吊方法' + m), -8) for m in '、，。；：”」）']
build('zh-c2c92639', '应对屋面板', '除；施工前，应对屋面板', V, 'cm2.docx')
