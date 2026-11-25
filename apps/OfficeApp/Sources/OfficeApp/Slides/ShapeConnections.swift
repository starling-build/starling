// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import FlutterSwiftBridge

/// S-SH-3: connectors glued to shapes. A line's start or end can be glued to a connection site of a shape (the middle of a
/// side, or a point on an ellipse); the end then follows the shape when it moves, turns or is resized.
extension SlideShape {
    /// The number of connection sites a shape has: four for a rectangle, rounded rectangle and diamond (top, left, bottom,
    /// right, as PowerPoint numbers them), eight for an ellipse (round from the top, anticlockwise). Zero: none modelled.
    var connectionSiteCount: Int {
        switch preset?.rawValue {
        case "rect", "roundRect", "diamond": return 4
        case "ellipse": return 8
        default: return 0
        }
    }

    /// Site `i` on the slide, with the shape's mirroring and rotation applied.
    func connectionSite(_ i: Int) -> Offset? {
        guard i >= 0, i < connectionSiteCount else { return nil }
        let hw = frame.width / 2, hh = frame.height / 2
        let d = 0.70710678
        var x = 0.0, y = 0.0
        if connectionSiteCount == 4 {
            switch i { case 0: y = -hh; case 1: x = -hw; case 2: y = hh; default: x = hw }
        } else {
            let pts: [(Double, Double)] = [(0, -1), (-d, -d), (-1, 0), (-d, d), (0, 1), (d, d), (1, 0), (d, -d)]
            x = pts[i].0 * hw; y = pts[i].1 * hh
        }
        if flipH { x = -x }
        if flipV { y = -y }
        let a = rotation * .pi / 180
        let c = frame.center
        return Offset(c.dx + x * cos(a) - y * sin(a), c.dy + x * sin(a) + y * cos(a))
    }

    /// A line that may be glued: a straight one, not mirrored or turned (its start is its frame's top left and its end the
    /// bottom right), or an elbow or curve, which may be either way up (its ends are found through its mirroring and turn).
    var isGluableLine: Bool { isElbow || (preset?.isLine == true && !flipH && !flipV && rotation == 0) }

    var isElbow: Bool { preset?.isElbow == true }

    /// An elbow's start (`start`) or end on the slide: the corner of its box that its path starts and ends at, mirrored and
    /// turned about the box's centre.
    func elbowPoint(start: Bool) -> Offset {
        var x = start ? -frame.width / 2 : frame.width / 2
        var y = start ? -frame.height / 2 : frame.height / 2
        if flipH { x = -x }
        if flipV { y = -y }
        let a = rotation * .pi / 180
        let c = frame.center
        return Offset(c.dx + x * cos(a) - y * sin(a), c.dy + x * sin(a) + y * cos(a))
    }

    /// The yellow handles of an elbow's middle runs: the adjust value each sets, whether it moves along the box's width, and
    /// where it sits on the slide (the middle of the run it moves).
    var elbowAdjustHandles: [(key: String, alongWidth: Bool, at: Offset)] {
        guard isElbow, let name = preset?.rawValue else { return [] }
        let w = frame.width, h = frame.height
        func v(_ k: String, _ d: Double) -> Double { (adjusts[k] ?? d) / 100000 }
        var out: [(String, Bool, Double, Double)] = []
        if name.hasSuffix("Connector3") {
            out = [("adj1", true, w * v("adj1", 50000), h / 2)]
        } else if name.hasSuffix("Connector4") {
            let x1 = w * v("adj1", 50000), y2 = h * v("adj2", 50000)
            out = [("adj1", true, x1, y2 / 2), ("adj2", false, (x1 + w) / 2, y2)]
        } else if name.hasSuffix("Connector5") {
            let x1 = w * v("adj1", 50000), y2 = h * v("adj2", 50000), x3 = w * v("adj3", 50000)
            out = [("adj1", true, x1, y2 / 2), ("adj2", false, (x1 + x3) / 2, y2), ("adj3", true, x3, (y2 + h) / 2)]
        }
        return out.map { ($0.0, $0.1, toSlide(localX: $0.2, localY: $0.3)) }
    }

