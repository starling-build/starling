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

    /// A straight line that may be glued: not mirrored, so its start is its frame's top left and its end the bottom right.
    var isGluableLine: Bool { preset?.isLine == true && !flipH && !flipV && rotation == 0 }

    var lineStart: Offset { Offset(frame.left, frame.top) }
    var lineEndPoint: Offset { Offset(frame.right, frame.bottom) }

    func moveLineEnd(start: Bool, to p: Offset) {
        frame = start ? Rect.fromLTRB(p.dx, p.dy, frame.right, frame.bottom)
                      : Rect.fromLTRB(frame.left, frame.top, p.dx, p.dy)
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
        for s in moved where s.preset?.isLine == true {
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

    /// After any change: each glued end sits on its site again, and an end whose shape has gone comes unglued.
    func followConnections() {
        for slide in slides {
            for s in slide.shapes where s.connStart != nil || s.connEnd != nil {
                for start in [true, false] {
                    guard let c = start ? s.connStart : s.connEnd else { continue }
                    if let t = slide.shapes.first(where: { $0.id == c.shape }), s.isGluableLine, let q = t.connectionSite(c.site) {
                        s.moveLineEnd(start: start, to: q)
                    } else if start { s.connStart = nil } else { s.connEnd = nil }
                }
            }
        }
    }
}
