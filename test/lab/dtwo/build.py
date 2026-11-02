#!/usr/bin/env python3
"""Lab dtwo (for Windows Word, from lenovo-5): n830205's (lo-9f27ef40) deleted paragraphs, cut from the real file, texts made unique.
usage: build.py SRC.docx OUTDIR   (SRC = test/corpus/docx/lo/docs/lo-9f27ef4097b11c63.docx, in the repo)
Writes, each a track-changes document of the SAME deleted paragraphs, so Word shows its Deleted balloons:
  d1.docx  source paragraphs 36-45 (XXX / XXX / empty / two-run / empty / two-run ...), every deleted text numbered t01, t02 ...
  d2.docx  source paragraphs 39-45 only (starts at the first two-run paragraph, nothing before)
  d3.docx  source paragraphs 36-40 only
  d4.docx  d1 with every pPrChange removed
  d5.docx  source paragraphs 33-45 WITH the two section breaks kept (34 and 35), as in the original
Print each to PDF (markup shown, as the Windows box does) and send the PDFs; what we need is the Deleted balloon's lines, in order."""
import sys, os, re, zipfile
import xml.etree.ElementTree as ET
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
src, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
zin = zipfile.ZipFile(src)
FILES = [(i.filename, zin.read(i.filename)) for i in zin.infolist()]
raw = zin.read('word/document.xml').decode('utf8')
for m in re.finditer(r'xmlns:(\w+)="([^"]+)"', raw): ET.register_namespace(m.group(1), m.group(2))
ET.register_namespace('', 'http://www.w3.org/XML/1998/namespace') if False else None
root = ET.fromstring(raw)
body = root.find(f'{{{W}}}body'); paras = [p for p in body if p.tag == f'{{{W}}}p']
sect = body.find(f'{{{W}}}sectPr')
def cut(lo, hi, nochange=False, keepsect=False):
    n = [0]
    chosen = []
    import copy
    for p in paras[lo:hi]:
        q = copy.deepcopy(p)
        pr = q.find(f'{{{W}}}pPr')
        if not keepsect and pr is not None and pr.find(f'{{{W}}}sectPr') is not None: pr.remove(pr.find(f'{{{W}}}sectPr'))
        if nochange and pr is not None and pr.find(f'{{{W}}}pPrChange') is not None: pr.remove(pr.find(f'{{{W}}}pPrChange'))
        for t in q.iter(f'{{{W}}}delText'):
            n[0] += 1; t.text = f't{n[0]:02d}'
        chosen.append(q)
    return chosen
def write(name, ps, mode=None):
    r = ET.fromstring(raw); b = r.find(f'{{{W}}}body')
    for e in list(b): b.remove(e)
    for p in ps: b.append(p)
    if sect is not None:
        import copy
        b.append(copy.deepcopy(sect))
    data = ET.tostring(r, encoding='utf-8', xml_declaration=True)
    with zipfile.ZipFile(os.path.join(out, name), 'w', zipfile.ZIP_DEFLATED) as z:
        for fn, blob in FILES:
            z.writestr(fn, data if fn == 'word/document.xml' else blob)
write('d1.docx', cut(36, 46)); write('d2.docx', cut(39, 46)); write('d3.docx', cut(36, 41)); write('d4.docx', cut(36, 46, True)); write('d5.docx', cut(33, 46, False, True))
print('5 docs')
if len(sys.argv) > 3:   # build.py SRC OUT LO HI  -> r.docx, paragraphs LO..HI-1 (local experiments)
    write('r.docx', cut(int(sys.argv[3]), int(sys.argv[4])))
