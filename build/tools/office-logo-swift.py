#!/usr/bin/env python3
"""build/tools/office-logo-swift.py — the Office icons as Swift, for the app to draw.

    python build/tools/office-logo-swift.py        # rewrites OfficeLogoArt.swift

The badge in the app's title row is the suite's icon, and the icons are the
three SVGs in build/office-gtk. The framework has no SVG reader, the app ships
no pictures, and the web build has no resource bundle at all — so the app
draws the icon itself (OfficeLogo.swift), from numbers this script takes out
of the SVGs. Run it again when an icon changes; the output is checked in.

It reads exactly what those files use and stops on anything else: one
gradient, the tile and its rim, a flock of one bird path placed by
translate/rotate/scale, and one stroked glyph.
"""
import os, re, sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "apps", "OfficeApp", "Sources", "OfficeApp", "OfficeLogoArt.swift")
ICONS = [("document", "starling-writer.svg"), ("workbook", "starling-sheets.svg"),
         ("presentation", "starling-slides.svg")]
NS = "{http://www.w3.org/2000/svg}"
NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")


def path(d):
    """SVG path data as absolute (command, numbers) pairs: M, L, C and Z only."""
    out, pos, start = [], (0.0, 0.0), (0.0, 0.0)
    for cmd, args in re.findall(r"([MmLlHhVvCcZz])([^MmLlHhVvCcZz]*)", d):
        n = [float(x) for x in NUM.findall(args)]
        rel = cmd.islower()
        c = cmd.upper()
        if c == "Z":
            out.append(("Z", []))
            pos = start
            continue
        step = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6}[c]
        if not n or len(n) % step:
            sys.exit("office-logo-swift: cannot read path piece %r" % (cmd + args))
        for i in range(0, len(n), step):
            a = n[i:i + step]
            if c == "H":
                p = (pos[0] + a[0] if rel else a[0], pos[1])
                out.append(("L", list(p)))
            elif c == "V":
                p = (pos[0], pos[1] + a[0] if rel else a[0])
                out.append(("L", list(p)))
            elif c == "C":
                pts = [(a[j] + (pos[0] if rel else 0), a[j + 1] + (pos[1] if rel else 0)) for j in (0, 2, 4)]
                out.append(("C", [v for q in pts for v in q]))
                p = pts[2]
            else:
                p = (a[0] + (pos[0] if rel else 0), a[1] + (pos[1] if rel else 0))
                # After the first pair an M goes on as L.
                first = c == "M" and i == 0
                out.append(("M" if first else "L", list(p)))
                if first:
                    start = p
            pos = p
    return out


def color(text, opacity=1.0):
    h = text.lstrip("#")
    if len(h) != 6:
        sys.exit("office-logo-swift: colour %r" % text)
    return "0x%02X%s" % (round(opacity * 255), h.upper())


def swift_path(cmds):
    return "[" + ", ".join("(%s, [%s])" % ('"%s"' % c, ", ".join("%g" % v for v in a)) for c, a in cmds) + "]"


def read(name):
    root = ET.parse(os.path.join(ROOT, "build", "office-gtk", name)).getroot()
    grad = root.find(NS + "defs").find(NS + "linearGradient")
    stops = grad.findall(NS + "stop")
    if grad.get("gradientUnits") != "userSpaceOnUse" or len(stops) != 2:
        sys.exit("office-logo-swift: %s: not the gradient this expects" % name)
    rects = root.findall(NS + "rect")
    tile, rim = rects[0], rects[1]
    paths = root.findall(NS + "path")
    birds, glyph, shape = [], None, None
    for p in paths:
        t = p.get("transform")
        if t is None:
            if glyph is not None:
                sys.exit("office-logo-swift: %s: more than one glyph" % name)
            glyph = p
            continue
        m = re.fullmatch(r"translate\(([-\d.]+) ([-\d.]+)\) rotate\(([-\d.]+)\) scale\(([-\d.]+)\)", t)
        if not m:
            sys.exit("office-logo-swift: %s: transform %r" % (name, t))
        if shape is None:
            shape = p.get("d")
        elif shape != p.get("d"):
            sys.exit("office-logo-swift: %s: the birds are not one shape" % name)
        birds.append((float(m[1]), float(m[2]), float(m[3]), float(m[4]), color(p.get("fill"))))
    if glyph is None or not birds:
        sys.exit("office-logo-swift: %s: no glyph or no birds" % name)
    return {
        "gradient": [float(grad.get(k)) for k in ("x1", "y1", "x2", "y2")],
        "top": color(stops[0].get("stop-color")), "bottom": color(stops[1].get("stop-color")),
        "tile": [float(tile.get(k)) for k in ("x", "y", "width", "height", "rx")],
        "rim": [float(rim.get(k)) for k in ("x", "y", "width", "height", "rx")],
        "rimColor": color(rim.get("stroke"), float(rim.get("stroke-opacity", "1"))),
        "rimWidth": float(rim.get("stroke-width")),
        "bird": shape, "birds": birds,
        "glyph": path(glyph.get("d")), "glyphColor": color(glyph.get("stroke")),
        "glyphWidth": float(glyph.get("stroke-width")),
        "roundCap": glyph.get("stroke-linecap") == "round",
        "roundJoin": glyph.get("stroke-linejoin") == "round",
    }


