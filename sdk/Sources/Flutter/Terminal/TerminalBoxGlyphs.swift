// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Box-drawing and block characters, drawn as rectangles instead of shaped
// from the font.
//
// WHY, given the font has these glyphs and they draw fine in prose. A font
// glyph is sized to its OWN ADVANCE. A terminal cell is not the advance — it
// is whatever the grid says, and once the cell is snapped to a whole number of
// device pixels (see TerminalView._snapCellToDevicePixels) the two differ by a
// fraction of a pixel. For letters that is invisible. For characters whose
// entire job is to meet their neighbours it is the whole story: a horizontal
// rule shows a hairline every cell, and a run of full blocks shows a comb of
// them. The glyph is not wrong; it simply does not know how wide the cell is.
//
// So these are drawn from the cell's own geometry, which makes them exact by
// construction: a line spans the cell edge to edge, a half block is half the
// cell, and adjacent cells abut on a shared coordinate. Every terminal that
// cares about this does the same — ghostty calls it a "sprite face" and hands
// its draw functions the integer cell width and height.
//
// SCOPE. The COMPLETE box-drawing and block-elements blocks, U+2500–259F —
// every line, dash, corner, tee and cross including the mixed weights, the
// double set pure and hybrid, the rounded corners, the diagonals, the
// half-lines, the eighths, quadrants and shades — plus the braille patterns
// and the core powerline separators. That is what real terminal output is
// drawn from: Claude Code's welcome frame is rounded corners plus light
// sides, its logo is quadrants and its spinner is braille, and every
// powerline prompt is E0B0–E0B7. The diagonals draw DIRECT on the frame
// canvas with a deliberate overshoot past the cell corners (`overflowsCell`)
// — a clipped atlas slot would pinch them where adjacent cells' strokes
// meet. Adding a glyph means extending a table here AND the decision list
// in the tests; the tests fail on either drifting from the other.
//
// SHAPE OF THIS FILE. Every glyph's geometry is computed as a pure PLAN —
// fills, shades and stroked segments as numbers — and `draw` merely replays
// the plan onto a canvas. The split exists for the tests: the plan is
// asserted directly (edge contact, seam bands, fill fractions, stroke
// continuity) at several cell geometries with no rasteriser in the loop,
// so "does every glyph reach the edges its arms claim" is a checked
// invariant rather than a hope. See Tests/FlutterTests/Terminal.

import Foundation
import FlutterSwiftBridge

/// How a box character reaches each edge of its cell.
struct BoxArms {
    var up = 0, down = 0, left = 0, right = 0   // 0 none, 1 light, 2 heavy
    var any: Bool { up + down + left + right > 0 }
}

/// One primitive of a glyph's drawing plan. Pure geometry — no canvas, no
/// paint — so the unit tests can assert on it as numbers.
enum BoxPlanOp {
    case fill(Rect)                    // solid, at the glyph's colour
    case shade(Rect, Double)           // solid, at a fraction of its alpha
    case stroke(from: Offset, segments: [BoxStroke], thickness: Double)
    case disc(Offset, Double)          // a braille dot: centre, radius
    case fillPath(from: Offset, segments: [BoxStroke])  // closed and filled
}

/// One segment of a stroked plan. The pen starts at the plan's `from` and
/// each segment continues from wherever the previous one ended.
enum BoxStroke {
    case line(to: Offset)
    case arc(oval: Rect, start: Double, sweep: Double)
}

enum TerminalBoxGlyphs {

