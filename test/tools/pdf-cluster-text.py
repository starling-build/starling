#!/usr/bin/env python3
"""Text-layer test: each cluster's text must appear exactly once in our PDF, in two readers.

usage: python3 test/tools/pdf-cluster-text.py [OFFICEAPP]   (source ~/bin/office-env.sh first; env as the sweeps use)
Makes one small docx per case (pre-base vowel, reph, reph + pre-base vowel, Arabic lam-alef, Bengali o-vowel,
Bengali conjunct, Arabic shadda, Devanagari conjunct), renders it with OfficeApp, and compares the text that
pymupdf and poppler's pdftotext extract with the source, letter by letter (spaces and line ends ignored).
Exit 1 if any case differs in either reader."""
import os, subprocess, sys, tempfile, zipfile, collections
from xml.sax.saxutils import escape
import pymupdf

APP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../apps/OfficeApp/.build/release/OfficeApp')
CASES = {
    'pre-base vowel (Devanagari ि)': ('कि मिल किताब हिंदी', 'Mangal'),
    'reph (र्म)': ('धर्म कर्म वर्ग मर्म', 'Mangal'),
    'reph + pre-base vowel (र्मि)': ('निर्मित धर्मिक कर्मिक', 'Mangal'),
    'Devanagari conjunct (क्ष त्र)': ('क्षत्रिय शिक्षा पत्र', 'Mangal'),
    'Bengali o-vowel (ো)': ('কোথায় মোটর বোন সোনা', 'Vrinda'),
    'Bengali conjunct (ক্ত)': ('শক্ত যুক্ত রক্ত মুক্তি', 'Vrinda'),
    'Arabic lam-alef': ('لا الأرض كلا بلاد', 'Arial'),
    'Arabic shadda': ('مُحَمَّد شَدَّة', 'Arial'),
}
def docx(text, font, path):
    rt = ' <w:rtl/>' if font == 'Arial' else ''
    body = ('<w:p><w:r><w:rPr><w:rFonts w:ascii="%s" w:hAnsi="%s" w:cs="%s"/><w:sz w:val="40"/><w:szCs w:val="40"/>%s</w:rPr><w:t>%s</w:t></w:r></w:p>'
            % (font, font, font, ' <w:cs/>' + rt, escape(text)))
    parts = {
        '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        '_rels/.rels': '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
        'word/document.xml': '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>%s<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>' % body,
    }
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, b in parts.items(): z.writestr(n, b.encode())
def letters(t): return collections.Counter(c for c in t if not c.isspace() and c not in '‌‍')
bad = 0
tmp = tempfile.mkdtemp(prefix='clustertext-')
for i, (name, (text, font)) in enumerate(CASES.items()):
    d = os.path.join(tmp, 'c%d.docx' % i); p = os.path.join(tmp, 'c%d.pdf' % i); docx(text, font, d)
    r = subprocess.run([APP, '--convert', d, p], capture_output=True)
    if not os.path.exists(p): print('FAIL  %-34s no PDF (exit %d)' % (name, r.returncode)); bad += 1; continue
    got = {'mupdf': ''.join(pg.get_text() for pg in pymupdf.open(p))}
    try: got['poppler'] = subprocess.run(['pdftotext', '-enc', 'UTF-8', p, '-'], capture_output=True, text=True).stdout
    except FileNotFoundError:
        if i == 0: print('SKIP  poppler: pdftotext not installed (apt install poppler-utils); only MuPDF checked')
    want = letters(text)
    for rd, t in got.items():
        have = letters(t); diff = {c: have[c] - want[c] for c in set(have) | set(want) if have[c] != want[c]}
        if diff: bad += 1; print('FAIL  %-34s %-8s %s' % (name, rd, ' '.join('U+%04X:%+d' % (ord(c), n) for c, n in sorted(diff.items()))))
        else: print('ok    %-34s %s' % (name, rd))
sys.exit(1 if bad else 0)