    /// A point of the connector's own box (origin at its top left, before mirroring and turning) on the slide.
    func toSlide(localX: Double, localY: Double) -> Offset {
        var x = localX - frame.width / 2, y = localY - frame.height / 2
        if flipH { x = -x }
        if flipV { y = -y }
        let a = rotation * .pi / 180
        let c = frame.center
        return Offset(c.dx + x * cos(a) - y * sin(a), c.dy + x * sin(a) + y * cos(a))
    }

    /// Drags the middle run `key` to the slide point `p`: the adjust value follows, the path is drawn again.
    func setElbowAdjust(_ key: String, alongWidth: Bool, to p: Offset) {
        let c = frame.center
        let dx = p.dx - c.dx, dy = p.dy - c.dy
        let a = -rotation * .pi / 180
        var x = dx * cos(a) - dy * sin(a), y = dx * sin(a) + dy * cos(a)
        if flipH { x = -x }
        if flipV { y = -y }
        let value = alongWidth ? (x + frame.width / 2) / max(frame.width, 1) : (y + frame.height / 2) / max(frame.height, 1)
        adjusts[key] = (value * 100000).rounded()
        if let name = preset?.rawValue {
            customPath = PresetGeometry.geometry(name, width: frame.width * Pptx.emu, height: frame.height * Pptx.emu, adjustments: adjusts)
        }
    }

    var lineStart: Offset { isElbow ? elbowPoint(start: true) : Offset(frame.left, frame.top) }
    var lineEndPoint: Offset { isElbow ? elbowPoint(start: false) : Offset(frame.right, frame.bottom) }

    func moveLineEnd(start: Bool, to p: Offset) {
        if isElbow {
            let r = ElbowRoute.make(from: start ? p : lineStart, to: start ? lineEndPoint : p, leaving: nil, arriving: nil,
                                    curved: preset?.rawValue.hasPrefix("curved") == true)
            apply(r)
            return
        }
        frame = start ? Rect.fromLTRB(p.dx, p.dy, frame.right, frame.bottom)
                      : Rect.fromLTRB(frame.left, frame.top, p.dx, p.dy)
    }

    /// Takes a route: the elbow variant, its box, turn, mirroring and adjust values, and the path drawn from them.
    func apply(_ r: ElbowRoute) {
        var adj = r.adjusts
        // The same variant bent the same way keeps the adjust values it has (a moved shape does not undo a hand-set elbow).
        if r.preset == preset?.rawValue, !adjusts.isEmpty {
            func side(_ v: Double) -> Int { v < 0 ? -1 : (v > 100000 ? 1 : 0) }
            for (k, v) in adjusts where adj[k] != nil && side(v) == side(adj[k]!) { adj[k] = v }
        }
        kind = .geometry(ShapePreset(rawValue: r.preset))
        frame = r.frame
        rotation = r.rotation
        flipH = false
        flipV = r.flipV
        adjusts = adj
        customPath = PresetGeometry.geometry(r.preset, width: r.frame.width * Pptx.emu, height: r.frame.height * Pptx.emu,
                                             adjustments: adj)
    }

    /// Which way site `i` faces, on the slide, as a unit step along an axis: up, left, down or right.
    func connectionSiteDirection(_ i: Int) -> (Double, Double)? {
        guard let p = connectionSite(i) else { return nil }
        let c = frame.center
        var dx = p.dx - c.dx, dy = p.dy - c.dy
        if connectionSiteCount == 4 {
            // The sides' middles: the offset is already along an axis (turned by the shape's rotation, which may be slanted).
            dx = abs(dx) < 1e-9 ? 0 : dx; dy = abs(dy) < 1e-9 ? 0 : dy
        }
        // A slanted site facing: take the nearer axis.
        return abs(dx) >= abs(dy) - 1e-9 ? (dx >= 0 ? 1 : -1, 0) : (0, dy >= 0 ? 1 : -1)
    }
}

