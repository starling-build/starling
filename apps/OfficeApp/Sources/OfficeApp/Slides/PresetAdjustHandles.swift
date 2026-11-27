// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// One yellow handle of a preset (`a:ahXY` or `a:ahPolar`): the adjust values it moves, their limits, and where it
/// sits (`a:pos`), all as the definition names them (`PresetHandleTable`).
struct PresetHandle: Equatable {
    /// `ahPolar`: `first` is the radius, `second` the angle; `ahXY`: `first` is x, `second` y.
    let polar: Bool
    let first: Axis?
    let second: Axis?
    let posX: String
    let posY: String

    struct Axis: Equatable {
        let ref: String
        let min: String
        let max: String
    }

    init?(_ row: Substring) {
        let w = row.split(separator: " ").map(String.init)
        guard w.count == 9 else { return nil }
        polar = w[0] == "polar"
        func axis(_ i: Int) -> Axis? { w[i] == "-" ? nil : Axis(ref: w[i], min: w[i + 1], max: w[i + 2]) }
        first = axis(1)
        second = axis(4)
        posX = w[7]
        posY = w[8]
    }
}

enum PresetHandles {
    /// A preset's handles, in the definition's order; none for a preset without any.
    static func handles(_ preset: String) -> [PresetHandle] {
        guard let row = PresetHandleTable.rows[preset] else { return [] }
        return row.split(separator: ";").compactMap(PresetHandle.init)
    }

    /// Where each handle sits in a shape `width` by `height` EMU at `adjusts` (origin at its top left, before
    /// mirroring and turning); nil for one whose place cannot be worked out.
    static func positions(_ preset: String, width: Double, height: Double, adjusts: [String: Double]) -> [Offset?] {
        let all = handles(preset)
        guard let g = PresetGeometry.guides(preset, width: width, height: height, adjustments: adjusts) else {
            return all.map { _ in nil }
        }
        return all.map { h in
            guard let x = g.value(h.posX), let y = g.value(h.posY) else { return nil }
            return Offset(x, y)
        }
    }

    /// The adjust values after handle `index` is dragged to `p` (EMU, in the shape's own box): each value the handle
    /// moves set, within its limits, to the whole number that brings the handle nearest `p`. PowerPoint stores whole
    /// numbers; a value the handle does not move stays as it was.
    static func drag(_ preset: String, handle index: Int, to p: Offset, width: Double, height: Double,
                     adjusts: [String: Double]) -> [String: Double] {
        let all = handles(preset)
        guard all.indices.contains(index),
              let start = PresetGeometry.guides(preset, width: width, height: height, adjustments: adjusts) else { return adjusts }
        let h = all[index]
        var out = adjusts
        // Values not yet set start from the definition's defaults.
        for a in [h.first, h.second].compactMap({ $0 }) where out[a.ref] == nil { out[a.ref] = start.value(a.ref) }
        func place(_ a: [String: Double]) -> Offset? {
            guard let g = PresetGeometry.guides(preset, width: width, height: height, adjustments: a),
                  let x = g.value(h.posX), let y = g.value(h.posY) else { return nil }
            return Offset(x, y)
        }
        // An xy handle follows the pointer along each of its axes on its own (a handle that moves only across
        // stays on its line however far up the pointer goes); a polar one goes to the nearest point, angle
        // first, then radius, then the angle again for the radius found.
        let order: [(PresetHandle.Axis, Int)] = h.polar
            ? [h.second.map { ($0, 2) }, h.first.map { ($0, 2) }, h.second.map { ($0, 2) }].compactMap { $0 }
            : [h.first.map { ($0, 0) }, h.second.map { ($0, 1) }].compactMap { $0 }
        for (axis, measure) in order {
            guard let g = PresetGeometry.guides(preset, width: width, height: height, adjustments: out),
                  let cur = out[axis.ref], var lo = g.value(axis.min), var hi = g.value(axis.max) else { continue }
            if lo > hi { swap(&lo, &hi) }
            // "No limit" is ±2147483647: search a window around the value instead, far wider than any slide.
            let reach = 1_000_000.0
            if lo < -1e9 { lo = Swift.min(cur, hi) - reach }
            if hi > 1e9 { hi = Swift.max(cur, lo) + reach }
            let cost: (Double) -> Double = { v in
                var a = out
                a[axis.ref] = v
                guard let q = place(a) else { return .infinity }
                switch measure {
                case 0: return abs(q.dx - p.dx)
                case 1: return abs(q.dy - p.dy)
                default: return hypot(q.dx - p.dx, q.dy - p.dy)
                }
            }
            out[axis.ref] = minimise(cost, lo, hi, current: cur)
        }
        return out
    }

