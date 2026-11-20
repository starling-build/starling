#!/usr/bin/env python3
"""lab-compat1415b.py BIN WORKDIR — the compat 14 / 15 floating-table labs (wip/lab-q3 a6e033ec6, test/labs/compat1415b) through BIN, against Word for Windows.

Each lab is floating Table1 (19-23 rows, tblpY 323) + empty paragraphs + floating Table2 (6 rows, tblpY 323); the number measured is the baseline of the
line "26" (Table2's last-row number, the first thing on the page Table2 lands on). Word's: [page, y] from windows' lab prints (the second number of each pair they sent; the first is Table2:A1's baseline), 2026-11-02.
All 20 agree, 2026-11-02 (anchor lab test/labs/anchor, wip/lab-anchor: in compat 15 the second table hangs 45pt under the baseline of the empty line just before it, when its first row fits there; a lone empty between the tables that does not fit is carried). Run from the repo root. Prints one row per lab and the count that agree (page equal and y within 1.0pt)."""
import glob, io, os, subprocess, sys, tarfile
import pymupdf

WORD = {  # name: (page, y) in c14 | c15
    "after2": ((2, 120.3), (2, 120.3)), "fs6": ((2, 131.7), (2, 94.8)), "fs11": ((2, 145.7), (2, 94.8)), "fs14": ((2, 154.1), (2, 154.1)),
    "fs20": ((2, 171.0), (2, 171.0)), "sp0": ((2, 110.3), (2, 94.8)), "rows19": ((2, 94.8), (2, 49.8)), "rows20": ((2, 94.8), (2, 94.8)),
    "rows22": ((2, 145.7), (2, 94.8)), "rows23": ((2, 166.6), (2, 166.6)),
}
BIN, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
EO = os.path.realpath("engine") + "/src/out/host_release"
ENV = dict(os.environ, OFFICE_FONT_SOURCE="bundled", OFFICE_WORD_FONTS="windows", STARLING_ICU=EO + "/icudtl.dat", LD_LIBRARY_PATH=EO,
           STARLING_ENGINE_OUT=EO, FLUTTER_SWIFT_ENGINE_OUT=EO)
d = f"{WORK}/test/labs/compat1415b"
if not os.path.isdir(d):
    os.makedirs(WORK, exist_ok=True)
    tar = subprocess.run(["git", "archive", "a6e033ec6", "test/labs/compat1415b"], capture_output=True, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(tar)).extractall(WORK, filter="data")
docs = sorted(glob.glob(d + "/*.docx"))
ps = [subprocess.Popen([BIN, "--convert", x, x[:-5] + ".pdf"], env=ENV, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) for x in docs]
for p in ps: p.wait()
ok = total = 0
for name, (c14, c15) in WORD.items():
    row = []
    for mode, want in (("c14", c14), ("c15", c15)):
        got = None
        for pg in pymupdf.open(f"{d}/{name}_{mode}.pdf"):
            for b in pg.get_text("dict")["blocks"]:
                for l in b.get("lines", []):
                    if "".join(s["text"] for s in l["spans"]).strip() == "26": got = (pg.number + 1, l["spans"][0]["origin"][1])
        good = got is not None and got[0] == want[0] and abs(got[1] - want[1]) <= 1.0
        ok += good; total += 1
        row.append(f"{mode} word p{want[0]} {want[1]:6.1f} ours " + (f"p{got[0]} {got[1]:6.1f}" if got else "-") + (" ok" if good else " DIFF"))
    print(f"{name:7s}", " | ".join(row))
print(f"{ok}/{total} agree")
