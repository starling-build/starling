#!/usr/bin/env python3
"""Lab gsq: how much a line's marks give on a character grid (zh-7a16a243,
mode 15, compressPunctuation, docGrid linesAndChars charSpace 4127 = 17.0076pt
cells at 16pt 標楷體). Word for Windows leaves two lines a character short where
ours squeezes the marks for it:
  A  p14 "率可達560％×1.2=672％)，然上開「允建樓地板面" | "積保障」…"  (ours takes 積,
     13.02pt over, "，" and "「" giving 8.5 each)
  B  p26 "積獎勵所獲得之18,463.2㎡獎勵「容積樓地板面" | "積」（如加計…"  (ours takes
     "積」", 0.52 over with "」" at half before "（")
Each paragraph starts at that line, the paragraph's runs as written, list
number off, the line's left edge where it was (w:ind left 1361, no first-line
indent). Rows k = 0..17: right indent -20k twips (the line 1pt longer a step).
  gsq-grid.docx    as the document is (on its grid)
  gsq-nogrid.docx  docGrid removed (16pt characters, no grid)
Read: for each row, the first line's last character.
usage: gen.py SOURCE.docx OUTDIR"""
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
doc = z.read('word/document.xml').decode('utf-8')
def para_with(key):
    # the paragraph whose text contains key
    for m in re.finditer(r'<w:p [^>]*>.*?</w:p>', doc, re.S):
        text = ''.join(re.findall(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', m.group(0)))
        if key in text: return m.group(0), text
    raise SystemExit('no ' + key)
def cut_from(p, start):
    # drop text before `start` (through the runs), keep the runs after it
    text = ''.join(re.findall(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', p))
    at = text.index(start)
    body = p[p.index('</w:pPr>') + len('</w:pPr>'):p.rindex('</w:p>')]
    out, seen = [], 0
    for r in re.finditer(r'<w:r[ >].*?</w:r>', body, re.S):
        run = r.group(0)
        ts = re.findall(r'<w:t(?: [^>]*)?>([^<]*)</w:t>', run)
        t = ''.join(ts)
        if seen + len(t) <= at: seen += len(t); continue
        if seen < at:
            keep = t[at - seen:]
            run = re.sub(r'<w:t(?: [^>]*)?>[^<]*</w:t>', '', run, count=len(ts) - 1) if len(ts) > 1 else run
            run = re.sub(r'<w:t(?: [^>]*)?>[^<]*</w:t>', '<w:t xml:space="preserve">' + keep + '</w:t>', run, count=1)
        seen += len(t)
        out.append(run)
    return ''.join(out)
lines = [('率可達560', '率可達560'), ('獎勵所獲得之18,463.2', '積獎勵所獲得之18,463.2')]
paras = []
for key, start in lines:
    p, text = para_with(key)
    runs = cut_from(p, start)
    for k in range(18):
        ppr = ('<w:pPr><w:pStyle w:val="2"/><w:numPr><w:ilvl w:val="1"/><w:numId w:val="0"/></w:numPr>'
               f'<w:ind w:left="1361" w:right="{-20 * k}" w:firstLine="0"/><w:rPr><w:b w:val="0"/></w:rPr></w:pPr>')
        paras.append('<w:p>' + ppr + runs + '</w:p>')
body_s = doc.index('<w:body>') + len('<w:body>')
sect = doc[doc.rindex('<w:sectPr'):doc.rindex('</w:body>')]
new = doc[:body_s] + ''.join(paras) + sect + doc[doc.rindex('</w:body>'):]
os.makedirs(out, exist_ok=True)
for name, d in [('grid', new), ('nogrid', re.sub(r'<w:docGrid [^>]*/>', '', new))]:
    with zipfile.ZipFile(os.path.join(out, f'gsq-{name}.docx'), 'w', zipfile.ZIP_DEFLATED) as o:
        for n in z.namelist():
            o.writestr(n, d if n == 'word/document.xml' else z.read(n))