/// The elbow or curved connector PowerPoint would draw between two points: `bentConnector2`-`5` (or `curvedConnector2`-`5`)
/// in a box between the points, turned by a multiple of 90 degrees and mirrored so that its path leaves the start in the
/// wanted direction and arrives at the end travelling the wanted way, with adjust values for the middle run.
struct ElbowRoute {
    var preset: String
    var frame: Rect
    var rotation: Double
    var flipV: Bool
    var adjusts: [String: Double]

    /// How far a path stands off a shape when it has to go round it.
    static let stub = 18.0

    /// `leaving`: the way the path heads off the start (an axis step); `arriving`: the way it travels into the end. Nil for
    /// a free end: the path then bends the simplest way, S-shaped when the end is ahead.
    static func make(from s: Offset, to e: Offset, leaving: (Double, Double)?, arriving: (Double, Double)?, curved: Bool) -> ElbowRoute {
        let d = Offset(e.dx - s.dx, e.dy - s.dy)
        func dot(_ a: (Double, Double), _ b: Offset) -> Double { a.0 * b.dx + a.1 * b.dy }
        var a = leaving ?? (0, 0), b = arriving ?? (0, 0)
        if leaving == nil && arriving == nil {
            a = abs(d.dx) >= abs(d.dy) ? (d.dx >= 0 ? 1 : -1, 0) : (0, d.dy >= 0 ? 1 : -1)
            b = a
        } else if leaving == nil {
            a = b
        } else if arriving == nil {
            b = a
            // A free end behind the start turns the corner rather than doubling back.
            if dot(a, d) < 0 { b = abs(a.0) == 1 ? (0, d.dy >= 0 ? 1 : -1) : (d.dx >= 0 ? 1 : -1, 0) }
        }
        let ex = dot(a, d) >= 0 ? a : (-a.0, -a.1)
        let sigma = a.0 * ex.0 + a.1 * ex.1
        let p = (-ex.1, ex.0)
        let perpendicular = abs(a.0 * b.0 + a.1 * b.1) < 0.5
        let ey: (Double, Double)
        if perpendicular { ey = dot(b, d) >= 0 ? b : (-b.0, -b.1) } else { ey = dot(p, d) >= 0 ? p : (-p.0, -p.1) }
        let flipV = ey.0 * p.0 + ey.1 * p.1 < 0
        let rotation: Double = ex.0 > 0.5 ? 0 : (ex.1 > 0.5 ? 90 : (ex.0 < -0.5 ? 180 : 270))
        let w = max(dot(ex, d), 1), h = max(dot(ey, d), 1)
        let stubW = stub / w * 100000, stubH = stub / h * 100000
        var name = "Connector3"
        var adj: [String: Double] = [:]
        if perpendicular {
            let rho = b.0 * ey.0 + b.1 * ey.1
            if sigma > 0 && rho > 0 { name = "Connector2" }
            else {
                name = "Connector4"
                adj["adj1"] = sigma > 0 ? 50000 : -stubW
                adj["adj2"] = rho > 0 ? 50000 : 100000 + stubH
            }
        } else {
            let tau = b.0 * ex.0 + b.1 * ex.1
            if sigma > 0 { if tau < 0 { adj["adj1"] = 100000 + stubW } }
            else if tau > 0 { adj["adj1"] = -stubW }
            else { name = "Connector5"; adj = ["adj1": -stubW, "adj2": 50000, "adj3": 100000 + stubW] }
            if name == "Connector3", adj["adj1"] == nil { adj["adj1"] = 50000 }
        }
        let c = Offset((s.dx + e.dx) / 2, (s.dy + e.dy) / 2)
        return ElbowRoute(preset: (curved ? "curved" : "bent") + name,
                          frame: Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h), rotation: rotation, flipV: flipV, adjusts: adj)
    }
}

