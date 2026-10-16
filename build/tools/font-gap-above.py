#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""build/tools/font-gap-above.py IN.ttf OUT.ttf — the face with its line gap
moved over its ascent (hhea: the ascender takes the gap, which is then 0).

The browser build's copy of what OfficeFonts._gapAbove does to Liberation
Sans and Serif in memory natively: Word sets a face's whole line gap over
its text, the engine half over and half under, and a line where Times
stands beside a face with no gap came out deeper than Word's.
"""
import struct
import sys

data = bytearray(open(sys.argv[1], "rb").read())
tables = struct.unpack(">H", data[4:6])[0]
for k in range(tables):
    entry = 12 + 16 * k
    if data[entry:entry + 4] == b"hhea":
        at = struct.unpack(">I", data[entry + 8:entry + 12])[0]
        ascender, descender, gap = struct.unpack(">hhh", data[at + 4:at + 10])
        if gap > 0:
            data[at + 4:at + 10] = struct.pack(">hhh", ascender + gap, descender, 0)
        break
else:
    sys.exit(f"{sys.argv[1]}: no hhea table")
open(sys.argv[2], "wb").write(data)
