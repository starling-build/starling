#!/usr/bin/env python3
"""Lab cend (for amd-opus): where Word for Windows stops squeezing a cell line's end, two lines the
fit cannot place.
Each document keeps its own table and cell; the paragraph is copied in place once per row, cut so
the line in question is its FIRST line (text from Word's own line start, first-line indent set to
the continuation lines'), and its right indent stepped by 5 twips (0.25pt). Row "k" is the cell's
own width (right indent unchanged); rows before it are wider (need less), rows after narrower.
The variant rows are offset by the length they add or remove (in 5-twip steps, noted below), so
their row "k" / "K" / "11" needs what row k does.
  cend-jin.docx  zh-073c9234's cell "…約15%，提升定量降雨估計應用於強降雨監測效能；精進" (PMingLiU 12,
                mode 15). Word's print takes "進" ~7.7pt over at the cell's width.
                rows a..y: the line as is;  A..Y: "15%" replaced by "十五成" (no automatic spaces; offset -49 steps, the line 12.4pt longer).
  cend-cheng.docx zh-147bdae0's p60 cell "做Open Source（開放原始碼），完整公開軟體程…" (標楷體 12).
                Word's print takes "程" ~2.7pt over: one automatic space and the word space give.
                rows a..y: as is;  A..Y: "OpenSource" (no word space; offset +24, 6pt shorter);  1..25: "做 Open Source"
                (a second word space, beside the ideograph; offset -24).
Read: for each row, the row letter and line 1's last two characters (and whether it is the take
character); for rows k, K and 11 the per-character x origin of line 1.
usage: gen.py CORPUS_DOCX_DIR OUTDIR"""
import sys, re, zipfile, os, glob
src_dir, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
L = 'abcdefghijklmnopqrstuvwxy'; U = L.upper(); N = [str(i) for i in range(1, 26)]
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
    # numbering off (the line is not the first one), first line at the continuation lines'
    base = re.sub(r'<w:numPr>.*?</w:numPr>', '', base, flags=re.S)
    ind = re.search(r'<w:ind\b[^>]*/>', base)
    left = right = 0
    if ind:
        g = lambda a: int((re.search(r'w:%s="(-?\d+)"' % a, ind.group(0)) or [0, 0])[1])
        left, right = g('left') or g('start'), g('right') or g('end')
    def row(p, step):
        newind = '<w:ind w:left="%d" w:right="%d" w:firstLine="0"/>' % (left, right + step * 5)
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
build('zh-073c9234', '精進新一代雙偏極化', '準確度約15%', [(L, lambda p: p, 0), (U, sub('15%', '十五成'), -49)], 'cend-jin.docx')
build('zh-147bdae0', '完整公開軟體程', '做Open Source', [(L, lambda p: p, 0), (U, sub('Open Source', 'OpenSource'), 24), (N, sub('做', '做 '), -24)], 'cend-cheng.docx')
