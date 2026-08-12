#!/usr/bin/env python3
"""Ghostty's two published `time cat` corpora, generated for the Windows grid.

A straight port of docs/perf/terminal-vs-ghostty-2026-08-04/gen-150mb.py. The
only change is COLS: that script wraps at 200 for a 201-column Linux terminal,
and the Windows bench runs at 120x40, so lines wrap at 119 to keep the
terminal from autowrapping. Same shape, same size, same content pools.

Absolute seconds are not comparable to the Linux numbers (different corpus
wrap, and ConPTY re-synthesis dominates everything on Windows) — only the
ratio between the terminals measured side by side here.
"""
import os, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else r"C:\bench150"
TARGET = 150 * 1000 * 1000
COLS = int(sys.argv[2]) if len(sys.argv) > 2 else 119
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
