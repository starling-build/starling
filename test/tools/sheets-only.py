#!/usr/bin/env python3
"""sheets-only.py FILE... — print the changed files (read from the arguments) that only the Sheets path uses, so the render gate can skip its Slides step.
A file under apps/OfficeApp/Sources/OfficeApp/Sheets/ qualifies when no name it declares at top level is used by any Swift file OUTSIDE Sheets/ (Slides, Word,
shared drawing, fonts, the text layer ...), and it extends no type declared outside Sheets/ (an extension of Color, String or a Slides type changes shared behaviour).
Decided by the files' text, never by a doc or file-name list (amd-8, 2026-11-23, starling-bd's rule: anything the Slides path compiles or reads keeps Slides on)."""
import os, re, sys, subprocess
root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
SRC = "apps/OfficeApp/Sources/OfficeApp"; SH = SRC + "/Sheets/"
decl = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|fileprivate|private|final|indirect|open)\s+)*(?:struct|class|enum|protocol|typealias|func|actor|let|var)\s+(\w+)", re.M)
ext = re.compile(r"^(?:(?:public|internal|fileprivate|private)\s+)?extension\s+([\w.]+)", re.M)
tok = re.compile(r"[A-Za-z_]\w*")
def read(p):
    try: return open(os.path.join(root, p), errors="ignore").read()
    except OSError: return None
want = [f for f in sys.argv[1:] if f.startswith(SH) and f.endswith(".swift")]
if not want: sys.exit(0)
sheets_decl = set()
for d in ("Sheets",):
    for f in os.listdir(os.path.join(root, SH)):
        t = read(SH + f)
        if t: sheets_decl |= set(decl.findall(t))
used = set()                      # identifiers used outside Sheets/ (the whole app, sdk and the other apps' sources that could name them)
for base in (SRC, "sdk/Sources"):
    for dp, dn, fn in os.walk(os.path.join(root, base)):
        if os.path.relpath(dp, root).startswith(SH.rstrip("/")): continue
        for f in fn:
            if f.endswith(".swift"):
                try: used |= set(tok.findall(open(os.path.join(dp, f), errors="ignore").read()))
                except OSError: pass
for f in want:
    t = read(f)
    if t is None: continue          # deleted: its names are gone; the build tells if something outside used them
    names = set(decl.findall(t))
    if any(n in used for n in names): continue
    if any(e.split(".")[0] not in sheets_decl or e.split(".")[0] in used for e in ext.findall(t)): continue   # an extension adds members to a type the rest of the app names
    print(f)