def main():
    arts = [(kind, name, read(name)) for kind, name in ICONS]
    shapes = {a["bird"] for _, _, a in arts}
    geometry = {(tuple(a["gradient"]), tuple(a["tile"]), tuple(a["rim"]), a["rimColor"], a["rimWidth"]) for _, _, a in arts}
    if len(shapes) != 1 or len(geometry) != 1:
        sys.exit("office-logo-swift: the three icons no longer share their bird, tile or rim")
    one = arts[0][2]
    w = []
    w.append("// Copyright the Starling authors")
    w.append("// SPDX-License-Identifier: Apache-2.0")
    w.append("")
    w.append("// GENERATED by build/tools/office-logo-swift.py from build/office-gtk/starling-*.svg.")
    w.append("// Do not edit: change the SVG and run the script. OfficeLogo.swift draws this.")
    w.append("")
    w.append("struct OfficeLogoArt {")
    w.append("    /// One starling: where it flies (in the icon's 256 box), its turn in")
    w.append("    /// degrees, its size, its colour.")
    w.append("    typealias Bird = (x: Double, y: Double, turn: Double, scale: Double, color: Int64)")
    w.append("    /// A path as absolute pieces: M and L take a point, C three, Z none.")
    w.append("    typealias Piece = (String, [Double])")
    w.append("")
    w.append("    let top: Int64")
    w.append("    let bottom: Int64")
    w.append("    let birds: [Bird]")
    w.append("    let glyph: [Piece]")
    w.append("    let glyphColor: Int64")
    w.append("    let glyphWidth: Double")
    w.append("    let roundCap: Bool")
    w.append("    let roundJoin: Bool")
    w.append("")
    w.append("    // What the three share.")
    w.append("    static let box = 256.0")
    w.append("    static let gradient: [Double] = [%s]" % ", ".join("%g" % v for v in one["gradient"]))
    w.append("    static let tile: [Double] = [%s]   // x, y, width, height, corner" % ", ".join("%g" % v for v in one["tile"]))
    w.append("    static let rim: [Double] = [%s]" % ", ".join("%g" % v for v in one["rim"]))
    w.append("    static let rimColor: Int64 = %s" % one["rimColor"])
    w.append("    static let rimWidth: Double = %g" % one["rimWidth"])
    w.append("    static let bird: [Piece] = %s" % swift_path(path(one["bird"])))
    for kind, name, a in arts:
        w.append("")
        w.append("    /// %s" % name)
        w.append("    static let %s = OfficeLogoArt(" % kind)
        w.append("        top: %s, bottom: %s," % (a["top"], a["bottom"]))
        w.append("        birds: [")
        for b in a["birds"]:
            w.append("            (%g, %g, %g, %g, %s)," % b)
        w.append("        ],")
        w.append("        glyph: %s," % swift_path(a["glyph"]))
        w.append("        glyphColor: %s, glyphWidth: %g, roundCap: %s, roundJoin: %s)" % (
            a["glyphColor"], a["glyphWidth"], str(a["roundCap"]).lower(), str(a["roundJoin"]).lower()))
    w.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(w) + "\n")
    print("==>", OUT, "(%s)" % ", ".join("%s: %d birds" % (k, len(a["birds"])) for k, _, a in arts))


if __name__ == "__main__":
    main()
