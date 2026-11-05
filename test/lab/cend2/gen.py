#!/usr/bin/env python3
"""Lab cend2 (for amd-opus), after lab cend: two cell lines Word for Windows REFUSES to squeeze, which our
share test cannot tell from cend's "進" (taken). Same method as cend: the paragraph copied in place once
per row, cut so the line is its FIRST line, the right indent stepped by 5 twips (0.25pt); row "k" / "K" /
"11" is the cell's own width.
  cend2-kuo.docx  zh-073c9234 p9's cell "提供優質永續服務，並為未來M4提供良善基盤及易於擴" (12pt, mode 15):
                  Word refuses "充" ~5.7pt over (two automatic spaces, one mark).
  cend2-shi.docx  zh-12db188f p3's cell "社（一）字第89067628號函" (14pt, mode 15): Word refuses "釋".
  Each: rows a..y the line as is;  A..Y automatic spacing OFF for the paragraph (autoSpaceDE/DN 0, the
  same glyphs, no automatic spaces; the line shorter by their width, so the rows narrower by an estimate of it);  1..25 the line's marks replaced by
  ideographs of the same em width (no marks; the rows wider, -12 and -43 steps, as the line then has little to give).
Read: for each row, line 1's last two characters and line 2's head (as cend); for rows k, K and 11 the
per-character x origin of line 1.
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
        # (Character-unit indents zeroed: a style's leftChars beats w:left — zh-12db188f's List Paragraph
        # has leftChars 200, which its paragraph cancels with leftChars 0.)
        newind = '<w:ind w:leftChars="0" w:left="%d" w:rightChars="0" w:right="%d" w:firstLineChars="0" w:firstLine="0"/>' % (left, right + step * 5)
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
def subs(*pairs):
    def f(p):
        for a, b in pairs: p = sub(a, b)(p)
        return p
    return f
LATER = ('bidi', 'adjustRightInd', 'snapToGrid', 'spacing', 'ind', 'contextualSpacing', 'mirrorIndents',
         'suppressOverlap', 'jc', 'textDirection', 'textAlignment', 'textboxTightWrap', 'outlineLvl', 'divId',
         'cnfStyle', 'rPr', 'sectPr', 'pPrChange')
def no_autospace(p):
    """autoSpaceDE/DN off, in schema order inside the paragraph's own pPr."""
    p = re.sub(r'<w:autoSpaceD[EN]\b[^>]*/>', '', p)
    tag = '<w:autoSpaceDE w:val="0"/><w:autoSpaceDN w:val="0"/>'
    m = re.search(r'<w:pPr>(.*?)</w:pPr>', p, flags=re.S)
    if not m: return re.sub(r'(<w:p[ >][^>]*>|<w:p>)', lambda k: k.group(1) + '<w:pPr>' + tag + '</w:pPr>', p, count=1)
    inner = m.group(1)
    at = min([k.start() for k in (re.search(r'<w:%s\b' % t, inner) for t in LATER) if k] or [len(inner)])
    return p[:m.start(1)] + inner[:at] + tag + inner[at:] + p[m.end(1):]
build('zh-073c9234', '易於擴充之系統架構', '提供優質永續服務', [(L, lambda p: p, 0), (U, no_autospace, 22), (N, sub('，並為', '並並為'), -12)], 'cend2-kuo.docx')
build('zh-12db188f', '89067628', '社', [(L, lambda p: p, 0), (U, no_autospace, 25), (N, subs(('（', '甲'), ('）', '乙')), -43)], 'cend2-shi.docx')
