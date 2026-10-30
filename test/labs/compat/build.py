#!/usr/bin/env python3
"""Lab compat: does Word for Windows' hang of a line's last full stop / comma
(and its kerning of pairs) follow the PRESENCE of the settings' w:compat element?

Four documents, run from the repository root: python3 test/labs/compat/build.py
  a-asis.docx         fdo63164-1 (lo-b7c1b8df1d85ac9c) untouched: settings carry no w:compat
  b-emptycompat.docx  the same with an EMPTY <w:compat/> added to the settings
  c-mode15.docx       the same with <w:compat> naming compatibilityMode 15
  d-guard-nocompat.docx  official form_footnotes (mode absent, a w:compat block) with its w:compat removed
Read in each print: page 4's paragraph "Die Baumaßnahme beinhaltet ..." (lines end
"... über der Wasserschöpfe" / "... auf einer Länge von ca. 65m." the 65m. past the margin
only if the hang is on); a, b: hang? c: no hang?  d: compare with form_footnotes' own print.
"""
import re, sys, zipfile, os
SRC = "test/corpus/docx/docs/"
OUT = "test/labs/compat/docx/"
def rewrite(src, dst, fn):
    zin = zipfile.ZipFile(src)
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "word/settings.xml":
                data = fn(data.decode("utf8")).encode("utf8")
            zout.writestr(item, data)
MODE15 = '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>'
def add(compat):
    def f(s):
        assert "<w:compat" not in s
        i = s.index("</w:settings>")
        return s[:i] + compat + s[i:]
    return f
def drop(s):
    n = re.sub(r"<w:compat>.*?</w:compat>|<w:compat/>", "", s, flags=re.S)
    assert n != s
    return n
os.makedirs(OUT, exist_ok=True)
fdo = SRC.replace("docx/docs/", "docx/lo/docs/") + "lo-b7c1b8df1d85ac9c.docx"
rewrite(fdo, OUT + "a-asis.docx", lambda s: s)
rewrite(fdo, OUT + "b-emptycompat.docx", add("<w:compat/>"))
rewrite(fdo, OUT + "c-mode15.docx", add(MODE15))
rewrite(SRC + "form_footnotes.docx", OUT + "d-guard-nocompat.docx", drop)
print("built", sorted(os.listdir(OUT)))
