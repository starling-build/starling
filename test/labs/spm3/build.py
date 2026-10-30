# build.py SRC.docx OUTDIR — lab spm3: why Word for Windows starts zh-7773163d's lines with a closing mark
# (p44 "，應作狹義解釋", p55 "，同時或先後為之", p49's "。" alone) and hangs none, where other old-mode
# doNotCompress documents (zh-4c5da793, mode 12; zh-8892701a, no mode) hang theirs. zh-7773163d alone has no
# themeFontLang, ulTrailSpace and shapeLayoutLikeWW8 in w:compat, and 細明體_HKSCS for its text. One change each:
#   S0 as is; S1 + themeFontLang eastAsia zh-TW; S2 - ulTrailSpace; S3 - shapeLayoutLikeWW8;
#   S4 the text face 細明體_HKSCS -> 新細明體 (fontTable and every rFonts); S5 = S1+S2+S3; S6 compatibilityMode 12 added.
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); names = z.namelist(); data = {n: z.read(n) for n in names}
S = data["word/settings.xml"].decode("utf-8")
def lang(s): return s.replace("</w:settings>", '<w:themeFontLang w:val="en-US" w:eastAsia="zh-TW"/></w:settings>')
def noul(s): return s.replace("<w:ulTrailSpace/>", "")
def nosl(s): return s.replace("<w:shapeLayoutLikeWW8/>", "")
def mode12(s): return s.replace("</w:compat>", '<w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="12"/></w:compat>')
V = {"S0": [], "S1": [lang], "S2": [noul], "S3": [nosl], "S4": "face", "S5": [lang, noul, nosl], "S6": [mode12]}
for k, fs in V.items():
    d = dict(data)
    if fs == "face":
        for n in names:
            if n.endswith(".xml") and n.startswith("word/"):
                d[n] = d[n].decode("utf-8").replace("細明體_HKSCS", "新細明體").encode("utf-8")
    else:
        s = S
        for f in fs:
            t = f(s); assert t != s, (k, f); s = t
        d["word/settings.xml"] = s.encode("utf-8")
    with zipfile.ZipFile(os.path.join(out, f"t-{k}.docx"), "w", zipfile.ZIP_DEFLATED) as w:
        for n in names: w.writestr(n, d[n])
print(len(V), "documents in", out)
