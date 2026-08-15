#!/usr/bin/env python3
"""icns-to-hicolor.py <icon.icns> <hicolor-root> <icon-name>

Extracts the PNG entries of an .icns into a freedesktop hicolor tree:
<hicolor-root>/<WxW>/apps/<icon-name>.png. The .icns is the single icon
source (generated on macOS by build/macos/gen-icon.swift); Linux packaging
feeds off the same pixels rather than keeping a second set to drift.

Modern .icns entries ARE PNG files; the legacy ARGB entries (ic04/ic05)
and metadata are skipped. Retina duplicates carry the same pixel size and
collapse into one file. Pure stdlib — this runs on package build boxes.
"""
import struct
import sys
from pathlib import Path

def main():
    icns_path, out_root, name = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    data = Path(icns_path).read_bytes()
    if data[:4] != b"icns":
        sys.exit(f"{icns_path}: not an icns file")
    written = {}
    off = 8
    while off < len(data):
        length = struct.unpack(">I", data[off + 4:off + 8])[0]
        payload = data[off + 8:off + length]
        off += length
        if payload[:8] != b"\x89PNG\r\n\x1a\n":
            continue
        w, h = struct.unpack(">II", payload[16:24])
        if w != h or w in written:
            continue
        dest = out_root / f"{w}x{w}" / "apps" / f"{name}.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(payload)
        written[w] = dest
    if not written:
        sys.exit(f"{icns_path}: no PNG entries found")
    print(f"icons: {sorted(written)} -> {out_root}")

if __name__ == "__main__":
    main()
