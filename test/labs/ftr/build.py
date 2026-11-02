# build.py SRC.docx OUTDIR — lab ftr: why does Word for Windows print a PAGE field in a footer text box
# (zh-2e7ef069 p10: footer2, numberInDash, box 36.1pt wide, wrap none, spAutoFit; BOTH the wps Choice and the
# VML Fallback copies carry 14pt runs; the footer style says 9pt) at 9pt, " - 10 - ", when the same document's
# footer1 box ("— " + PAGE + " —", 14pt runs) prints 14pt? Each document is ELEVEN pages (a page break after
# each of ten lines) in the source's last section, so the footer reads "- 1 -" ... "- 11 -" (cached result "- 1 -").
# Variants (footer2.xml / document.xml changes only):
#  v0 as is
#  v1 no \* MERGEFORMAT switch on the field
#  v2 every run size in the box removed (Choice and Fallback), so the style's 9pt is all there is
#  v3 pgNumType decimal (result "1" .. "11") instead of numberInDash
#  v4 the box 100pt wide (wp:extent, a:ext and the VML width), runs 14pt as is
#  v5 wrap="square" instead of "none"
#  v6 numberInDash and cached result "- 10 -" (the cache as long as page 10's)
import re, sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
z = zipfile.ZipFile(src); data = {n: z.read(n) for n in z.namelist() if not n.endswith("/")}
doc = data["word/document.xml"].decode("utf-8")
body0 = doc.index("<w:body>") + len("<w:body>")
sect = re.findall(r"<w:sectPr.*?</w:sectPr>", doc, re.S)[-1]
paras = "".join('<w:p><w:r><w:t>footer lab line %d</w:t></w:r></w:p>%s' % (i + 1, '<w:p><w:r><w:br w:type="page"/></w:r></w:p>' if i < 10 else "") for i in range(11))
newdoc = doc[:body0] + paras + sect + "</w:body></w:document>"
f2 = data["word/footer2.xml"].decode("utf-8")
def make(tag, f2x, docx=newdoc):
    d = dict(data); d["word/footer2.xml"] = f2x.encode("utf-8"); d["word/document.xml"] = docx.encode("utf-8")
    with zipfile.ZipFile(os.path.join(out, "ftr-%s.docx" % tag), "w", zipfile.ZIP_DEFLATED) as o:
        for n, b in d.items(): o.writestr(n, b)
make("v0", f2)
make("v1", f2.replace(" PAGE  \\* MERGEFORMAT ", " PAGE "))
make("v2", re.sub(r'<w:sz w:val="28"/><w:szCs w:val="28"/>', "", f2))
make("v3", f2, newdoc.replace('<w:pgNumType w:fmt="numberInDash"/>', ""))
make("v4", f2.replace('cx="458470"', 'cx="1270000"').replace('cx="458368"', 'cx="1270000"').replace("width:36.1pt", "width:100pt"))
make("v5", f2.replace('wrap="none"', 'wrap="square"'))
make("v6", f2.replace("<w:t>- 1 -</w:t>", "<w:t>- 10 -</w:t>"))
print(sorted(os.listdir(out)))
