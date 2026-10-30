# build.py SRC.docx OUTDIR — lab p3dplot: Word's auto plot box for a 3-D pie.
# Varies zh-27a874b7's chart 1 (page 3, untitled 3-D pie, rotX 30, no legend,
# outside best-fit labels with manual moves); chart 2 is left as a control.
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
names = z.namelist()
data = {n: z.read(n) for n in names}
C = "word/charts/chart1.xml"
base = data[C].decode("utf-8")

def strip_dlbl(s):   # remove per-point label moves, keep the series' own dLbls settings
    return re.sub(r"<c:dLbl>.*?</c:dLbl>", "", s, flags=re.S)
def no_labels(s):    # the series' labels off
    return re.sub(r"<c:dLbls>.*?</c:dLbls>", "<c:dLbls><c:delete val=\"1\"/></c:dLbls>", s, count=1, flags=re.S)
def rotx(v):
    return lambda s: re.sub(r'<c:rotX val="\d+"/>', f'<c:rotX val="{v}"/>', s)
def title_deleted(s):
    return s.replace('<c:autoTitleDeleted val="0"/>', '<c:autoTitleDeleted val="1"/>')
def title(s):
    t = ('<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:r><a:rPr lang="zh-TW"/>'
         '<a:t>標題測試</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title><c:autoTitleDeleted val="0"/>')
    return s.replace('<c:autoTitleDeleted val="0"/>', t)
def legend(pos):
    return lambda s: s.replace("</c:plotArea>", f'</c:plotArea><c:legend><c:legendPos val="{pos}"/><c:overlay val="0"/></c:legend>', 1)
def layout(target):
    lay = (f'<c:layout><c:manualLayout>{"<c:layoutTarget val=\"inner\"/>" if target == "inner" else ""}'
           '<c:xMode val="edge"/><c:yMode val="edge"/><c:x val="0.2"/><c:y val="0.15"/><c:w val="0.6"/><c:h val="0.7"/>'
           '</c:manualLayout></c:layout>')
    return lambda s: s.replace("<c:plotArea><c:layout/>", "<c:plotArea>" + lay, 1)

V = {
    "A00-orig":        [],
    "A01-nolabels":    [no_labels],
    "A02-nomoves":     [strip_dlbl],
    "A03-titledel":    [title_deleted],
    "A04-title":       [title],
    "A05-legR":        [legend("r")],
    "A06-legB":        [legend("b")],
    "A07-rotx15":      [rotx(15)],
    "A08-rotx50":      [rotx(50)],
    "A09-inner":       [layout("inner")],
    "A10-outer":       [layout("outer")],
    "A11-nolab-rx15":  [no_labels, rotx(15)],
    "A12-nolab-rx50":  [no_labels, rotx(50)],
    "A13-nolab-title": [no_labels, title],
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
