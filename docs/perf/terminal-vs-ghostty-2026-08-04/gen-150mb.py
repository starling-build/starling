#!/usr/bin/env python3
"""Generate the two files Ghostty's maintainer benchmarked with `time cat`.

Their post reports `time cat 150MB_ascii.txt` and `time cat 150MB_unicode.txt`
(mixed languages). The exact corpora are not published, so these are
reconstructions of the same shape and size — absolute seconds are therefore
NOT comparable to their machine's numbers, only the ratios between terminals
measured here.

Lines are wrapped at 200 columns so a 201-column terminal never autowraps,
matching the rest of test/bench.
"""
import os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "/var/tmp/bench"
TARGET = 150 * 1000 * 1000
COLS = 200
os.makedirs(OUT, exist_ok=True)

def write(name, line_iter):
    p = os.path.join(OUT, name)
    n = 0
    with open(p, "wb") as f:
        while n < TARGET:
            chunk = "".join(next(line_iter) for _ in range(2000)).encode()
            f.write(chunk)
            n += len(chunk)
    print(f"{name:22s} {os.path.getsize(p)/1e6:7.1f} MB")

def ascii_lines():
    i = 0
    while True:
        i += 1
        yield "".join(chr(0x41 + ((i + j) % 26)) for j in range(COLS)) + "\n"

# Mixed languages, as their "unicode" file is described: Latin-with-accents,
# Cyrillic, Greek, CJK, Hangul, Arabic, plus emoji — 2, 3 and 4 byte sequences.
POOL = ("héllo wörld Привет мир αβγδε 日本語テキスト 中文字符 한국어 "
        "مرحبا بالعالم ✓✗→≤∞ 🎉🚀🔥 ")
def unicode_lines():
    base = (POOL * ((COLS // len(POOL)) + 2))
    i = 0
    while True:
        i += 1
        yield base[i % 37:][:COLS] + "\n"

write("ascii_150mb.txt", ascii_lines())
write("unicode_150mb.txt", unicode_lines())
