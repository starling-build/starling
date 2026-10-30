# build3.py SRC.docx OUTDIR — lab p3dplot3: where Word for Windows sets a 3-D pie's
# INSIDE (best-fit) labels as their slices turn. zh-27a874b7's chart 1 (page 3; rotX
# 30, untitled, no legend, auto layout), its labels' manual moves removed (= B00),
# turned by view3D rotY 0..330 in 30-degree steps. 科技 (21%) and 文化 (12%) carry
# three-line labels that stand inside or out by turn. Measure with measl.py.
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src)
names = z.namelist()
data = {n: z.read(n) for n in names}
C = "word/charts/chart1.xml"
base = re.sub(r"<c:dLbl>.*?</c:dLbl>", "", data[C].decode("utf-8"), flags=re.S)
n = 0
for rot in range(0, 360, 30):
    s = re.sub(r'<c:rotY val="\d+"/>', f'<c:rotY val="{rot}"/>', base)
    assert rot == 0 or s != base
    with zipfile.ZipFile(os.path.join(out, f"t-C{rot:03d}.docx"), "w", zipfile.ZIP_DEFLATED) as w:
        for nm in names:
            w.writestr(nm, s.encode("utf-8") if nm == C else data[nm])
    n += 1
print(n, "documents in", out)
