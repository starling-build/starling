// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// A freeform (`a:custGeom`) as drawn: its subpaths in the unit square of
/// the shape's frame, every guide formula already evaluated for the size
/// the shape was read at. The element itself is still kept verbatim for
/// the file; this is only what the deck paints.
struct FreeformGeometry: Equatable {
    enum Command: Equatable {
        case move(Double, Double)
        case line(Double, Double)
        case quad(Double, Double, Double, Double)
        case cubic(Double, Double, Double, Double, Double, Double)
        /// An elliptical arc from the current point: the ellipse's bounds
        /// (unit square) and its start and sweep angles in radians.
        case arc(Rect, Double, Double)
        case close
    }

    struct Subpath: Equatable {
        var fill: Bool
        var stroke: Bool
        var commands: [Command]
    }

    var subpaths: [Subpath]

    /// The subpath as a `Path` in `r`.
    static func path(_ s: Subpath, in r: Rect) -> Path {
        let path = Path()
        // Overlapping contours of one path cut holes, as PowerPoint draws them.
        path.fillType = .evenOdd
        func x(_ u: Double) -> Double { r.left + u * r.width }
        func y(_ v: Double) -> Double { r.top + v * r.height }
        for c in s.commands {
            switch c {
            case .move(let u, let v): path.moveTo(x(u), y(v))
            case .line(let u, let v): path.lineTo(x(u), y(v))
            case .quad(let u1, let v1, let u, let v): path.quadraticBezierTo(x(u1), y(v1), x(u), y(v))
            case .cubic(let u1, let v1, let u2, let v2, let u, let v):
                path.cubicTo(x(u1), y(v1), x(u2), y(v2), x(u), y(v))
            case .arc(let b, let start, let sweep):
                path.arcTo(Rect.fromLTWH(x(b.left), y(b.top), b.width * r.width, b.height * r.height), start, sweep, false)
            case .close: path.close()
            }
        }
        return path
    }

    // MARK: Reading

