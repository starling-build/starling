#!/usr/bin/env python3
"""folder-only.py DIR FILE... — print the changed files (the arguments) under apps/OfficeApp/Sources/OfficeApp/DIR/ that only that folder's code uses.
The test of test/tools/sheets-only.py, for any app folder (Slides, Sheets): a file qualifies when no name it declares at top level is used by any
Swift file OUTSIDE the folder (the other apps, shared drawing, fonts, the text layer, sdk/), and it extends no type declared outside the folder.
Decided by the files' text, never by a doc or file-name list. ~/bin/gate-scope uses it to skip the Word step for Slides-only or Sheets-only batches
(amd-8, 2026-11-27, LANDING-RULES "Faster pre-land checks"; starling-bd: only files clearly owned by one app narrow the gate)."""
import os, re, sys, subprocess
root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
if len(sys.argv) < 2 or "/" in sys.argv[1]: sys.exit("usage: folder-only.py DIR FILE...")
SRC = "apps/OfficeApp/Sources/OfficeApp"; FD = SRC + "/" + sys.argv[1] + "/"
decl = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|fileprivate|private|final|indirect|open)\s+)*(?:struct|class|enum|protocol|typealias|func|actor|let|var)\s+(\w+)", re.M)
ext = re.compile(r"^(?:(?:public|internal|fileprivate|private)\s+)?extension\s+([\w.]+)", re.M)
tok = re.compile(r"[A-Za-z_]\w*")
def read(p):
    try: return open(os.path.join(root, p), errors="ignore").read()
    except OSError: return None
want = [f for f in sys.argv[2:] if f.startswith(FD) and f.endswith(".swift")]
if not want or not os.path.isdir(os.path.join(root, FD)): sys.exit(0)
own = set()                       # names declared anywhere in the folder (subfolders included)
for dp, dn, fn in os.walk(os.path.join(root, FD)):
    for f in fn:
        if f.endswith(".swift"):
            t = read(os.path.relpath(os.path.join(dp, f), root))
            if t: own |= set(decl.findall(t))
used = set()                      # identifiers used outside the folder: the rest of OfficeApp, its sibling targets, and sdk/
for base in ("apps/OfficeApp/Sources", "sdk/Sources"):
    for dp, dn, fn in os.walk(os.path.join(root, base)):
        if (os.path.relpath(dp, root) + "/").startswith(FD): continue
        for f in fn:
            if f.endswith(".swift"):
                try: used |= set(tok.findall(open(os.path.join(dp, f), errors="ignore").read()))
                except OSError: pass
for f in want:
    t = read(f)
    if t is None: continue          # deleted: not proven folder-only, so it keeps every set
    names = set(decl.findall(t))
    if any(n in used for n in names): continue
    if any(e.split(".")[0] not in own or e.split(".")[0] in used for e in ext.findall(t)): continue
    print(f)
