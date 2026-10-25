#!/usr/bin/env python3
"""Round-trip a corpus of real Excel workbooks through Sheets.

    test/xlsx-corpus.py [--dir DIR] [--fetch-only] [FILE.xlsx ...]

Downloads Apache POI's .xlsx test files (real workbooks from bug reports,
and fuzzer cases), LibreOffice's sc/qa regression workbooks (as lo-*) and
its chart2/qa ones (as chart-*) into DIR (default
~/.cache/starling/xlsx-corpus/in) once, then for each: read, save and
re-read (`OfficeApp --xlsx-roundtrip`). Expected: every healthy workbook
"ok"; the clusterfuzz-* and crash-* files are deliberately broken (refused
cleanly), and a few of POI's are encrypted or not workbooks at all.

The set as downloaded on 2026-10-11 is pinned in test/corpus/xlsx/books:
that copy is what the painter gate (test/xlsx-app-render.sh) sweeps once
Excel's own printing of each is beside it, and its README says where
every file comes from and what is still to be made. This script still downloads to its own DIR, whose
sibling directory takes its outputs — do not point --dir into the repo.

The formula oracle needs no rendering: `OfficeApp --xlsx-check FILE…`
recalculates a workbook and compares with the values Excel left in it.
"""
import argparse, json, os, subprocess, sys, time, urllib.request
# (Starling's own fonts, whatever this machine has: see OfficeFonts.fontSource.)
os.environ.setdefault("OFFICE_FONT_SOURCE", "bundled")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.environ.get("OFFICE_APP") or os.path.join(ROOT, "apps/OfficeApp/.build/debug/OfficeApp")
# (prefix, GitHub directory listing). The prefix keeps the sources apart in
# one directory and tells the reports which corpus a workbook came from.
SOURCES = [
    ("", "https://api.github.com/repos/apache/poi/contents/test-data/spreadsheet"),
    ("lo-", "https://api.github.com/repos/LibreOffice/core/contents/sc/qa/unit/data/xlsx"),
    ("chart-", "https://api.github.com/repos/LibreOffice/core/contents/chart2/qa/extras/data/xlsx"),
]


def fetch(dest):
    os.makedirs(dest, exist_ok=True)
    total = 0
    for prefix, url in SOURCES:
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                entries = [e for e in json.load(r) if e["name"].lower().endswith(".xlsx")]
        except Exception as e:  # noqa: BLE001 — offline, reset, truncated, or a rate-limit page
            # Offline, GitHub reset the connection, or it answered with a
            # rate-limit notice instead of the listing: the cache is the corpus.
            cached = [f for f in os.listdir(dest) if f.lower().endswith(".xlsx")]
            if not cached:
                raise
            print(f"corpus: listing unavailable ({e}); using the {len(cached)} cached workbooks")
            return len(cached)
        for e in entries:
            path = os.path.join(dest, prefix + e["name"])
            if os.path.exists(path) and os.path.getsize(path) == e["size"]:
                continue
            with urllib.request.urlopen(e["download_url"], timeout=120) as r, open(path, "wb") as f:
                f.write(r.read())
        total += len(entries)
    return total


def run(args, timeout=120):
    t = time.time()
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr, time.time() - t
    except subprocess.TimeoutExpired:
        return "timeout", "", time.time() - t


def last(text):
    lines = text.strip().splitlines()
    return lines[-1][:160] if lines else ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.expanduser("~/.cache/starling/xlsx-corpus/in"))
    ap.add_argument("--fetch-only", action="store_true")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    if not a.files:
        print("corpus:", fetch(a.dir), "workbooks in", a.dir)
    if a.fetch_only:
        return
    if not os.path.exists(APP):
        sys.exit("build the app first: swift build --package-path apps/OfficeApp")
    out = os.path.join(os.path.dirname(a.dir), "out")
    os.makedirs(out, exist_ok=True)
    # Excel leaves `~$name.xlsx` lock files beside workbooks it has open
    # (test/xlsx-excel-render.sh opens the originals): not workbooks.
    names = a.files or sorted(f for f in os.listdir(a.dir) if f.lower().endswith(".xlsx") and not f.startswith("~$"))
    counts = {}
    for name in names:
        src, dst = os.path.join(a.dir, name), os.path.join(out, name)
        code, text, _ = run([APP, "--xlsx-roundtrip", src, dst])
        status = "ok" if code == 0 else ("TIMEOUT" if code == "timeout" else "READ-FAIL")
        if status == "ok":
            code, text, _ = run([APP, "--xlsx-roundtrip", dst, dst + ".again"])
            if code != 0:
                status = "REREAD-FAIL"
            if os.path.exists(dst + ".again"):
                os.remove(dst + ".again")
        counts[status] = counts.get(status, 0) + 1
        if status != "ok":
            print(f"{status:12} {name}  {last(text)}")
    print(counts)


if __name__ == "__main__":
    main()