    /// True for every scalar this file can draw. Checked per cell, so it is a
    /// range test and a table lookup, not a dictionary.
    static func handles(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x2500...0x259F: return true              // ALL box drawing + blocks
        case 0x2800...0x28FF: return true              // braille patterns
        case 0xE0B0...0xE0B7: return true              // powerline separators
        default: return false
        }
    }

    /// The three diagonals draw past their cell bounds so adjacent cells'
    /// strokes overlap at the shared corner instead of pinching there — which
    /// a clipped atlas slot cannot represent. The painter draws these DIRECT
    /// on the frame canvas in every mode.
    static func overflowsCell(_ scalar: UInt32) -> Bool {
        (0x2571...0x2573).contains(scalar)
    }

    /// Draw one cell: compute the plan, replay it. `x`/`y` are the cell's
    /// top-left in logical units.
    static func draw(_ canvas: any Canvas, scalar: UInt32,
                     x: Double, y: Double, w: Double, h: Double,
                     color: UInt32, scale: Double) {
        for op in plan(scalar: scalar, x: x, y: y, w: w, h: h, scale: scale) {
            switch op {
            case .fill(let r):
                let paint = Paint()
                paint.color = Color(Int(color))
                canvas.drawRect(r, paint)
            case .shade(let r, let frac):
                // A shade is a fraction of ink, and as a solid fill at that
                // alpha it is both closer to the intent and steadier than the
                // font's dither pattern, which beats against the pixel grid.
                let a = Double((color >> 24) & 0xFF) * frac
                let paint = Paint()
                paint.color = Color(Int((UInt32(a.rounded()) << 24) | (color & 0x00FF_FFFF)))
                canvas.drawRect(r, paint)
            case .stroke(let from, let segments, let thickness):
                let paint = Paint()
                paint.color = Color(Int(color))
                paint.style = .stroke
                paint.strokeWidth = thickness
                canvas.drawPath(builtPath(from, segments), paint)
            case .disc(let centre, let radius):
                let paint = Paint()
                paint.color = Color(Int(color))
                canvas.drawCircle(centre, radius, paint)
            case .fillPath(let from, let segments):
                let paint = Paint()
                paint.color = Color(Int(color))
                let path = builtPath(from, segments)
                path.close()
                canvas.drawPath(path, paint)
            }
        }
    }

    private static func builtPath(_ from: Offset, _ segments: [BoxStroke]) -> Path {
        let path = Path()
        path.moveTo(from.dx, from.dy)
        for segment in segments {
            switch segment {
            case .line(let to):
                path.lineTo(to.dx, to.dy)
            case .arc(let oval, let start, let sweep):
                path.arcTo(oval, start, sweep, false)
            }
        }
        return path
    }

    /// The full drawing plan for one cell. Everything `draw` paints comes
    /// from here, so asserting on this IS asserting on the rendering,
    /// rasteriser aside.
    static func plan(scalar: UInt32, x: Double, y: Double,
                     w: Double, h: Double, scale: Double) -> [BoxPlanOp] {
        if (0x2504...0x250B).contains(scalar) || (0x254C...0x254F).contains(scalar) {
            return dashOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if let a = arms(for: scalar) {
            return armOps(a, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x256D...0x2570).contains(scalar) {
            return roundedOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x2550...0x256C).contains(scalar) {
            return doubleOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x2571...0x2573).contains(scalar) {
            return diagonalOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x2800...0x28FF).contains(scalar) {
            return brailleOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0xE0B0...0xE0B7).contains(scalar) {
            return powerlineOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        return blockOps(scalar, x: x, y: y, w: w, h: h)
    }

    // MARK: - Lines

    /// Line thickness in logical units: one device pixel per unit of scale for
    /// a light line, doubled for a heavy one, so a line is always a whole
    /// number of device pixels and never lands half-lit.
    static func thickness(_ weight: Int, _ scale: Double) -> Double {
        let light = max(1.0, (scale).rounded())
        return (weight >= 2 ? light * 2 : light) / scale
    }

    private static func armOps(_ a: BoxArms,
                               x: Double, y: Double, w: Double, h: Double,
                               scale: Double) -> [BoxPlanOp] {
        // The centre join is as thick as the heaviest arm meeting here, so a
        // light arm joining a heavy one does not leave a notch at the join.
        let heaviest = max(max(a.up, a.down), max(a.left, a.right))
        let tv = thickness(heaviest, scale)          // join height
        let th = thickness(heaviest, scale)          // join width
        // Centre the join on whole device pixels; an odd thickness on an even
        // centre is what makes a line look like two grey rows instead of one.
        let cy = y + snap((h - tv) / 2, scale)
        let cx = x + snap((w - th) / 2, scale)

        // Each arm sits on ITS OWN weight's centred band — the seam law: a
        // light up-arm must occupy exactly the band a `│` in the cell above
        // occupies, whatever else meets it here (╽ is light above the join,
        // heavy below). For uniform-weight glyphs the band equals the join,
        // and this reduces to the previous geometry. Along its own axis an
        // arm still runs from the cell edge to the far side of the JOIN, so
        // opposite and perpendicular arms overlap there and leave no gap.
        func vband(_ weight: Int) -> (Double, Double) {
            let t = thickness(weight, scale)
            let bx = x + snap((w - t) / 2, scale)
            return (bx, t)
        }
        func hband(_ weight: Int) -> (Double, Double) {
            let t = thickness(weight, scale)
            let by = y + snap((h - t) / 2, scale)
            return (by, t)
        }
        var ops: [BoxPlanOp] = []
        if a.left > 0 {
            let (by, t) = hband(a.left)
            ops.append(.fill(Rect.fromLTRB(x, by, cx + th, by + t)))
        }
        if a.right > 0 {
            let (by, t) = hband(a.right)
            ops.append(.fill(Rect.fromLTRB(cx, by, x + w, by + t)))
        }
        if a.up > 0 {
            let (bx, t) = vband(a.up)
            ops.append(.fill(Rect.fromLTRB(bx, y, bx + t, cy + tv)))
        }
        if a.down > 0 {
            let (bx, t) = vband(a.down)
            ops.append(.fill(Rect.fromLTRB(bx, cy, bx + t, y + h)))
        }
        return ops
    }

    static func snap(_ v: Double, _ scale: Double) -> Double {
        (v * scale).rounded() / scale
    }

    // MARK: - Rounded corners

    /// ╭╮╯╰ as a stroked path: two straight runs meeting in a quarter arc,
    /// with the stroke centred on the same lines the rect arms occupy, so a
    /// rounded corner continues seamlessly into a `│` above or a `─` beside
    /// it — the seam between the font's corner and our synthesized sides is
    /// what forced these in here.
    private static func roundedOps(_ scalar: UInt32,
                                   x: Double, y: Double, w: Double, h: Double,
                                   scale: Double) -> [BoxPlanOp] {
        let th = thickness(1, scale)
        // The rect arms put a bar's LEADING edge at cx/cy; the stroke is
        // centred, so the centreline sits half a thickness further in.
        let bx = x + snap((w - th) / 2, scale) + th / 2
        let by = y + snap((h - th) / 2, scale) + th / 2
        let r = max(th, min(w, h) / 2 - th / 2)
        let pi = Double.pi

        let from: Offset
        let segments: [BoxStroke]
        switch scalar {
        case 0x256D:                                     // ╭ down + right
            from = Offset(bx, y + h)
            segments = [
                .line(to: Offset(bx, by + r)),
                .arc(oval: Rect.fromLTRB(bx, by, bx + 2 * r, by + 2 * r),
                     start: pi, sweep: pi / 2),
                .line(to: Offset(x + w, by)),
            ]
        case 0x256E:                                     // ╮ down + left
            from = Offset(bx, y + h)
            segments = [
                .line(to: Offset(bx, by + r)),
                .arc(oval: Rect.fromLTRB(bx - 2 * r, by, bx, by + 2 * r),
                     start: 0, sweep: -pi / 2),
                .line(to: Offset(x, by)),
            ]
        case 0x256F:                                     // ╯ up + left
            from = Offset(bx, y)
            segments = [
                .line(to: Offset(bx, by - r)),
                .arc(oval: Rect.fromLTRB(bx - 2 * r, by - 2 * r, bx, by),
                     start: 0, sweep: pi / 2),
                .line(to: Offset(x, by)),
            ]
        default:                                         // ╰ up + right
            from = Offset(bx, y)
            segments = [
                .line(to: Offset(bx, by - r)),
                .arc(oval: Rect.fromLTRB(bx, by - 2 * r, bx + 2 * r, by),
                     start: pi, sweep: -pi / 2),
                .line(to: Offset(x + w, by)),
            ]
        }
        return [.stroke(from: from, segments: segments, thickness: th)]
    }

    // MARK: - Doubles

    /// The double-line set, pure and hybrid: two light bars a light-line's
    /// width apart, centred as a pair on the same lines the single bars use;
    /// the hybrids (╒╓…╫) mix that pair with a single bar on the canonical
    /// band, so a ╪ continues into the │ above it and the ═ beside it.
    private static func doubleOps(_ scalar: UInt32,
                                  x: Double, y: Double, w: Double, h: Double,
                                  scale: Double) -> [BoxPlanOp] {
        let th = thickness(1, scale)
        let bx = x + snap((w - th) / 2, scale) + th / 2
        let by = y + snap((h - th) / 2, scale) + th / 2
        let d = th                                       // pair offset
        let vo = bx - d, vi = bx + d                     // vertical centres
        let ho = by - d, hi = by + d                     // horizontal centres
        var ops: [BoxPlanOp] = []
        func hbar(_ cy: Double, _ x0: Double, _ x1: Double) {
            ops.append(.fill(Rect.fromLTRB(x0, cy - th / 2, x1, cy + th / 2)))
        }
        func vbar(_ cx: Double, _ y0: Double, _ y1: Double) {
            ops.append(.fill(Rect.fromLTRB(cx - th / 2, y0, cx + th / 2, y1)))
        }
        switch scalar {
        case 0x2550:                                     // ═
            hbar(ho, x, x + w); hbar(hi, x, x + w)
        case 0x2551:                                     // ║
            vbar(vo, y, y + h); vbar(vi, y, y + h)
        case 0x2554:                                     // ╔ down + right
            hbar(ho, vo - th / 2, x + w); vbar(vo, ho - th / 2, y + h)
            hbar(hi, vi - th / 2, x + w); vbar(vi, hi - th / 2, y + h)
        case 0x2557:                                     // ╗ down + left
            hbar(ho, x, vi + th / 2); vbar(vi, ho - th / 2, y + h)
            hbar(hi, x, vo + th / 2); vbar(vo, hi - th / 2, y + h)
        case 0x255A:                                     // ╚ up + right
            hbar(hi, vo - th / 2, x + w); vbar(vo, y, hi + th / 2)
            hbar(ho, vi - th / 2, x + w); vbar(vi, y, ho + th / 2)
        case 0x255D:                                     // ╝ up + left
            hbar(hi, x, vi + th / 2); vbar(vi, y, hi + th / 2)
            hbar(ho, x, vo + th / 2); vbar(vo, y, ho + th / 2)
        case 0x2560:                                     // ╠
            vbar(vo, y, y + h)
            vbar(vi, y, ho + th / 2); vbar(vi, hi - th / 2, y + h)
            hbar(ho, vi - th / 2, x + w); hbar(hi, vi - th / 2, x + w)
        case 0x2563:                                     // ╣
            vbar(vi, y, y + h)
            vbar(vo, y, ho + th / 2); vbar(vo, hi - th / 2, y + h)
            hbar(ho, x, vo + th / 2); hbar(hi, x, vo + th / 2)
        case 0x2566:                                     // ╦
            hbar(ho, x, x + w)
            hbar(hi, x, vo + th / 2); hbar(hi, vi - th / 2, x + w)
            vbar(vo, hi - th / 2, y + h); vbar(vi, hi - th / 2, y + h)
        case 0x2569:                                     // ╩
            hbar(hi, x, x + w)
            hbar(ho, x, vo + th / 2); hbar(ho, vi - th / 2, x + w)
            vbar(vo, y, ho + th / 2); vbar(vi, y, ho + th / 2)
        case 0x2552:                                     // ╒ down S, right D
            hbar(ho, bx - th / 2, x + w); hbar(hi, bx - th / 2, x + w)
            vbar(bx, ho - th / 2, y + h)
        case 0x2553:                                     // ╓ down D, right S
            hbar(by, vo - th / 2, x + w)
            vbar(vo, by - th / 2, y + h); vbar(vi, by - th / 2, y + h)
        case 0x2555:                                     // ╕ down S, left D
            hbar(ho, x, bx + th / 2); hbar(hi, x, bx + th / 2)
            vbar(bx, ho - th / 2, y + h)
        case 0x2556:                                     // ╖ down D, left S
            hbar(by, x, vi + th / 2)
            vbar(vo, by - th / 2, y + h); vbar(vi, by - th / 2, y + h)
        case 0x2558:                                     // ╘ up S, right D
            hbar(ho, bx - th / 2, x + w); hbar(hi, bx - th / 2, x + w)
            vbar(bx, y, hi + th / 2)
        case 0x2559:                                     // ╙ up D, right S
            hbar(by, vo - th / 2, x + w)
            vbar(vo, y, by + th / 2); vbar(vi, y, by + th / 2)
        case 0x255B:                                     // ╛ up S, left D
            hbar(ho, x, bx + th / 2); hbar(hi, x, bx + th / 2)
            vbar(bx, y, hi + th / 2)
        case 0x255C:                                     // ╜ up D, left S
            hbar(by, x, vi + th / 2)
            vbar(vo, y, by + th / 2); vbar(vi, y, by + th / 2)
        case 0x255E:                                     // ╞ vertical S, right D
            vbar(bx, y, y + h)
            hbar(ho, bx - th / 2, x + w); hbar(hi, bx - th / 2, x + w)
        case 0x255F:                                     // ╟ vertical D, right S
            vbar(vo, y, y + h); vbar(vi, y, y + h)
            hbar(by, vi - th / 2, x + w)
        case 0x2561:                                     // ╡ vertical S, left D
            vbar(bx, y, y + h)
            hbar(ho, x, bx + th / 2); hbar(hi, x, bx + th / 2)
        case 0x2562:                                     // ╢ vertical D, left S
            vbar(vo, y, y + h); vbar(vi, y, y + h)
            hbar(by, x, vo + th / 2)
        case 0x2564:                                     // ╤ horizontal D, down S
            hbar(ho, x, x + w); hbar(hi, x, x + w)
            vbar(bx, hi - th / 2, y + h)
        case 0x2565:                                     // ╥ horizontal S, down D
            hbar(by, x, x + w)
            vbar(vo, by - th / 2, y + h); vbar(vi, by - th / 2, y + h)
        case 0x2567:                                     // ╧ horizontal D, up S
            hbar(ho, x, x + w); hbar(hi, x, x + w)
            vbar(bx, y, ho + th / 2)
        case 0x2568:                                     // ╨ horizontal S, up D
            hbar(by, x, x + w)
            vbar(vo, y, by + th / 2); vbar(vi, y, by + th / 2)
        case 0x256A:                                     // ╪ vertical S, horizontal D
            vbar(bx, y, y + h)
            hbar(ho, x, x + w); hbar(hi, x, x + w)
        case 0x256B:                                     // ╫ vertical D, horizontal S
            vbar(vo, y, y + h); vbar(vi, y, y + h)
            hbar(by, x, x + w)
        default:                                         // ╬
            vbar(vo, y, ho + th / 2); vbar(vo, hi - th / 2, y + h)
            vbar(vi, y, ho + th / 2); vbar(vi, hi - th / 2, y + h)
            hbar(ho, x, vo + th / 2); hbar(ho, vi - th / 2, x + w)
            hbar(hi, x, vo + th / 2); hbar(hi, vi - th / 2, x + w)
        }
        return ops
    }

    // MARK: - Blocks and shades

    private static func blockOps(_ scalar: UInt32,
                                 x: Double, y: Double,
                                 w: Double, h: Double) -> [BoxPlanOp] {
        switch scalar {
        case 0x2588:                                     // █ full
            return [.fill(Rect.fromLTWH(x, y, w, h))]
        case 0x2580:                                     // ▀ upper half
            return [.fill(Rect.fromLTWH(x, y, w, h / 2))]
        case 0x2584:                                     // ▄ lower half
            return [.fill(Rect.fromLTWH(x, y + h / 2, w, h / 2))]
        case 0x258C:                                     // ▌ left half
            return [.fill(Rect.fromLTWH(x, y, w / 2, h))]
        case 0x2590:                                     // ▐ right half
            return [.fill(Rect.fromLTWH(x + w / 2, y, w / 2, h))]
        case 0x2581...0x2587:                            // ▁▂▃▄▅▆▇ lower eighths
            let n = Double(scalar - 0x2580)              // 1...7 eighths tall
            let fh = h * n / 8
            return [.fill(Rect.fromLTWH(x, y + h - fh, w, fh))]
        case 0x2589...0x258F:                            // ▉▊▋▌▍▎▏ left eighths
            let n = Double(0x2590 - scalar)              // 7...1 eighths wide
            return [.fill(Rect.fromLTWH(x, y, w * n / 8, h))]
        case 0x2594:                                     // ▔ upper eighth
            return [.fill(Rect.fromLTWH(x, y, w, h / 8))]
        case 0x2595:                                     // ▕ right eighth
            return [.fill(Rect.fromLTRB(x + w * 7 / 8, y, x + w, y + h))]
        case 0x2596...0x259F:                            // ▖▗▘▙▚▛▜▝▞▟ quadrants
            // Quadrants share the exact midpoint coordinates, so the pairs
            // that should touch (▛'s upper-right and lower-left, a ▘ beside
            // a ▝) abut with no seam and no overlap.
            let xm = x + w / 2, ym = y + h / 2
            let mask: Int                                //  UL=1 UR=2 LL=4 LR=8
            switch scalar {
            case 0x2596: mask = 4                        // ▖
            case 0x2597: mask = 8                        // ▗
            case 0x2598: mask = 1                        // ▘
            case 0x2599: mask = 1 | 4 | 8                // ▙
            case 0x259A: mask = 1 | 8                    // ▚
            case 0x259B: mask = 1 | 2 | 4                // ▛
            case 0x259C: mask = 1 | 2 | 8                // ▜
            case 0x259D: mask = 2                        // ▝
            case 0x259E: mask = 2 | 4                    // ▞
            default:     mask = 2 | 4 | 8                // ▟
            }
            var ops: [BoxPlanOp] = []
            if mask & 1 != 0 { ops.append(.fill(Rect.fromLTRB(x, y, xm, ym))) }
            if mask & 2 != 0 { ops.append(.fill(Rect.fromLTRB(xm, y, x + w, ym))) }
            if mask & 4 != 0 { ops.append(.fill(Rect.fromLTRB(x, ym, xm, y + h))) }
            if mask & 8 != 0 { ops.append(.fill(Rect.fromLTRB(xm, ym, x + w, y + h))) }
            return ops
        case 0x2591, 0x2592, 0x2593:                     // ░▒▓ shades
            let frac = scalar == 0x2591 ? 0.25 : (scalar == 0x2592 ? 0.5 : 0.75)
            return [.shade(Rect.fromLTWH(x, y, w, h), frac)]
        default:
            return []
        }
    }

    // MARK: - Dashes

    /// ╌╍┄┅┆┇┈┉┊┋ ╎╏ — a broken bar on the canonical band of its weight: n
    /// segments, each 60% ink centred in its slice, so the line reads dashed
    /// and adjacent dashed cells stay visibly separate (a dash deliberately
    /// touches NO cell edge — that is what distinguishes it from ─).
    private static func dashOps(_ scalar: UInt32,
                                x: Double, y: Double, w: Double, h: Double,
                                scale: Double) -> [BoxPlanOp] {
        let (n, weight, horizontal): (Int, Int, Bool)
        switch scalar {
        case 0x2504: (n, weight, horizontal) = (3, 1, true)   // ┄
        case 0x2505: (n, weight, horizontal) = (3, 2, true)   // ┅
        case 0x2506: (n, weight, horizontal) = (3, 1, false)  // ┆
        case 0x2507: (n, weight, horizontal) = (3, 2, false)  // ┇
        case 0x2508: (n, weight, horizontal) = (4, 1, true)   // ┈
        case 0x2509: (n, weight, horizontal) = (4, 2, true)   // ┉
        case 0x250A: (n, weight, horizontal) = (4, 1, false)  // ┊
        case 0x250B: (n, weight, horizontal) = (4, 2, false)  // ┋
        case 0x254C: (n, weight, horizontal) = (2, 1, true)   // ╌
        case 0x254D: (n, weight, horizontal) = (2, 2, true)   // ╍
        case 0x254E: (n, weight, horizontal) = (2, 1, false)  // ╎
        default:     (n, weight, horizontal) = (2, 2, false)  // ╏
        }
        let t = thickness(weight, scale)
        var ops: [BoxPlanOp] = []
        if horizontal {
            let by = y + snap((h - t) / 2, scale)
            let seg = w / Double(n)
            for i in 0..<n {
                ops.append(.fill(Rect.fromLTRB(x + seg * (Double(i) + 0.2), by,
                                               x + seg * (Double(i) + 0.8), by + t)))
            }
        } else {
            let bx = x + snap((w - t) / 2, scale)
            let seg = h / Double(n)
            for i in 0..<n {
                ops.append(.fill(Rect.fromLTRB(bx, y + seg * (Double(i) + 0.2),
                                               bx + t, y + seg * (Double(i) + 0.8))))
            }
        }
        return ops
    }

    // MARK: - Diagonals

    /// ╱ ╲ ╳ as strokes overshooting the cell corners by one line thickness
    /// along the diagonal. Clipped exactly at the corner, two diagonals
    /// meeting from adjacent cells pinch to a point under antialiasing — the
    /// problem ghostty's quarter-cell sprite padding exists for. Here the
    /// overshoot rides the stroke itself, and the painter draws these three
    /// direct on the frame canvas (`overflowsCell`), never through a clipped
    /// atlas slot.
    private static func diagonalOps(_ scalar: UInt32,
                                    x: Double, y: Double, w: Double, h: Double,
                                    scale: Double) -> [BoxPlanOp] {
        let t = thickness(1, scale)
        let len = (w * w + h * h).squareRoot()
        let ox = t * w / len, oy = t * h / len
        let rising = BoxPlanOp.stroke(
            from: Offset(x - ox, y + h + oy),
            segments: [.line(to: Offset(x + w + ox, y - oy))],
            thickness: t)
        let falling = BoxPlanOp.stroke(
            from: Offset(x - ox, y - oy),
            segments: [.line(to: Offset(x + w + ox, y + h + oy))],
            thickness: t)
        switch scalar {
        case 0x2571: return [rising]                     // ╱
        case 0x2572: return [falling]                    // ╲
        default:     return [rising, falling]            // ╳
        }
    }

    // MARK: - Braille

    /// U+2800–28FF as discs on the standard 2x4 dot grid. Dots never join
    /// across cells, so there is no seam contract here — the properties that
    /// matter are the bit mapping (dot k is bit k-1) and that every dot stays
    /// inside its cell. Every TUI spinner lives in this range.
    private static func brailleOps(_ scalar: UInt32,
                                   x: Double, y: Double,
                                   w: Double, h: Double) -> [BoxPlanOp] {
        let bits = scalar - 0x2800
        // Dot k → (column, row) of the 2x4 grid, per the Unicode layout:
        // dots 1-3 down the left, 4-6 down the right, 7-8 the bottom pair.
        let grid: [(Int, Int)] = [(0, 0), (0, 1), (0, 2),      // dots 1 2 3
                                  (1, 0), (1, 1), (1, 2),      // dots 4 5 6
                                  (0, 3), (1, 3)]              // dots 7 8
        let radius = min(w / 2, h / 4) * 0.33
        var ops: [BoxPlanOp] = []
        for bit in 0..<8 where bits & (1 << bit) != 0 {
            let (col, row) = grid[bit]
            ops.append(.disc(Offset(x + w * (0.25 + 0.5 * Double(col)),
                                    y + h * (0.125 + 0.25 * Double(row))),
                             radius))
        }
        return ops
    }

    // MARK: - Powerline

    /// U+E0B0–E0B7, the private-use separators every powerline prompt is
    /// built from: solid and outline triangles, solid and outline
    /// half-circles. The solid forms hard-attach to one cell edge — the whole
    /// visual trick is the flush transition — so they claim that edge for the
    /// full cell height.
    private static func powerlineOps(_ scalar: UInt32,
                                     x: Double, y: Double, w: Double, h: Double,
                                     scale: Double) -> [BoxPlanOp] {
        let t = thickness(1, scale)
        let midY = y + h / 2
        let pi = Double.pi
        switch scalar {
        case 0xE0B0:                                     // solid right triangle
            return [.fillPath(from: Offset(x, y),
                              segments: [.line(to: Offset(x + w, midY)),
                                         .line(to: Offset(x, y + h))])]
        case 0xE0B1:                                     // right chevron
            return [.stroke(from: Offset(x, y),
                            segments: [.line(to: Offset(x + w, midY)),
                                       .line(to: Offset(x, y + h))],
                            thickness: t)]
        case 0xE0B2:                                     // solid left triangle
            return [.fillPath(from: Offset(x + w, y),
                              segments: [.line(to: Offset(x, midY)),
                                         .line(to: Offset(x + w, y + h))])]
        case 0xE0B3:                                     // left chevron
            return [.stroke(from: Offset(x + w, y),
                            segments: [.line(to: Offset(x, midY)),
                                       .line(to: Offset(x + w, y + h))],
                            thickness: t)]
        case 0xE0B4:                                     // solid right half-circle
            return [.fillPath(from: Offset(x, y),
                              segments: [.arc(oval: Rect.fromLTRB(x - w, y, x + w, y + h),
                                              start: -pi / 2, sweep: pi)])]
        case 0xE0B5:                                     // right half-circle line
            return [.stroke(from: Offset(x, y),
                            segments: [.arc(oval: Rect.fromLTRB(x - w, y, x + w, y + h),
                                            start: -pi / 2, sweep: pi)],
                            thickness: t)]
        case 0xE0B6:                                     // solid left half-circle
            return [.fillPath(from: Offset(x + w, y),
                              segments: [.arc(oval: Rect.fromLTRB(x, y, x + w + w, y + h),
                                              start: -pi / 2, sweep: -pi)])]
        default:                                         // E0B7 left half-circle line
            return [.stroke(from: Offset(x + w, y),
                            segments: [.arc(oval: Rect.fromLTRB(x, y, x + w + w, y + h),
                                            start: -pi / 2, sweep: -pi)],
                            thickness: t)]
        }
    }

    // MARK: - The arm table

    /// Which arms a box character extends, for the uniform-weight subset.
    /// nil means "not ours" — the font draws it.
    static func arms(for scalar: UInt32) -> BoxArms? {
        let L = 1, H = 2
        switch scalar {
        case 0x2500: return BoxArms(left: L, right: L)          // ─
        case 0x2501: return BoxArms(left: H, right: H)          // ━
        case 0x2502: return BoxArms(up: L, down: L)             // │
        case 0x2503: return BoxArms(up: H, down: H)             // ┃
        case 0x250C: return BoxArms(down: L, right: L)          // ┌
        case 0x250D: return BoxArms(down: L, right: H)          // ┍
        case 0x250E: return BoxArms(down: H, right: L)          // ┎
        case 0x250F: return BoxArms(down: H, right: H)          // ┏
        case 0x2510: return BoxArms(down: L, left: L)           // ┐
        case 0x2511: return BoxArms(down: L, left: H)           // ┑
        case 0x2512: return BoxArms(down: H, left: L)           // ┒
        case 0x2513: return BoxArms(down: H, left: H)           // ┓
        case 0x2514: return BoxArms(up: L, right: L)            // └
        case 0x2515: return BoxArms(up: L, right: H)            // ┕
        case 0x2516: return BoxArms(up: H, right: L)            // ┖
        case 0x2517: return BoxArms(up: H, right: H)            // ┗
        case 0x2518: return BoxArms(up: L, left: L)             // ┘
        case 0x2519: return BoxArms(up: L, left: H)             // ┙
        case 0x251A: return BoxArms(up: H, left: L)             // ┚
        case 0x251B: return BoxArms(up: H, left: H)             // ┛
        case 0x251C: return BoxArms(up: L, down: L, right: L)   // ├
        case 0x251D: return BoxArms(up: L, down: L, right: H)   // ┝
        case 0x251E: return BoxArms(up: H, down: L, right: L)   // ┞
        case 0x251F: return BoxArms(up: L, down: H, right: L)   // ┟
        case 0x2520: return BoxArms(up: H, down: H, right: L)   // ┠
        case 0x2521: return BoxArms(up: H, down: L, right: H)   // ┡
        case 0x2522: return BoxArms(up: L, down: H, right: H)   // ┢
        case 0x2523: return BoxArms(up: H, down: H, right: H)   // ┣
        case 0x2524: return BoxArms(up: L, down: L, left: L)    // ┤
        case 0x2525: return BoxArms(up: L, down: L, left: H)    // ┥
        case 0x2526: return BoxArms(up: H, down: L, left: L)    // ┦
        case 0x2527: return BoxArms(up: L, down: H, left: L)    // ┧
        case 0x2528: return BoxArms(up: H, down: H, left: L)    // ┨
        case 0x2529: return BoxArms(up: H, down: L, left: H)    // ┩
        case 0x252A: return BoxArms(up: L, down: H, left: H)    // ┪
        case 0x252B: return BoxArms(up: H, down: H, left: H)    // ┫
        case 0x252C: return BoxArms(down: L, left: L, right: L) // ┬
        case 0x252D: return BoxArms(down: L, left: H, right: L) // ┭
        case 0x252E: return BoxArms(down: L, left: L, right: H) // ┮
        case 0x252F: return BoxArms(down: L, left: H, right: H) // ┯
        case 0x2530: return BoxArms(down: H, left: L, right: L) // ┰
        case 0x2531: return BoxArms(down: H, left: H, right: L) // ┱
        case 0x2532: return BoxArms(down: H, left: L, right: H) // ┲
        case 0x2533: return BoxArms(down: H, left: H, right: H) // ┳
        case 0x2534: return BoxArms(up: L, left: L, right: L)   // ┴
        case 0x2535: return BoxArms(up: L, left: H, right: L)   // ┵
        case 0x2536: return BoxArms(up: L, left: L, right: H)   // ┶
        case 0x2537: return BoxArms(up: L, left: H, right: H)   // ┷
        case 0x2538: return BoxArms(up: H, left: L, right: L)   // ┸
        case 0x2539: return BoxArms(up: H, left: H, right: L)   // ┹
        case 0x253A: return BoxArms(up: H, left: L, right: H)   // ┺
        case 0x253B: return BoxArms(up: H, left: H, right: H)   // ┻
        case 0x253C: return BoxArms(up: L, down: L, left: L, right: L)  // ┼
        case 0x253D: return BoxArms(up: L, down: L, left: H, right: L)  // ┽
        case 0x253E: return BoxArms(up: L, down: L, left: L, right: H)  // ┾
        case 0x253F: return BoxArms(up: L, down: L, left: H, right: H)  // ┿
        case 0x2540: return BoxArms(up: H, down: L, left: L, right: L)  // ╀
        case 0x2541: return BoxArms(up: L, down: H, left: L, right: L)  // ╁
        case 0x2542: return BoxArms(up: H, down: H, left: L, right: L)  // ╂
        case 0x2543: return BoxArms(up: H, down: L, left: H, right: L)  // ╃
        case 0x2544: return BoxArms(up: H, down: L, left: L, right: H)  // ╄
        case 0x2545: return BoxArms(up: L, down: H, left: H, right: L)  // ╅
        case 0x2546: return BoxArms(up: L, down: H, left: L, right: H)  // ╆
        case 0x2547: return BoxArms(up: H, down: L, left: H, right: H)  // ╇
        case 0x2548: return BoxArms(up: L, down: H, left: H, right: H)  // ╈
        case 0x2549: return BoxArms(up: H, down: H, left: H, right: L)  // ╉
        case 0x254A: return BoxArms(up: H, down: H, left: L, right: H)  // ╊
        case 0x254B: return BoxArms(up: H, down: H, left: H, right: H)  // ╋
        case 0x2574: return BoxArms(left: L)                    // ╴
        case 0x2575: return BoxArms(up: L)                      // ╵
        case 0x2576: return BoxArms(right: L)                   // ╶
        case 0x2577: return BoxArms(down: L)                    // ╷
        case 0x2578: return BoxArms(left: H)                    // ╸
        case 0x2579: return BoxArms(up: H)                      // ╹
        case 0x257A: return BoxArms(right: H)                   // ╺
        case 0x257B: return BoxArms(down: H)                    // ╻
        case 0x257C: return BoxArms(left: L, right: H)          // ╼
        case 0x257D: return BoxArms(up: L, down: H)             // ╽
        case 0x257E: return BoxArms(left: H, right: L)          // ╾
        case 0x257F: return BoxArms(up: H, down: L)             // ╿
        default: return nil
        }
    }
}
