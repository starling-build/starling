#!/usr/bin/env python3
"""The 500 MB `time cat` corpora for the Windows long round.

Same content pools and wrap as ../terminal-windows-published-2026-08-12/
gen-150mb-win.py -- only the size changes, from 150 MB to the long round's
500 MB, matching the macOS long round's bigcat500. Lines wrap at 119 for the
120-column Windows grid so the terminal never autowraps.

Run it ON the VM (1 GB of output; do not push it over scp):

    python gen-bigcat-win.py C:\\bench
"""
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else r"C:\bench"
TARGET = int(sys.argv[2]) if len(sys.argv) > 2 else 500 * 1000 * 1000
COLS = 119
os.makedirs(OUT, exist_ok=True)


def write(name, line_iter):
    p = os.path.join(OUT, name)
    n = 0
    with open(p, "wb") as f:
        while n < TARGET:
            chunk = "".join(next(line_iter) for _ in range(2000)).encode()
            f.write(chunk)
            n += len(chunk)
    print("%-22s %7.1f MB" % (name, os.path.getsize(p) / 1e6))


def ascii_lines():
    i = 0
    while True:
        i += 1
        yield "".join(chr(0x41 + ((i + j) % 26)) for j in range(COLS)) + "\n"


POOL = ("hello world Privet mir abgde \u65e5\u672c\u8a9e\u30c6\u30ad\u30b9\u30c8 "
        "\u4e2d\u6587\u5b57\u7b26 \ud55c\uad6d\uc5b4 "
        "\u2713\u2717\u2192\u2264\u221e \U0001f389\U0001f680\U0001f525 ")


def unicode_lines():
    base = POOL * ((COLS // len(POOL)) + 2)
    i = 0
    while True:
        i += 1
        yield base[i % 37:][:COLS] + "\n"


write("big500-ascii.bin", ascii_lines())
write("big500-unicode.bin", unicode_lines())
