# build_h.py REPO OUTDIR — lab sqz4: which variable makes Word for Windows break between "×" and a digit?
# Lab sqz3 (line G of zh-6b242483 "…9（家）|×1（每年1次", mode 14, FangSong 16pt, zh-CN) showed Word keeps "×1" together
# (refused at 16.02pt of room for a 15.96 "×", taken only when the marks can give 7pt for the 24pt "×1"), while the Traditional
# cells of the corpus (PMingLiU, zh-TW) end a line "…）×" and open the next "100%". Language and face move together there.
# Four variants of the G paragraph, each at four right margins (0, -60, -120, -200 twips: room 11, 14, 17, 21pt for the lone "×"):
#   a  as is (zh-CN, 仿宋_GB2312)       b  language zh-TW everywhere (styles, themeFontLang, the run), face unchanged
#   c  face PMingLiU, language unchanged   d  both
# Read-out (meas.py): a LONE "×" ending line 1 (…家）× | 1（每年) = Word breaks × | digit in that variant; "×1" always
# together = it does not. A variant that breaks is the key for the rule.
import re, sys, os, zipfile, subprocess, tempfile
repo, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
tmp = tempfile.mkdtemp()
subprocess.check_call([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_g.py"), repo, tmp])
src = next(os.path.join(tmp, f) for f in os.listdir(tmp) if f.startswith("t-G-W0-"))
z = zipfile.ZipFile(src); names = z.namelist(); data = {n: z.read(n) for n in names}
def variant(v, d):
    doc = data["word/document.xml"].decode("utf-8"); sty = data["word/styles.xml"].decode("utf-8"); st = data["word/settings.xml"].decode("utf-8")
    if v in "bd":
        sty = sty.replace('w:eastAsia="zh-CN"', 'w:eastAsia="zh-TW"'); st = st.replace('w:eastAsia="zh-CN"', 'w:eastAsia="zh-TW"')
    if v in "cd":
        doc = re.sub(r"<w:rFonts [^>]*/>", '<w:rFonts w:hint="eastAsia" w:ascii="PMingLiU" w:hAnsi="PMingLiU" w:eastAsia="PMingLiU" w:cs="PMingLiU"/>', doc)
    if v in "bd":   # (w:lang follows w:rFonts in a run's properties)
        doc = re.sub(r"(<w:rFonts [^>]*/>)", r'\1<w:lang w:eastAsia="zh-TW"/>', doc)
    doc = re.sub(r'(<w:pgMar[^>]*w:right=")(-?\d+)', lambda m: m.group(1) + str(int(m.group(2)) + d), doc)
    return doc, sty, st
n = 0
for v in "abcd":
    for d in (0, -60, -120, -200):
        doc, sty, st = variant(v, d)
        with zipfile.ZipFile(os.path.join(out, f"t-H-{v}W{d}.docx"), "w", zipfile.ZIP_DEFLATED) as w:
            for nm in names:
                w.writestr(nm, doc.encode() if nm == "word/document.xml" else sty.encode() if nm == "word/styles.xml" else st.encode() if nm == "word/settings.xml" else data[nm])
        n += 1
print(n, "documents in", out)
