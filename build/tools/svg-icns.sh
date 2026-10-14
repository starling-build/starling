#!/usr/bin/env bash
# build/tools/svg-icns.sh IN.svg OUT.icns — a macOS app icon from an SVG.
#
# build/macos-app.sh picks up build/macos/<Name>.icns; this makes one. AppKit
# draws the SVG at each of the ten sizes an .icns carries, on a clear ground
# (Quick Look's thumbnailer would do it too, on a white one), and iconutil
# packs them. macOS only.
#
#   build/tools/svg-icns.sh build/office-gtk/starling-writer.svg build/macos/Office.icns
#   build/tools/svg-icns.sh --png 180 IN.svg OUT.png     # one PNG, that many pixels square
set -euo pipefail
PNG=""
if [ "${1:-}" = --png ]; then PNG="$2"; shift 2; fi
[ $# -eq 2 ] || { sed -n '2,11p' "$0"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/draw.swift" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
guard let image = NSImage(contentsOf: URL(fileURLWithPath: a[1])) else { fatalError("cannot read \(a[1])") }
let n = Int(a[3])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: n, height: n)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: n, height: n), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
SWIFT
swiftc -O -o "$TMP/draw" "$TMP/draw.swift" 2>/dev/null
if [ -n "$PNG" ]; then "$TMP/draw" "$1" "$2" "$PNG"; exit 0; fi
SET="$TMP/icon.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
    "$TMP/draw" "$1" "$SET/icon_${s}x${s}.png" "$s"
    "$TMP/draw" "$1" "$SET/icon_${s}x${s}@2x.png" "$((s * 2))"
done
iconutil -c icns -o "$2" "$SET"
echo "==> $2"