    /// The whole number in `lo`...`hi` where `cost` is least: a scan, then a narrowing around the best point it found.
    /// Ties keep `current`, so a handle pinned by its limits does not wander.
    private static func minimise(_ cost: (Double) -> Double, _ lo: Double, _ hi: Double, current: Double) -> Double {
        guard hi > lo else { return lo.rounded() }
        let n = 128
        let step = (hi - lo) / Double(n)
        var best = Swift.min(Swift.max(current, lo), hi), bestCost = cost(best)
        for i in 0...n {
            let v = lo + Double(i) * step
            let c = cost(v)
            if c < bestCost - 1e-6 { best = v; bestCost = c }
        }
        var a = Swift.max(lo, best - step), b = Swift.min(hi, best + step)
        for _ in 0..<48 where b - a > 0.5 {
            let m1 = a + (b - a) / 3, m2 = b - (b - a) / 3
            if cost(m1) <= cost(m2) { b = m2 } else { a = m1 }
        }
        let mid = ((a + b) / 2).rounded()
        let candidates = [mid - 1, mid, mid + 1, best.rounded()].filter { $0 >= lo.rounded(.up) - 1e-9 && $0 <= hi.rounded(.down) + 1e-9 }
        var pick = candidates.first ?? mid, pickCost = cost(pick)
        for c in candidates.dropFirst() {
            let k = cost(c)
            if k < pickCost - 1e-6 { pick = c; pickCost = k }
        }
        if cost(current) <= pickCost + 1e-6, current >= lo, current <= hi { return current }
        return pick
    }
}

extension SlideShape {
    /// The yellow handles of a preset shape on the slide (not a line's or connector's): which handle, and where.
    var adjustHandles: [(index: Int, at: Offset)] {
        guard let name = preset?.rawValue, !(preset?.isLine ?? false), !isElbow, frame.width > 0, frame.height > 0 else { return [] }
        let e = Pptx.emu
        let places = PresetHandles.positions(name, width: frame.width * e, height: frame.height * e, adjusts: adjusts)
        return places.enumerated().compactMap { i, p in
            p.map { (i, toSlide(localX: $0.dx / e, localY: $0.dy / e)) }
        }
    }

    /// Drags yellow handle `index` to the slide point `p`.
    func setAdjustHandle(_ index: Int, to p: Offset) {
        guard let name = preset?.rawValue else { return }
        let c = frame.center
        let dx = p.dx - c.dx, dy = p.dy - c.dy
        let a = -rotation * .pi / 180
        var x = dx * cos(a) - dy * sin(a), y = dx * sin(a) + dy * cos(a)
        if flipH { x = -x }
        if flipV { y = -y }
        let e = Pptx.emu
        let local = Offset((x + frame.width / 2) * e, (y + frame.height / 2) * e)
        setAdjusts(PresetHandles.drag(name, handle: index, to: local, width: frame.width * e, height: frame.height * e,
                                      adjusts: adjusts))
    }

    /// Sets the preset's adjust values: the outline drawn again, and the text kept within the preset's text
    /// rectangle at the new values (the margins the text frame sets itself stay as they were).
    func setAdjusts(_ values: [String: Double]) {
        guard let name = preset?.rawValue, values != adjusts else { return }
        adjusts = values
        let e = Pptx.emu
        guard let g = PresetGeometry.geometry(name, width: frame.width * e, height: frame.height * e, adjustments: adjusts) else { return }
        customPath = g
        guard shapeInsets != .zero, let box = g.textRect else { return }
        var share = EdgeInsets(left: box.left * frame.width, top: box.top * frame.height,
                               right: (1 - box.right) * frame.width, bottom: (1 - box.bottom) * frame.height)
        if flipH || flipV { share = share.mirroringShare(share, horizontal: flipH, vertical: flipV) }
        insets = insets.minusShare(shapeInsets).plusShare(share)
        shapeInsets = share
    }
}
