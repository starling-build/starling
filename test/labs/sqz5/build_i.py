# build_i.py REPO OUTDIR — lab sqz5: is it the table cell, or the alignment, that lets Word break between "×" and a digit?
# Labs sqz3/sqz4: in zh-6b242483's BODY paragraph (left-aligned, mode 14, FangSong, zh-CN) Word never leaves the "×" alone from its "1",
# whatever the language (zh-TW) or face (PMingLiU); lab sqz F4 (docGrid removed) did not change it. The corpus's break-allowed cases
# ("…）×" | "100%", "…）×" | "50%") are all inside TABLE CELLS (Traditional, justified by the Web style, no docGrid).
# Variants of the G paragraph, each at three right margins (0, -60, -100 twips: room 11, 14, 16.02pt for the lone "×"):
#   a  as is (left-aligned body paragraph)     j  jc both, still a body paragraph
#   t  the same paragraph in a one-cell table of the text width (cell margins 0)     tj  both
# Read-out: a LONE "×" ending line 1 ("…家）×" | "1（每年") = Word breaks × | digit there; "×1" always together = it does not.
import re, sys, os, zipfile, subprocess, tempfile
repo, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
tmp = tempfile.mkdtemp()
subprocess.check_call([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_g.py"), repo, tmp])
src = next(os.path.join(tmp, f) for f in os.listdir(tmp) if f.startswith("t-G-W0-"))
z = zipfile.ZipFile(src); names = z.namelist(); data = {n: z.read(n) for n in names}
def variant(v, d):
    doc = data["word/document.xml"].decode("utf-8")
    left = int(re.search(r'<w:pgMar[^>]*w:left="(\d+)"', doc).group(1)); right = int(re.search(r'<w:pgMar[^>]*w:right="(-?\d+)"', doc).group(1)) + d
    width = 11906 - left - right
    doc = re.sub(r'(<w:pgMar[^>]*w:right=")(-?\d+)', lambda m: m.group(1) + str(right), doc)
    m = re.search(r"<w:p>.*?</w:p>", doc, re.S); p = m.group(0)
    if "j" in v: p = p.replace('<w:jc w:val="left"/>', '<w:jc w:val="both"/>')
    if v.startswith("t"):
        tbl = (f'<w:tbl><w:tblPr><w:tblW w:w="{width}" w:type="dxa"/><w:tblInd w:w="0" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
               f'<w:tblCellMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
               f'<w:tblGrid><w:gridCol w:w="{width}"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/></w:tcPr>{p}</w:tc></w:tr></w:tbl><w:p/>')
        p = tbl
    return doc[:m.start()] + p + doc[m.end():]
n = 0
for v in ("a", "j", "t", "tj"):
    for d in (0, -60, -100):
        doc = variant(v, d)
        with zipfile.ZipFile(os.path.join(out, f"t-I-{v}W{d}.docx"), "w", zipfile.ZIP_DEFLATED) as w:
            for nm in names: w.writestr(nm, doc.encode() if nm == "word/document.xml" else data[nm])
        n += 1
print(n, "documents in", out)
