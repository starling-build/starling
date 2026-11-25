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