extension DeckController {
    /// The nearest connection site within `radius` points of `p` on the current slide, on a shape other than `line`.
    func nearestSite(to p: Offset, excluding line: SlideShape, radius: Double = 10) -> (shape: SlideShape, site: Int, point: Offset)? {
        var best: (shape: SlideShape, site: Int, point: Offset)? = nil
        var bestD = radius
        for s in currentSlide.shapes where s !== line && s.connectionSiteCount > 0 {
            for i in 0..<s.connectionSiteCount {
                guard let q = s.connectionSite(i) else { continue }
                let dist = ((q.dx - p.dx) * (q.dx - p.dx) + (q.dy - p.dy) * (q.dy - p.dy)).squareRoot()
                if dist < bestD { bestD = dist; best = (s, i, q) }
            }
        }
        return best
    }

    /// A drag of a line's end (handle 0 the start, 1 the end): the line takes `frame`, and the end that moved glues to a
    /// connection site within reach when `snap` is on, or comes unglued. No history entry: the drag has its own.
    func dragLineEnd(_ line: SlideShape, handle: Int, frame: Rect, snap: Bool) {
        line.frame = frame
        guard line.isGluableLine else { _changed(keepSession: true); return }
        let start = handle == 0
        let p = start ? line.lineStart : line.lineEndPoint
        var conn: ShapeConn? = nil
        if snap, let hit = nearestSite(to: p, excluding: line) {
            line.moveLineEnd(start: start, to: hit.point)
            conn = ShapeConn(shape: hit.shape.id, site: hit.site)
        }
        if start { line.connStart = conn } else { line.connEnd = conn }
        _changed(keepSession: true)
    }

    /// Glues one end of the selected line to a site of a shape (for a test, and for the keyboard later). One undo step.
    func connect(_ line: SlideShape, start: Bool, to target: SlideShape, site: Int) {
        guard line.isGluableLine, let q = target.connectionSite(site) else { return }
        _checkpoint()
        line.moveLineEnd(start: start, to: q)
        let c = ShapeConn(shape: target.id, site: site)
        if start { line.connStart = c } else { line.connEnd = c }
        _changed()
    }

    /// Lines about to be moved with `moved` come unglued from any shape that is not moving with them.
    func detachLines(moving moved: [SlideShape]) {
        let ids = Set(moved.map(\.id))
        for s in moved where s.preset?.isLine == true || s.isElbow {
            if let c = s.connStart, !ids.contains(c.shape) { s.connStart = nil }
            if let c = s.connEnd, !ids.contains(c.shape) { s.connEnd = nil }
        }
    }

    /// The glued lines Reroute Connectors acts on: the selected ones, or every glued line on the slide when none is selected.
    var reroutableLines: [SlideShape] {
        let glued: (SlideShape) -> Bool = { $0.isGluableLine && ($0.connStart != nil || $0.connEnd != nil) }
        let picked = selection.filter(glued)
        return picked.isEmpty && !selection.contains(where: { $0.preset?.isLine == true }) ? currentSlide.shapes.filter(glued) : picked
    }

