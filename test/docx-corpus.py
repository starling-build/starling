#!/usr/bin/env python3
"""Round-trip Apache POI's .docx test corpus through Writer, headless.

    test/docx-corpus.py [--dir DIR] [FILE.docx ...]

Fetches POI's test-data/document/*.docx (real Word documents from bug
reports, plus fuzzer cases) into ~/.cache/starling/docx-corpus/in — never
into the repo — then for each: read and save (`OfficeApp --convert in out`),
read the copy again (`--convert out out2`), and test/ooxml-check.py on the
copy. Verdicts per file: ok, READ-FAIL (the original does not open),
WRITE-FAIL (the copy does not read back, or reads back with a different
paragraph count), CHECK-FAIL (the copy's package is unsound). The copies
stay in ~/.cache/starling/docx-corpus/out for test/docx-word.sh, which is
the oracle this gate cannot be: a copy can pass here and still make Word
ask to recover it.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "apps/OfficeApp/.build/debug/OfficeApp")
CHECK = os.path.join(ROOT, "test/ooxml-check.py")
LIST = "https://api.github.com/repos/apache/poi/contents/test-data/document"


def fetch(dest):
    os.makedirs(dest, exist_ok=True)
    try:
        with urllib.request.urlopen(LIST, timeout=60) as r:
            entries = [e for e in json.load(r) if e["name"].lower().endswith(".docx")]
    except (urllib.error.URLError, OSError) as e:
        cached = [f for f in os.listdir(dest) if f.lower().endswith(".docx")]
        if not cached:
            raise
        print(f"corpus: listing unavailable ({e}); using the {len(cached)} cached documents")
        return len(cached)
    for e in entries:
        path = os.path.join(dest, e["name"])
        if os.path.exists(path) and os.path.getsize(path) == e["size"]:
            continue
        with urllib.request.urlopen(e["download_url"], timeout=120) as r, open(path, "wb") as f:
            f.write(r.read())
    return len(entries)


def run(args, timeout=90):
    t = time.time()
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr, time.time() - t
    except subprocess.TimeoutExpired:
        return "timeout", "", time.time() - t


def last(text):
    lines = text.strip().splitlines()
    return lines[-1][:160] if lines else ""


def counts(text):
    m = re.search(r"(\d+) paragraphs, (\d+) words", text)
    return (int(m.group(1)), int(m.group(2))) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.expanduser("~/.cache/starling/docx-corpus/in"))
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    if not os.path.exists(APP):
        sys.exit("build the app first: swift build --package-path apps/OfficeApp")
    if not a.files:
        print("corpus:", fetch(a.dir), "documents in", a.dir)
    out = os.path.join(os.path.dirname(a.dir), "out")
    again = os.path.join(os.path.dirname(a.dir), "again")
    os.makedirs(out, exist_ok=True)
    os.makedirs(again, exist_ok=True)
    names = a.files or sorted(f for f in os.listdir(a.dir) if f.lower().endswith(".docx"))
    tally = {}
    for name in names:
        src = name if a.files else os.path.join(a.dir, name)
        base = os.path.basename(src)
        dst = os.path.join(out, base)
        dst2 = os.path.join(again, base)
        for p in (dst, dst2):
            if os.path.exists(p):
                os.remove(p)
        code, text, secs = run([APP, "--convert", src, dst])
        if code != 0:
            verdict, detail = "READ-FAIL", last(text)
        else:
            first = counts(text)
            code2, text2, _ = run([APP, "--convert", dst, dst2])
            second = counts(text2)
            if code2 != 0:
                verdict, detail = "WRITE-FAIL", "copy does not read back: " + last(text2)
            elif first and second and first[0] != second[0]:
                verdict, detail = "WRITE-FAIL", f"{first[0]} paragraphs saved, {second[0]} read back"
            else:
                c, ctext, _ = run([sys.executable, CHECK, dst])
                if c != 0:
                    verdict, detail = "CHECK-FAIL", last(ctext)
                else:
                    verdict, detail = "ok", f"{first[0]} paragraphs, {first[1]} words" if first else ""
        tally[verdict] = tally.get(verdict, 0) + 1
        flag = "" if verdict == "ok" else verdict
        print(f"{flag:11} {base:50} {detail}" if flag else f"{'':11} {base:50} {detail}")
    print(tally)


if __name__ == "__main__":
    main()
