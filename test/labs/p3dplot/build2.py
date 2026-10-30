# build2.py SRC.docx OUTDIR — lab p3dplot2: how Word for Windows sizes a 3-D pie
# by its labels. zh-27a874b7's chart 1 (page 3; rotX 30, untitled, no legend, auto
# layout), its labels' manual moves removed (lab p3dplot's A02 = B00), varied one
# thing at a time. Chart 2 is a control. Measure with meas.py.
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
names = z.namelist()
data = {n: z.read(n) for n in names}
C = "word/charts/chart1.xml"
base = re.sub(r"<c:dLbl>.*?</c:dLbl>", "", data[C].decode("utf-8"), flags=re.S)

def only(*keep):   # every other point's label deleted
    def f(s):
        dels = "".join(f'<c:dLbl><c:idx val="{i}"/><c:delete val="1"/></c:dLbl>' for i in range(6) if i not in keep)
        return s.replace("<c:dLbls>", "<c:dLbls>" + dels, 1)
    return f
def cats(names6):  # the categories' names (the label text)
    def f(s):
        cat = re.search(r"<c:cat>.*?</c:cat>", s, re.S).group(0)
        new = cat
        for i, n in enumerate(names6):
            new = re.sub(rf'(<c:pt idx="{i}"><c:v>)[^<]*(</c:v>)', rf"\g<1>{n}\g<2>", new)
        return s.replace(cat, new, 1)
    return f
def pos(p):        # the series' labels' position
    return lambda s: s.replace("<c:dLbls>", "<c:dLbls>", 1).replace("<c:showLegendKey", f'<c:dLblPos val="{p}"/><c:showLegendKey', 1)
def flag(name, v): # showCatName / showPercent / showVal
    return lambda s: re.sub(rf'(<c:dLbls>(?:(?!</c:dLbls>).)*?<c:{name} val=")[01]', rf"\g<1>{v}", s, count=1, flags=re.S)
def sep(t):        # the separator between a label's parts
    return lambda s: re.sub(r"<c:separator>.*?</c:separator>", f"<c:separator>{t}</c:separator>", s, count=1, flags=re.S)

V = {
    "B00-all":         [],
    "B01-only5":       [only(5)],              # 建築, 1%, a small slice
    "B02-only0":       [only(0)],              # 經濟, 53%
    "B03-only015":     [only(0, 1, 5)],
    "B04-names4":      [cats(["經濟發展", "科技研發", "文化藝術", "教育學術", "金融保險", "建築工程"])],
    "B05-names6":      [cats(["經濟發展計畫", "科技研發計畫", "文化藝術計畫", "教育學術計畫", "金融保險計畫", "建築工程計畫"])],
    "B06-outEnd":      [pos("outEnd")],
    "B07-inEnd":       [pos("inEnd")],
    "B08-ctr":         [pos("ctr")],
    "B09-nocat":       [flag("showCatName", 0)],
    "B10-nopct":       [flag("showPercent", 0)],
    "B11-valonly":     [flag("showCatName", 0), flag("showPercent", 0)],
    "B12-catonly":     [flag("showVal", 0), flag("showPercent", 0)],
    "B13-oneline":     [sep(", ")],
}
for name, fs in V.items():
    s = base
    for f in fs:
        t = f(s)
        assert t != s, (name, f)
        s = t
    with zipfile.ZipFile(os.path.join(out, f"t-{name}.docx"), "w", zipfile.ZIP_DEFLATED) as w:
        for n in names:
            w.writestr(n, s.encode("utf-8") if n == C else data[n])
print(len(V), "documents in", out)