    /// PowerPoint's Reroute Connectors: each glued line moves its ends to the pair of connection sites that makes it the
    /// shortest. A line glued at both ends picks both sites; glued at one end, it keeps the free end and picks that shape's
    /// nearest site. One undo step; nothing happens when no line would change.
    func rerouteConnectors() {
        let lines = reroutableLines
        guard !lines.isEmpty else { return }
        func dist(_ a: Offset, _ b: Offset) -> Double { ((a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy)).squareRoot() }
        func shape(_ c: ShapeConn?) -> SlideShape? { c.flatMap { c in currentSlide.shapes.first { $0.id == c.shape } } }
        var plan: [(SlideShape, ShapeConn?, ShapeConn?)] = []
        for l in lines {
            let a = shape(l.connStart), b = shape(l.connEnd)
            var best: (Double, Int, Int)? = nil
            if let a, let b {
                for i in 0..<a.connectionSiteCount { for j in 0..<b.connectionSiteCount {
                    guard let p = a.connectionSite(i), let q = b.connectionSite(j) else { continue }
                    let d = dist(p, q); if best == nil || d < best!.0 - 1e-9 { best = (d, i, j) }
                } }
                if let best { plan.append((l, ShapeConn(shape: a.id, site: best.1), ShapeConn(shape: b.id, site: best.2))) }
            } else if let a {
                for i in 0..<a.connectionSiteCount {
                    guard let p = a.connectionSite(i) else { continue }
                    let d = dist(p, l.lineEndPoint); if best == nil || d < best!.0 - 1e-9 { best = (d, i, 0) }
                }
                if let best { plan.append((l, ShapeConn(shape: a.id, site: best.1), nil)) }
            } else if let b {
                for j in 0..<b.connectionSiteCount {
                    guard let q = b.connectionSite(j) else { continue }
                    let d = dist(q, l.lineStart); if best == nil || d < best!.0 - 1e-9 { best = (d, 0, j) }
                }
                if let best { plan.append((l, nil, ShapeConn(shape: b.id, site: best.2))) }
            }
        }
        plan = plan.filter { l, s, e in (s != nil && s != l.connStart) || (e != nil && e != l.connEnd) }
        guard !plan.isEmpty else { return }
        _checkpoint()
        for (l, s, e) in plan { if let s { l.connStart = s }; if let e { l.connEnd = e } }
        followConnections()
        _changed()
    }

    /// A drag of an elbow's end (handle 0 the start, 1 the end) to `p`: the end glues to a site within reach when `snap` is
    /// on, or hangs free at `p`; the path is routed again. No history entry: the drag has its own.
    func dragElbowEnd(_ line: SlideShape, handle: Int, to p: Offset, snap: Bool) {
        guard line.isElbow else { return }
        let start = handle == 0
        var conn: ShapeConn? = nil
        var q = p
        if snap, let hit = nearestSite(to: p, excluding: line) {
            q = hit.point
            conn = ShapeConn(shape: hit.shape.id, site: hit.site)
        }
        if start { line.connStart = conn } else { line.connEnd = conn }
        line.moveLineEnd(start: start, to: q)
        _changed(keepSession: true)
    }

    /// After any change: each glued end sits on its site again, and an end whose shape has gone comes unglued. An elbow or
    /// curve is routed again between its ends, leaving and entering the shapes at the sides its sites face.
    func followConnections() {
        if _loading { return }
        for slide in slides {
            for s in slide.shapes where s.connStart != nil || s.connEnd != nil {
                if !s.connAnchor.isEmpty {
                    if s.connAnchor.allSatisfy({ id, f in slide.shapes.first(where: { $0.id == id })?.frame == f }) { continue }
                    s.connAnchor = [:]
                }
                var ends: [Bool: (Offset, (Double, Double))] = [:]
                for start in [true, false] {
                    guard let c = start ? s.connStart : s.connEnd else { continue }
                    if let t = slide.shapes.first(where: { $0.id == c.shape }), s.isGluableLine, let q = t.connectionSite(c.site) {
                        if s.isElbow, let d = t.connectionSiteDirection(c.site) {
                            ends[start] = (q, start ? d : (-d.0, -d.1))
                        } else { s.moveLineEnd(start: start, to: q) }
                    } else if start { s.connStart = nil } else { s.connEnd = nil }
                }
                guard s.isElbow, !ends.isEmpty else { continue }
                let from = ends[true]?.0 ?? s.lineStart, to = ends[false]?.0 ?? s.lineEndPoint
                s.apply(ElbowRoute.make(from: from, to: to, leaving: ends[true]?.1, arriving: ends[false]?.1,
                                        curved: s.preset?.rawValue.hasPrefix("curved") == true))
            }
        }
    }
}