    /// `custGeom` evaluated for a shape `w` by `h` EMU. Nil when a guide
    /// cannot be evaluated (the shape is then shown as a box).
    static func parse(_ geom: XNode, width w: Double, height h: Double) -> FreeformGeometry? {
        var guides = Guides(width: w, height: h)
        for list in ["a:avLst", "a:gdLst"] {
            for gd in geom.first(list)?.all("a:gd") ?? [] {
                guard let name = gd["name"], let fmla = gd["fmla"], let v = guides.evaluate(fmla) else { return nil }
                guides.values[name] = v
            }
        }
        var subpaths: [Subpath] = []
        for p in geom.first("a:pathLst")?.all("a:path") ?? [] {
            // The path's own coordinate space, or the shape's when absent.
            let pw = p["w"].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? w
            let ph = p["h"].flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil } ?? h
            guard pw > 0, ph > 0 else { continue }
            var cmds: [Command] = []
            var cur = (0.0, 0.0)
            func pt(_ n: XNode) -> (Double, Double)? {
                guard let xs = n["x"], let ys = n["y"], let x = guides.value(xs), let y = guides.value(ys) else { return nil }
                return (x / pw, y / ph)
            }
            for c in p.children {
                switch c.name {
                case "a:moveTo":
                    guard let q = c.first("a:pt").flatMap(pt) else { return nil }
                    cmds.append(.move(q.0, q.1)); cur = q
                case "a:lnTo":
                    guard let q = c.first("a:pt").flatMap(pt) else { return nil }
                    cmds.append(.line(q.0, q.1)); cur = q
                case "a:quadBezTo":
                    let pts = c.all("a:pt").compactMap(pt)
                    guard pts.count == 2 else { return nil }
                    cmds.append(.quad(pts[0].0, pts[0].1, pts[1].0, pts[1].1)); cur = pts[1]
                case "a:cubicBezTo":
                    let pts = c.all("a:pt").compactMap(pt)
                    guard pts.count == 3 else { return nil }
                    cmds.append(.cubic(pts[0].0, pts[0].1, pts[1].0, pts[1].1, pts[2].0, pts[2].1)); cur = pts[2]
                case "a:arcTo":
                    guard let wr = c["wR"].flatMap(guides.value), let hr = c["hR"].flatMap(guides.value),
                          let st = c["stAng"].flatMap(guides.value), let sw = c["swAng"].flatMap(guides.value) else { return nil }
                    let rx = wr / pw, ry = hr / ph
                    let start = st / 60000 * .pi / 180, sweep = sw / 60000 * .pi / 180
                    // The ellipse's centre: the current point lies on it at
                    // the start angle.
                    let cx = cur.0 - rx * cos(start), cy = cur.1 - ry * sin(start)
                    cmds.append(.arc(Rect.fromLTWH(cx - rx, cy - ry, 2 * rx, 2 * ry), start, sweep))
                    cur = (cx + rx * cos(start + sweep), cy + ry * sin(start + sweep))
                case "a:close":
                    cmds.append(.close)
                default: continue
                }
            }
            guard !cmds.isEmpty else { continue }
            subpaths.append(Subpath(fill: p["fill"] != "none", stroke: p["stroke"] != "0", commands: cmds))
        }
        return subpaths.isEmpty ? nil : FreeformGeometry(subpaths: subpaths)
    }

    /// DrawingML's guide language: the built-in names for a shape of this
    /// size, the guides defined so far, and the formulas over them.
    struct Guides {
        var values: [String: Double]

        init(width w: Double, height h: Double) {
            let ss = min(w, h)
            values = [
                "w": w, "h": h, "ss": ss, "ls": max(w, h), "l": 0, "t": 0, "r": w, "b": h,
                "hc": w / 2, "vc": h / 2, "wd2": w / 2, "hd2": h / 2, "wd3": w / 3, "hd3": h / 3,
                "wd4": w / 4, "hd4": h / 4, "wd5": w / 5, "hd5": h / 5, "wd6": w / 6, "hd6": h / 6,
                "wd8": w / 8, "hd8": h / 8, "wd10": w / 10, "hd10": h / 10, "wd12": w / 12, "hd12": h / 12,
                "wd32": w / 32, "hd32": h / 32,
                "ssd2": ss / 2, "ssd4": ss / 4, "ssd6": ss / 6, "ssd8": ss / 8, "ssd16": ss / 16, "ssd32": ss / 32,
                "cd2": 10_800_000, "cd4": 5_400_000, "cd8": 2_700_000,
                "3cd4": 16_200_000, "3cd8": 8_100_000, "5cd8": 13_500_000, "7cd8": 18_900_000,
            ]
        }

        /// A number, or a guide's value.
        func value(_ s: String) -> Double? {
            if let d = Double(s) { return d }
            return values[s]
        }

        /// A formula: an operator and up to three arguments. Angles are in
        /// 60000ths of a degree.
        func evaluate(_ fmla: String) -> Double? {
            let parts = fmla.split(separator: " ").map(String.init)
            guard let op = parts.first else { return nil }
            let args = parts.dropFirst().compactMap(value)
            guard args.count == parts.count - 1 else { return nil }
            func a(_ i: Int) -> Double { args.indices.contains(i) ? args[i] : 0 }
            func deg(_ v: Double) -> Double { v / 60000 * .pi / 180 }
            switch op {
            case "val": return a(0)
            case "*/": return a(2) == 0 ? 0 : a(0) * a(1) / a(2)
            case "+-": return a(0) + a(1) - a(2)
            case "+/": return a(2) == 0 ? 0 : (a(0) + a(1)) / a(2)
            case "?:": return a(0) > 0 ? a(1) : a(2)
            case "abs": return abs(a(0))
            case "at2": return atan2(a(1), a(0)) * 180 / .pi * 60000
            case "cat2": return a(0) * cos(atan2(a(2), a(1)))
            case "sat2": return a(0) * sin(atan2(a(2), a(1)))
            case "cos": return a(0) * cos(deg(a(1)))
            case "sin": return a(0) * sin(deg(a(1)))
            case "tan": return a(0) * tan(deg(a(1)))
            case "max": return max(a(0), a(1))
            case "min": return min(a(0), a(1))
            case "mod": return (a(0) * a(0) + a(1) * a(1) + a(2) * a(2)).squareRoot()
            case "pin": return min(max(a(1), a(0)), a(2))
            case "sqrt": return a(0) < 0 ? 0 : a(0).squareRoot()
            default: return nil
            }
        }
    }
}
