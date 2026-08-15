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
    case fillPath(from: Offset, segments: [BoxStroke], alpha: Double)  // closed + filled
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
        case 0x23F4...0x23FA: return true              // ⏴⏵⏶⏷⏸⏹⏺ media controls
        case 0x2500...0x259F: return true              // ALL box drawing + blocks
        case 0x25E2...0x25E5: return true              // ◢◣◤◥ corner triangles
        case 0x25F8...0x25FA, 0x25FF: return true      // ◸◹◺◿ outline triangles
        case 0x2800...0x28FF: return true              // braille patterns
        case 0x1FB93: return false                     // reserved, unassigned
        case 0x1FB00...0x1FBAF: return true            // sextants…fills…chamfers
        case 0x1FBCE, 0x1FBCF: return true             // thirds blocks
        case 0x1FBD0...0x1FBEF: return true            // diagonal pieces, circles
        case 0x1CC1B...0x1CC1E: return true            // line + edge-bar combos
        case 0x1CC21...0x1CC3F: return true            // separated quads, circle pieces
        case 0x1CD00...0x1CDE5: return true            // octants
        case 0x1CE00, 0x1CE01, 0x1CE0B, 0x1CE0C: return true  // white circles/ellipses
        case 0x1CE16...0x1CE19: return true            // vertical + edge-bar combos
        case 0x1CE51...0x1CEAF: return true            // separated sextants, sixteenths
        case 0xE0B0...0xE0BF: return true              // powerline separators
        case 0xF5D0...0xF60D: return true              // branch drawing (git graphs)
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
            case .fillPath(let from, let segments, let alpha):
                let a = Double((color >> 24) & 0xFF) * alpha
                let paint = Paint()
                paint.color = Color(Int((UInt32(a.rounded()) << 24) | (color & 0x00FF_FFFF)))
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
        if (0x1FB00...0x1FB3B).contains(scalar) {
            return sextantOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0x1FB3C...0x1FB67).contains(scalar) {
            return wedgeOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0x1FB68...0x1FB6F).contains(scalar) {
            return triangleOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0x1FB70...0x1FB8F).contains(scalar) {
            return legacyBlockOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0x1FB90...0x1FBAF).contains(scalar) || scalar == 0x1FBCE || scalar == 0x1FBCF {
            return legacyExtraOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x25E2...0x25E5).contains(scalar) || (0x25F8...0x25FA).contains(scalar)
            || scalar == 0x25FF {
            return geometricTriangleOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x23F4...0x23FA).contains(scalar) {
            return mediaControlOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0x1FBD0...0x1FBDF).contains(scalar) {
            return diagonalPieceOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x1FBE0...0x1FBEF).contains(scalar) {
            return circleOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x1CC1B...0x1CC1E).contains(scalar) || (0x1CE16...0x1CE19).contains(scalar) {
            return lineBarOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x1CC21...0x1CC2F).contains(scalar) || (0x1CE51...0x1CE8F).contains(scalar) {
            return separatedOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0x1CC30...0x1CC3F).contains(scalar)
            || [0x1CE00, 0x1CE01, 0x1CE0B, 0x1CE0C].contains(scalar) {
            return circlePieceOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x1CE90...0x1CE9F).contains(scalar) {
            let i = Int(scalar - 0x1CE90)
            return [.fill(Rect.fromLTRB(x + w * Double(i % 4) / 4,
                                        y + h * Double(i / 4) / 4,
                                        x + w * Double(i % 4 + 1) / 4,
                                        y + h * Double(i / 4 + 1) / 4))]
        }
        if (0x1CEA0...0x1CEAF).contains(scalar) {
            // The corner runs: single rects with quarter-fraction bounds.
            let q: [(Double, Double, Double, Double)] = [
                (2, 4, 3, 4), (1, 4, 3, 4), (0, 3, 3, 4), (0, 2, 3, 4),
                (0, 1, 2, 4), (0, 1, 1, 4), (0, 1, 0, 3), (0, 1, 0, 2),
                (0, 2, 0, 1), (0, 3, 0, 1), (1, 4, 0, 1), (2, 4, 0, 1),
                (3, 4, 0, 2), (3, 4, 0, 3), (3, 4, 1, 4), (3, 4, 2, 4),
            ]
            let f = q[Int(scalar - 0x1CEA0)]
            return [.fill(Rect.fromLTRB(x + w * f.0 / 4, y + h * f.2 / 4,
                                        x + w * f.1 / 4, y + h * f.3 / 4))]
        }
        if (0xF5D0...0xF60D).contains(scalar) {
            return branchOps(scalar, x: x, y: y, w: w, h: h, scale: scale)
        }
        if (0x1CD00...0x1CDE5).contains(scalar) {
            return octantOps(scalar, x: x, y: y, w: w, h: h)
        }
        if (0xE0B0...0xE0BF).contains(scalar) {
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

    // MARK: - Legacy computing mosaics

    /// Sextants U+1FB00–1FB3B: 2x3 mosaics, like the quadrants one row
    /// finer. The codepoints run through the 6-bit masks in order, SKIPPING
    /// empty, full, and the two half-blocks that already exist in U+2580's
    /// block — which is why the index needs two bumps rather than being the
    /// mask itself. Cell k is bit k-1: (k-1)%2 the column, (k-1)/2 the row.
    private static func sextantOps(_ scalar: UInt32,
                                   x: Double, y: Double,
                                   w: Double, h: Double) -> [BoxPlanOp] {
        var mask = scalar - 0x1FB00 + 1
        if mask >= 0b010101 { mask += 1 }               // ▌ left half, skipped
        if mask >= 0b101010 { mask += 1 }               // ▐ right half, skipped
        let xm = x + w / 2
        let ys = [y, y + h / 3, y + 2 * h / 3, y + h]
        var ops: [BoxPlanOp] = []
        for bit in 0..<6 where mask & (1 << bit) != 0 {
            let row = bit / 2
            ops.append(.fill(bit % 2 == 0
                ? Rect.fromLTRB(x, ys[row], xm, ys[row + 1])
                : Rect.fromLTRB(xm, ys[row], x + w, ys[row + 1])))
        }
        return ops
    }

    /// Octants U+1CD00–1CDE5 (Unicode 16): 2x4 mosaics. The 26 shapes that
    /// already exist elsewhere — the quadrant combinations, the half and
    /// quarter blocks — are excluded from the range with no usable pattern,
    /// so the mapping is a table: mask per codepoint, in order, derived from
    /// the Unicode names (cell k of the name is bit k-1).
    private static let octantMasks: [UInt8] = [
        0x04, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, 0x0E, 0x10, 0x11, 0x12,
        0x13, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
        0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x29, 0x2A, 0x2B, 0x2C,
        0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
        0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46,
        0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x51, 0x52, 0x53,
        0x54, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x5D, 0x5E, 0x60, 0x61, 0x62,
        0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E,
        0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A,
        0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F, 0x90, 0x91, 0x92, 0x93,
        0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
        0xA1, 0xA2, 0xA3, 0xA4, 0xA6, 0xA7, 0xA8, 0xA9, 0xAB, 0xAC, 0xAD, 0xAE,
        0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB,
        0xBC, 0xBD, 0xBE, 0xBF, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8,
        0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4,
        0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE0,
        0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC,
        0xED, 0xEE, 0xEF, 0xF1, 0xF2, 0xF3, 0xF4, 0xF6, 0xF7, 0xF8, 0xF9, 0xFB,
        0xFD, 0xFE,
    ]

    private static func octantOps(_ scalar: UInt32,
                                  x: Double, y: Double,
                                  w: Double, h: Double) -> [BoxPlanOp] {
        let mask = octantMasks[Int(scalar - 0x1CD00)]
        let xm = x + w / 2
        let ys = [y, y + h / 4, y + h / 2, y + 3 * h / 4, y + h]
        var ops: [BoxPlanOp] = []
        for bit in 0..<8 where mask & (1 << bit) != 0 {
            let row = bit / 2
            ops.append(.fill(bit % 2 == 0
                ? Rect.fromLTRB(x, ys[row], xm, ys[row + 1])
                : Rect.fromLTRB(xm, ys[row], x + w, ys[row + 1])))
        }
        return ops
    }

    /// Smooth mosaics U+1FB3C–1FB67 — the wedges chafa's smooth mode draws
    /// images with. Each glyph is one filled polygon whose vertices lie on
    /// the wedge lattice: x at {0, ½, 1}, y at {0, ⅓, ⅔, 1}. The masks flag
    /// which of the ten boundary points are vertices, in polygon-walk order
    /// (down the left side, across the bottom, up the right, back across the
    /// top); they are derived from ghostty's hand-written pattern table
    /// (MIT) through its own vertex reduction, because no mathematical
    /// pattern relates codepoint to shape.
    private static let wedgeMasks: [UInt16] = [
        0x01C, 0x02C, 0x01A, 0x02A, 0x019, 0x32A, 0x12A, 0x32C, 0x12C, 0x328,
        0x0AC, 0x070, 0x068, 0x0B0, 0x0A8, 0x130, 0x2A9, 0x0A9, 0x269, 0x069,
        0x229, 0x06A, 0x135, 0x125, 0x133, 0x123, 0x131, 0x203, 0x103, 0x205,
        0x105, 0x209, 0x185, 0x159, 0x149, 0x199, 0x189, 0x119, 0x380, 0x181,
        0x340, 0x141, 0x320, 0x143,
    ]

    private static func wedgeOps(_ scalar: UInt32,
                                 x: Double, y: Double,
                                 w: Double, h: Double) -> [BoxPlanOp] {
        let mask = wedgeMasks[Int(scalar - 0x1FB3C)]
        let pts: [(Double, Double)] = [
            (x, y),                                      // top-left corner
            (x, y + h / 3), (x, y + 2 * h / 3),          // left edge thirds
            (x, y + h),                                  // bottom-left corner
            (x + w / 2, y + h),                          // bottom centre
            (x + w, y + h),                              // bottom-right corner
            (x + w, y + 2 * h / 3), (x + w, y + h / 3),  // right edge thirds
            (x + w, y),                                  // top-right corner
            (x + w / 2, y),                              // top centre
        ]
        var poly: [Offset] = []
        for bit in 0..<10 where mask & (1 << bit) != 0 {
            poly.append(Offset(pts[bit].0, pts[bit].1))
        }
        return [.fillPath(from: poly[0],
                          segments: poly.dropFirst().map { .line(to: $0) },
                          alpha: 1)]
    }

    /// U+1FB68–1FB6F: the four quarter triangles pointing at the cell
    /// centre, and the four three-quarter blocks that are the cell minus
    /// one of them.
    private static func triangleOps(_ scalar: UInt32,
                                    x: Double, y: Double,
                                    w: Double, h: Double) -> [BoxPlanOp] {
        let c = Offset(x + w / 2, y + h / 2)
        let tl = Offset(x, y), tr = Offset(x + w, y)
        let bl = Offset(x, y + h), br = Offset(x + w, y + h)
        let poly: [Offset]
        switch scalar {
        case 0x1FB68: poly = [tl, c, bl, br, tr]         // 🭨 all but left
        case 0x1FB69: poly = [tl, c, tr, br, bl]         // 🭩 all but top
        case 0x1FB6A: poly = [tr, c, br, bl, tl]         // 🭪 all but right
        case 0x1FB6B: poly = [bl, c, br, tr, tl]         // 🭫 all but bottom
        case 0x1FB6C: poly = [tl, c, bl]                 // 🭬 left triangle
        case 0x1FB6D: poly = [tl, tr, c]                 // 🭭 upper triangle
        case 0x1FB6E: poly = [tr, br, c]                 // 🭮 right triangle
        default:      poly = [bl, c, br]                 // 🭯 lower triangle
        }
        return [.fillPath(from: poly[0],
                          segments: poly.dropFirst().map { .line(to: $0) },
                          alpha: 1)]
    }

    /// U+1FB70–1FB8F: the positional eighth blocks (a vertical or horizontal
    /// eighth at positions 2–7 — positions 1 and 8 live in U+2580's block),
    /// the one-eighth frame pieces, the upper/right partial blocks at the
    /// fractions U+2580 skips, and the four half-cell medium shades.
    private static func legacyBlockOps(_ scalar: UInt32,
                                       x: Double, y: Double,
                                       w: Double, h: Double) -> [BoxPlanOp] {
        func col(_ n: Double) -> BoxPlanOp {             // vertical eighth n (0-7)
            .fill(Rect.fromLTRB(x + w * n / 8, y, x + w * (n + 1) / 8, y + h))
        }
        func row(_ n: Double) -> BoxPlanOp {             // horizontal eighth n (0-7)
            .fill(Rect.fromLTRB(x, y + h * n / 8, x + w, y + h * (n + 1) / 8))
        }
        let upperK: [Double] = [2, 3, 5, 6, 7]           // the fractions 2580 skips
        switch scalar {
        case 0x1FB70...0x1FB75:                          // 🭰…🭵 vertical eighths 2-7
            return [col(Double(scalar - 0x1FB70) + 1)]
        case 0x1FB76...0x1FB7B:                          // 🭶…🭻 horizontal eighths 2-7
            return [row(Double(scalar - 0x1FB76) + 1)]
        case 0x1FB7C: return [col(0), row(7)]            // 🭼 left and lower
        case 0x1FB7D: return [col(0), row(0)]            // 🭽 left and upper
        case 0x1FB7E: return [col(7), row(0)]            // 🭾 right and upper
        case 0x1FB7F: return [col(7), row(7)]            // 🭿 right and lower
        case 0x1FB80: return [row(0), row(7)]            // 🮀 upper and lower
        case 0x1FB81: return [row(0), row(2), row(4), row(7)]  // 🮁 rows 1,3,5,8
        case 0x1FB82...0x1FB86:                          // 🮂…🮆 upper k/8
            let k = upperK[Int(scalar - 0x1FB82)]
            return [.fill(Rect.fromLTRB(x, y, x + w, y + h * k / 8))]
        case 0x1FB87...0x1FB8B:                          // 🮇…🮋 right k/8
            let k = upperK[Int(scalar - 0x1FB87)]
            return [.fill(Rect.fromLTRB(x + w * (8 - k) / 8, y, x + w, y + h))]
        case 0x1FB8C:                                    // 🮌 left half medium shade
            return [.shade(Rect.fromLTRB(x, y, x + w / 2, y + h), 0.5)]
        case 0x1FB8D:                                    // 🮍 right half
            return [.shade(Rect.fromLTRB(x + w / 2, y, x + w, y + h), 0.5)]
        case 0x1FB8E:                                    // 🮎 upper half
            return [.shade(Rect.fromLTRB(x, y, x + w, y + h / 2), 0.5)]
        default:                                         // 🮏 lower half
            return [.shade(Rect.fromLTRB(x, y + h / 2, x + w, y + h), 0.5)]
        }
    }

    // MARK: - Legacy fills, shade combos, and chamfer lines

    /// U+1FB90–1FBAF plus the thirds blocks: the inverse-shade combinations,
    /// the checker and stripe fills, the hourglass and bowtie pairs, the
    /// corner triangle shades, the corner chamfer lines, and U+1FBAF (the
    /// heavy-vertical/light-horizontal cross this block re-encodes).
    private static func legacyExtraOps(_ scalar: UInt32,
                                       x: Double, y: Double, w: Double, h: Double,
                                       scale: Double) -> [BoxPlanOp] {
        let c = Offset(x + w / 2, y + h / 2)
        let tl = Offset(x, y), tr = Offset(x + w, y)
        let bl = Offset(x, y + h), br = Offset(x + w, y + h)
        func tri(_ a: Offset, _ b: Offset, _ d: Offset,
                 _ alpha: Double = 1) -> BoxPlanOp {
            .fillPath(from: a, segments: [.line(to: b), .line(to: d)], alpha: alpha)
        }
        switch scalar {
        case 0x1FB90:                                    // 🮐 inverse medium shade
            return [.shade(Rect.fromLTWH(x, y, w, h), 0.5)]
        case 0x1FB91:                                    // 🮑 upper solid, lower shade
            return [.fill(Rect.fromLTRB(x, y, x + w, y + h / 2)),
                    .shade(Rect.fromLTRB(x, y + h / 2, x + w, y + h), 0.5)]
        case 0x1FB92:                                    // 🮒 upper shade, lower solid
            return [.shade(Rect.fromLTRB(x, y, x + w, y + h / 2), 0.5),
                    .fill(Rect.fromLTRB(x, y + h / 2, x + w, y + h))]
        case 0x1FB94:                                    // 🮔 left shade, right solid
            return [.shade(Rect.fromLTRB(x, y, x + w / 2, y + h), 0.5),
                    .fill(Rect.fromLTRB(x + w / 2, y, x + w, y + h))]
        case 0x1FB95, 0x1FB96:                           // 🮕🮖 checker + inverse
            let parity = scalar == 0x1FB95 ? 0 : 1
            var ops: [BoxPlanOp] = []
            for row in 0..<4 {
                for col in 0..<4 where (row + col) % 2 == parity {
                    ops.append(.fill(Rect.fromLTRB(
                        x + w * Double(col) / 4, y + h * Double(row) / 4,
                        x + w * Double(col + 1) / 4, y + h * Double(row + 1) / 4)))
                }
            }
            return ops
        case 0x1FB97:                                    // 🮗 heavy horizontal fill
            return [.fill(Rect.fromLTRB(x, y + h / 4, x + w, y + h / 2)),
                    .fill(Rect.fromLTRB(x, y + 3 * h / 4, x + w, y + h))]
        case 0x1FB98, 0x1FB99:                           // 🮘🮙 diagonal hatches
            // Five strokes parallel to the cell diagonal, endpoints on the
            // boundary — a real hatch, not a flat shade, because at cell
            // scale the direction of the pattern is the glyph.
            let t = thickness(1, scale)
            let down = scalar == 0x1FB98                 // ╲ direction or ╱
            var ops: [BoxPlanOp] = []
            for k in [-0.667, -0.333, 0.0, 0.333, 0.667] {
                let (p0, p1): (Offset, Offset)
                if k < 0 {                               // toward the left/bottom
                    let f = 1 + k
                    (p0, p1) = down
                        ? (Offset(x, y + h * -k), Offset(x + w * f, y + h))
                        : (Offset(x + w * f, y), Offset(x, y + h * f))
                } else {                                 // toward the right/top
                    let f = 1 - k
                    (p0, p1) = down
                        ? (Offset(x + w * k, y), Offset(x + w, y + h * f))
                        : (Offset(x + w, y + h * k), Offset(x + w * k, y + h))
                }
                ops.append(.stroke(from: p0, segments: [.line(to: p1)], thickness: t))
            }
            return ops
        case 0x1FB9A:                                    // 🮚 hourglass
            return [tri(tl, tr, c), tri(bl, c, br)]
        case 0x1FB9B:                                    // 🮛 bowtie
            return [tri(tl, c, bl), tri(tr, br, c)]
        case 0x1FB9C: return [tri(tl, bl, tr, 0.5)]      // 🮜 shaded corner triangles
        case 0x1FB9D: return [tri(tl, br, tr, 0.5)]      // 🮝
        case 0x1FB9E: return [tri(bl, br, tr, 0.5)]      // 🮞
        case 0x1FB9F: return [tri(tl, bl, br, 0.5)]      // 🮟
        case 0x1FBA0...0x1FBAE:                          // 🮠…🮮 corner chamfer lines
            let masks: [UInt32] = [1, 2, 4, 8, 5, 10, 12, 3, 9, 6, 14, 13, 11, 7, 15]
            let mask = masks[Int(scalar - 0x1FBA0)]
            let t = thickness(1, scale)
            let mt = Offset(x + w / 2, y), ml = Offset(x, y + h / 2)
            let mr = Offset(x + w, y + h / 2), mb = Offset(x + w / 2, y + h)
            var ops: [BoxPlanOp] = []
            if mask & 1 != 0 { ops.append(.stroke(from: mt, segments: [.line(to: ml)], thickness: t)) }
            if mask & 2 != 0 { ops.append(.stroke(from: mt, segments: [.line(to: mr)], thickness: t)) }
            if mask & 4 != 0 { ops.append(.stroke(from: mb, segments: [.line(to: ml)], thickness: t)) }
            if mask & 8 != 0 { ops.append(.stroke(from: mb, segments: [.line(to: mr)], thickness: t)) }
            return ops
        case 0x1FBAF:                                    // 🮯 heavy vertical, light horizontal
            return armOps(BoxArms(up: 2, down: 2, left: 1, right: 1),
                          x: x, y: y, w: w, h: h, scale: scale)
        case 0x1FBCE:                                    // 🯎 left two thirds
            return [.fill(Rect.fromLTRB(x, y, x + 2 * w / 3, y + h))]
        default:                                         // 🯏 left one third
            return [.fill(Rect.fromLTRB(x, y, x + w / 3, y + h))]
        }
    }

    /// ◢◣◤◥ solid and ◸◹◺◿ outlined half-cell triangles — prompt decorations
    /// and the odd TUI chart. The outlines are stroked with an explicit
    /// closing segment.
    private static func geometricTriangleOps(_ scalar: UInt32,
                                             x: Double, y: Double,
                                             w: Double, h: Double,
                                             scale: Double) -> [BoxPlanOp] {
        let tl = Offset(x, y), tr = Offset(x + w, y)
        let bl = Offset(x, y + h), br = Offset(x + w, y + h)
        let corners: [Offset]
        switch scalar {
        case 0x25E2: corners = [bl, br, tr]              // ◢ lower right
        case 0x25E3: corners = [tl, bl, br]              // ◣ lower left
        case 0x25E4: corners = [tl, bl, tr]              // ◤ upper left
        case 0x25E5: corners = [tl, br, tr]              // ◥ upper right
        case 0x25F8: corners = [tl, bl, tr]              // ◸ outlined upper left
        case 0x25F9: corners = [tl, br, tr]              // ◹ outlined upper right
        case 0x25FA: corners = [tl, bl, br]              // ◺ outlined lower left
        default:     corners = [bl, br, tr]              // ◿ outlined lower right
        }
        if scalar <= 0x25E5 {
            return [.fillPath(from: corners[0],
                              segments: corners.dropFirst().map { .line(to: $0) },
                              alpha: 1)]
        }
        return [.stroke(from: corners[0],
                        segments: corners.dropFirst().map { .line(to: $0) }
                            + [.line(to: corners[0])],
                        thickness: thickness(1, scale))]
    }

    // MARK: - Media controls

    /// ⏴⏵⏶⏷⏸⏹⏺ (U+23F4–23FA). No face in the bundled fallback chain has
    /// them — Roboto Mono, both DejaVu monos, DejaVu Sans, the Noto CJK and
    /// emoji faces all stop short of the media-control block — and with no
    /// system font fallback the cells painted NOTHING: Claude Code's "⏵⏵"
    /// auto-mode indicator was simply absent. Shapes are sized from the cell
    /// WIDTH (a terminal cell is ~1.7x taller than wide, so keying off the
    /// full cell box draws comically stretched arrows).
    private static func mediaControlOps(_ scalar: UInt32,
                                        x: Double, y: Double,
                                        w: Double, h: Double) -> [BoxPlanOp] {
        let cx = x + w / 2, cy = y + h / 2
        // Triangles keep a margin so a run like Claude Code's "⏵⏵" reads as
        // two arrows, not one chain; the pause/stop/record marks keep the
        // larger box for the same visual weight.
        let tri2 = min(w, h) * 0.44
        let mark = min(w, h) * 0.48
        func tri(_ a: Offset, _ b: Offset, _ c: Offset) -> [BoxPlanOp] {
            [.fillPath(from: a, segments: [.line(to: b), .line(to: c)], alpha: 1)]
        }
        switch scalar {
        case 0x23F4:                                     // ⏴ left
            return tri(Offset(cx + tri2, cy - tri2), Offset(cx + tri2, cy + tri2),
                       Offset(cx - tri2, cy))
        case 0x23F5:                                     // ⏵ right
            return tri(Offset(cx - tri2, cy - tri2), Offset(cx - tri2, cy + tri2),
                       Offset(cx + tri2, cy))
        case 0x23F6:                                     // ⏶ up
            return tri(Offset(cx - tri2, cy + tri2), Offset(cx + tri2, cy + tri2),
                       Offset(cx, cy - tri2))
        case 0x23F7:                                     // ⏷ down
            return tri(Offset(cx - tri2, cy - tri2), Offset(cx + tri2, cy - tri2),
                       Offset(cx, cy + tri2))
        case 0x23F8:                                     // ⏸ pause
            let bar = mark * 0.62
            return [.fill(Rect.fromLTRB(cx - mark, cy - mark, cx - mark + bar, cy + mark)),
                    .fill(Rect.fromLTRB(cx + mark - bar, cy - mark, cx + mark, cy + mark))]
        case 0x23F9:                                     // ⏹ stop
            let s = mark * 0.86
            return [.fill(Rect.fromLTRB(cx - s, cy - s, cx + s, cy + s))]
        default:                                         // ⏺ record
            return [.disc(Offset(cx, cy), mark * 0.92)]
        }
    }

    // MARK: - Diagonal pieces and circles

    /// U+1FBD0–1FBDF: light strokes between points of the cell's 3x3
    /// alignment grid — corners, edge midpoints, centre. The first eight are
    /// single segments; the rest are two segments meeting at a shared point,
    /// the chevron family.
    private static func diagonalPieceOps(_ scalar: UInt32,
                                         x: Double, y: Double, w: Double, h: Double,
                                         scale: Double) -> [BoxPlanOp] {
        // Grid coordinates: (col, row) in 0...2, scaled by the half-cell.
        typealias P = (Int, Int)
        let table: [[(P, P)]] = [
            [((2, 1), (0, 2))],                          // 🯐 MR→LL
            [((2, 0), (0, 1))],                          // 🯑 UR→ML
            [((0, 0), (2, 1))],                          // 🯒 UL→MR
            [((0, 1), (2, 2))],                          // 🯓 ML→LR
            [((0, 0), (1, 2))],                          // 🯔 UL→LC
            [((1, 0), (2, 2))],                          // 🯕 UC→LR
            [((2, 0), (1, 2))],                          // 🯖 UR→LC
            [((1, 0), (0, 2))],                          // 🯗 UC→LL
            [((0, 0), (1, 1)), ((1, 1), (2, 0))],        // 🯘 UL→C→UR
            [((2, 0), (1, 1)), ((1, 1), (2, 2))],        // 🯙 UR→C→LR
            [((0, 2), (1, 1)), ((1, 1), (2, 2))],        // 🯚 LL→C→LR
            [((0, 0), (1, 1)), ((1, 1), (0, 2))],        // 🯛 UL→C→LL
            [((0, 0), (1, 2)), ((1, 2), (2, 0))],        // 🯜 UL→LC→UR
            [((2, 0), (0, 1)), ((0, 1), (2, 2))],        // 🯝 UR→ML→LR
            [((0, 2), (1, 0)), ((1, 0), (2, 2))],        // 🯞 LL→UC→LR
            [((0, 0), (2, 1)), ((2, 1), (0, 2))],        // 🯟 UL→MR→LL
        ]
        let t = thickness(1, scale)
        func pt(_ p: P) -> Offset {
            Offset(x + w * Double(p.0) / 2, y + h * Double(p.1) / 2)
        }
        return table[Int(scalar - 0x1FBD0)].map {
            .stroke(from: pt($0.0), segments: [.line(to: pt($0.1))], thickness: t)
        }
    }

    /// U+1FBE0–1FBEF: circles centred on cell edges and corners (the in-cell
    /// part is a half or quarter disc), and the four centred half-size
    /// blocks. Radius is half the smaller cell dimension, like a font would
    /// square the shape.
    private static func circleOps(_ scalar: UInt32,
                                  x: Double, y: Double, w: Double, h: Double,
                                  scale: Double) -> [BoxPlanOp] {
        let t = thickness(1, scale)
        let pi = Double.pi
        let r = min(w, h) / 2
        func oval(_ cx: Double, _ cy: Double, _ radius: Double) -> Rect {
            Rect.fromLTRB(cx - radius, cy - radius, cx + radius, cy + radius)
        }
        // The visible half of a circle centred on an edge midpoint, as a
        // start angle and sweep (y-down angles; π/2 is the cell's bottom).
        func half(_ cx: Double, _ cy: Double, start: Double,
                  filled: Bool) -> BoxPlanOp {
            filled
                ? .fillPath(from: Offset(cx + r * cos(start), cy + r * sin(start)),
                            segments: [.arc(oval: oval(cx, cy, r),
                                            start: start, sweep: pi)],
                            alpha: 1)
                : .stroke(from: Offset(cx + (r - t / 2) * cos(start),
                                       cy + (r - t / 2) * sin(start)),
                          segments: [.arc(oval: oval(cx, cy, r - t / 2),
                                          start: start, sweep: pi)],
                          thickness: t)
        }
        // A quarter disc hanging off a corner: arc plus the two edge runs
        // back through the corner.
        func quarter(_ corner: Offset, start: Double) -> BoxPlanOp {
            let from = Offset(corner.dx + r * cos(start), corner.dy + r * sin(start))
            return .fillPath(from: from,
                             segments: [.arc(oval: oval(corner.dx, corner.dy, r),
                                             start: start, sweep: pi / 2),
                                        .line(to: corner)],
                             alpha: 1)
        }
        switch scalar {
        case 0x1FBE0: return [half(x + w / 2, y, start: pi, filled: false)]      // 🯠
        case 0x1FBE1: return [half(x + w, y + h / 2, start: pi / 2, filled: false)] // 🯡
        case 0x1FBE2: return [half(x + w / 2, y + h, start: pi, filled: false)]  // 🯢
        case 0x1FBE3: return [half(x, y + h / 2, start: -pi / 2, filled: false)] // 🯣
        case 0x1FBE4:                                    // 🯤 upper centre block
            return [.fill(Rect.fromLTRB(x + w / 4, y, x + 3 * w / 4, y + h / 2))]
        case 0x1FBE5:                                    // 🯥 lower centre block
            return [.fill(Rect.fromLTRB(x + w / 4, y + h / 2, x + 3 * w / 4, y + h))]
        case 0x1FBE6:                                    // 🯦 middle left block
            return [.fill(Rect.fromLTRB(x, y + h / 4, x + w / 2, y + 3 * h / 4))]
        case 0x1FBE7:                                    // 🯧 middle right block
            return [.fill(Rect.fromLTRB(x + w / 2, y + h / 4, x + w, y + 3 * h / 4))]
        case 0x1FBE8: return [half(x + w / 2, y, start: pi, filled: true)]       // 🯨
        case 0x1FBE9: return [half(x + w, y + h / 2, start: pi / 2, filled: true)] // 🯩
        case 0x1FBEA: return [half(x + w / 2, y + h, start: pi, filled: true)]   // 🯪
        case 0x1FBEB: return [half(x, y + h / 2, start: -pi / 2, filled: true)]  // 🯫
        case 0x1FBEC: return [quarter(Offset(x + w, y), start: pi / 2)]          // 🯬
        case 0x1FBED: return [quarter(Offset(x, y + h), start: -pi / 2)]         // 🯭
        case 0x1FBEE: return [quarter(Offset(x + w, y + h), start: pi)]          // 🯮
        default:      return [quarter(Offset(x, y), start: 0)]                   // 🯯
        }
    }

    // MARK: - Supplement combos and separated mosaics

    /// U+1CC1B–1CC1E and U+1CE16–1CE19: a full light line with an
    /// edge-hugging half bar — chart plumbing for old character sets.
    private static func lineBarOps(_ scalar: UInt32,
                                   x: Double, y: Double, w: Double, h: Double,
                                   scale: Double) -> [BoxPlanOp] {
        let t = thickness(1, scale)
        var ops: [BoxPlanOp] = []
        switch scalar {
        case 0x1CC1B, 0x1CC1C:                           // 𜰛𜰜 ─ + right edge bar
            ops = armOps(BoxArms(left: 1, right: 1), x: x, y: y, w: w, h: h, scale: scale)
            ops.append(.fill(scalar == 0x1CC1B
                ? Rect.fromLTRB(x + w - t, y, x + w, y + h / 2)
                : Rect.fromLTRB(x + w - t, y + h / 2, x + w, y + h)))
        case 0x1CC1D:                                    // 𜰝 top bar + upper left bar
            ops = [.fill(Rect.fromLTRB(x, y, x + w, y + t)),
                   .fill(Rect.fromLTRB(x, y, x + t, y + h / 2))]
        case 0x1CC1E:                                    // 𜰞 bottom bar + lower left bar
            ops = [.fill(Rect.fromLTRB(x, y + h - t, x + w, y + h)),
                   .fill(Rect.fromLTRB(x, y + h / 2, x + t, y + h))]
        default:                                         // 𜸖𜸗𜸘𜸙 │ + edge bar
            ops = armOps(BoxArms(up: 1, down: 1), x: x, y: y, w: w, h: h, scale: scale)
            switch scalar {
            case 0x1CE16: ops.append(.fill(Rect.fromLTRB(x + w / 2, y, x + w, y + t)))
            case 0x1CE17: ops.append(.fill(Rect.fromLTRB(x + w / 2, y + h - t, x + w, y + h)))
            case 0x1CE18: ops.append(.fill(Rect.fromLTRB(x, y, x + w / 2, y + t)))
            default:      ops.append(.fill(Rect.fromLTRB(x, y + h - t, x + w / 2, y + h)))
            }
        }
        return ops
    }

    /// Separated quadrants U+1CC21–1CC2F and separated sextants
    /// U+1CE51–1CE8F: the mosaic cells inset by a gutter — a twelfth of the
    /// cell width outside, two gutters between — so adjacent glyphs read as
    /// distinct dots. Masks are the codepoint offset, no skips.
    private static func separatedOps(_ scalar: UInt32,
                                     x: Double, y: Double,
                                     w: Double, h: Double) -> [BoxPlanOp] {
        let g = w / 12
        let cw = (w - 4 * g) / 2
        let xs = [x + g, x + g + cw + 2 * g]
        var ops: [BoxPlanOp] = []
        if scalar <= 0x1CC2F {                           // quadrants, 2 rows
            let mask = scalar - 0x1CC20
            let ch = (h - 4 * g) / 2
            let ys = [y + g, y + g + ch + 2 * g]
            for bit in 0..<4 where mask & (1 << bit) != 0 {
                ops.append(.fill(Rect.fromLTWH(xs[bit % 2], ys[bit / 2], cw, ch)))
            }
        } else {                                         // sextants, 3 rows
            let mask = scalar - 0x1CE50
            let ch = (h - 6 * g) / 3
            let ys = [y + g, y + g + ch + 2 * g, y + g + 2 * (ch + 2 * g)]
            for bit in 0..<6 where mask & (1 << bit) != 0 {
                ops.append(.fill(Rect.fromLTWH(xs[bit % 2], ys[bit / 2], cw, ch)))
            }
        }
        return ops
    }

    /// U+1CC30–1CC3F and the white circle/ellipse pairs: stroked quarter
    /// arcs of circles spanning one or two cells, so a 2x2 block of the
    /// twelfth pieces composes one large circle across cells.
    private static func circlePieceOps(_ scalar: UInt32,
                                       x: Double, y: Double, w: Double, h: Double,
                                       scale: Double) -> [BoxPlanOp] {
        let t = thickness(1, scale)
        let pi = Double.pi
        // (px, py): this cell's offset into the circle's bounding box, in
        // cells. (cw, ch): the circle's RADIUS in cells — a "twelfth circle"
        // piece belongs to a circle spanning 2·cw x 2·ch cells, whose ring
        // passes through twelve boundary cells. Quarter per corner: tl is
        // the arc from the box's left edge to its top.
        func piece(_ px: Double, _ py: Double, _ cw: Double, _ ch: Double,
                   _ corner: String) -> BoxPlanOp {
            let ox = x - px * w, oy = y - py * h
            let oval = Rect.fromLTRB(ox + t / 2, oy + t / 2,
                                     ox + 2 * cw * w - t / 2, oy + 2 * ch * h - t / 2)
            let (start, sweep): (Double, Double)
            switch corner {
            case "tl": (start, sweep) = (pi, pi / 2)     // left → top
            case "tr": (start, sweep) = (3 * pi / 2, pi / 2)
            case "bl": (start, sweep) = (pi / 2, pi / 2)
            default:   (start, sweep) = (0, pi / 2)      // br
            }
            let cx = (oval.left + oval.right) / 2, cy = (oval.top + oval.bottom) / 2
            let rx = (oval.right - oval.left) / 2, ry = (oval.bottom - oval.top) / 2
            return .stroke(from: Offset(cx + rx * cos(start), cy + ry * sin(start)),
                           segments: [.arc(oval: oval, start: start, sweep: sweep)],
                           thickness: t)
        }
        switch scalar {
        case 0x1CC30: return [piece(0, 0, 2, 2, "tl")]
        case 0x1CC31: return [piece(1, 0, 2, 2, "tl")]
        case 0x1CC32: return [piece(2, 0, 2, 2, "tr")]
        case 0x1CC33: return [piece(3, 0, 2, 2, "tr")]
        case 0x1CC34: return [piece(0, 1, 2, 2, "tl")]
        case 0x1CC35: return [piece(0, 0, 1, 1, "tl")]
        case 0x1CC36: return [piece(1, 0, 1, 1, "tr")]
        case 0x1CC37: return [piece(3, 1, 2, 2, "tr")]
        case 0x1CC38: return [piece(0, 2, 2, 2, "bl")]
        case 0x1CC39: return [piece(0, 1, 1, 1, "bl")]
        case 0x1CC3A: return [piece(1, 1, 1, 1, "br")]
        case 0x1CC3B: return [piece(3, 2, 2, 2, "br")]
        case 0x1CC3C: return [piece(0, 3, 2, 2, "bl")]
        case 0x1CC3D: return [piece(1, 3, 2, 2, "bl")]
        case 0x1CC3E: return [piece(2, 3, 2, 2, "br")]
        case 0x1CC3F: return [piece(3, 3, 2, 2, "br")]
        case 0x1CE00:                                    // 𜸀 left+right white circles
            return circleOps(0x1FBE3, x: x, y: y, w: w, h: h, scale: scale)
                + circleOps(0x1FBE1, x: x, y: y, w: w, h: h, scale: scale)
        case 0x1CE01:                                    // 𜸁 top+bottom white circles
            return circleOps(0x1FBE0, x: x, y: y, w: w, h: h, scale: scale)
                + circleOps(0x1FBE2, x: x, y: y, w: w, h: h, scale: scale)
        case 0x1CE0B, 0x1CE0C:                           // 𜸋𜸌 half white ellipses
            let oval = Rect.fromLTRB(x + t / 2, y + t / 2,
                                     x + w - t / 2, y + h - t / 2)
            let start = scalar == 0x1CE0B ? pi / 2 : -pi / 2
            let cx = (oval.left + oval.right) / 2, cy = (oval.top + oval.bottom) / 2
            let rx = (oval.right - oval.left) / 2, ry = (oval.bottom - oval.top) / 2
            return [.stroke(from: Offset(cx + rx * cos(start), cy + ry * sin(start)),
                            segments: [.arc(oval: oval, start: start, sweep: pi)],
                            thickness: t)]
        default:
            return []
        }
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
                                         .line(to: Offset(x, y + h))],
                              alpha: 1)]
        case 0xE0B1:                                     // right chevron
            return [.stroke(from: Offset(x, y),
                            segments: [.line(to: Offset(x + w, midY)),
                                       .line(to: Offset(x, y + h))],
                            thickness: t)]
        case 0xE0B2:                                     // solid left triangle
            return [.fillPath(from: Offset(x + w, y),
                              segments: [.line(to: Offset(x, midY)),
                                         .line(to: Offset(x + w, y + h))],
                              alpha: 1)]
        case 0xE0B3:                                     // left chevron
            return [.stroke(from: Offset(x + w, y),
                            segments: [.line(to: Offset(x, midY)),
                                       .line(to: Offset(x + w, y + h))],
                            thickness: t)]
        case 0xE0B4:                                     // solid right half-circle
            return [.fillPath(from: Offset(x, y),
                              segments: [.arc(oval: Rect.fromLTRB(x - w, y, x + w, y + h),
                                              start: -pi / 2, sweep: pi)],
                              alpha: 1)]
        case 0xE0B5:                                     // right half-circle line
            return [.stroke(from: Offset(x, y),
                            segments: [.arc(oval: Rect.fromLTRB(x - w, y, x + w, y + h),
                                            start: -pi / 2, sweep: pi)],
                            thickness: t)]
        case 0xE0B6:                                     // solid left half-circle
            return [.fillPath(from: Offset(x + w, y),
                              segments: [.arc(oval: Rect.fromLTRB(x, y, x + w + w, y + h),
                                              start: -pi / 2, sweep: -pi)],
                              alpha: 1)]
        case 0xE0B7:                                     // left half-circle line
            return [.stroke(from: Offset(x + w, y),
                            segments: [.arc(oval: Rect.fromLTRB(x, y, x + w + w, y + h),
                                            start: -pi / 2, sweep: -pi)],
                            thickness: t)]
        default:
            // E0B8–E0BF: the corner slants — a half-cell triangle hanging
            // off one bottom or top edge, and the matching bare diagonal.
            let tl = Offset(x, y), tr = Offset(x + w, y)
            let bl = Offset(x, y + h), br = Offset(x + w, y + h)
            func solid(_ a: Offset, _ b: Offset, _ c: Offset) -> [BoxPlanOp] {
                [.fillPath(from: a, segments: [.line(to: b), .line(to: c)], alpha: 1)]
            }
            func slant(_ a: Offset, _ b: Offset) -> [BoxPlanOp] {
                [.stroke(from: a, segments: [.line(to: b)], thickness: t)]
            }
            switch scalar {
            case 0xE0B8: return solid(tl, bl, br)        // lower-left solid
            case 0xE0B9: return slant(tl, br)            // its diagonal
            case 0xE0BA: return solid(bl, br, tr)        // lower-right solid
            case 0xE0BB: return slant(bl, tr)            // its diagonal
            case 0xE0BC: return solid(bl, tl, tr)        // upper-left solid
            case 0xE0BD: return slant(bl, tr)            // its diagonal
            case 0xE0BE: return solid(tl, tr, br)        // upper-right solid
            default:     return slant(tl, br)            // E0BF, its diagonal
            }
        }
    }

    // MARK: - Branch drawing

    /// U+F5D0–F60D, the branch-drawing set kitty specified for git graphs
    /// (implemented from the published character-set description): centre
    /// lines, fading lines, centre-bend arcs — the rounded corners' own
    /// geometry — and commit nodes: a centred circle, filled or open, with
    /// line stubs from the cell edges to its rim.
    private static func branchOps(_ scalar: UInt32,
                                  x: Double, y: Double, w: Double, h: Double,
                                  scale: Double) -> [BoxPlanOp] {
        let t = thickness(1, scale)
        func lines(_ a: BoxArms) -> [BoxPlanOp] {
            armOps(a, x: x, y: y, w: w, h: h, scale: scale)
        }
        func bend(_ corner: UInt32) -> [BoxPlanOp] {
            roundedOps(corner, x: x, y: y, w: w, h: h, scale: scale)
        }
        // A line fading toward one edge: the canonical band in four
        // segments of descending ink.
        func fading(horizontal: Bool, towardEnd: Bool) -> [BoxPlanOp] {
            var ops: [BoxPlanOp] = []
            for i in 0..<4 {
                let along = towardEnd ? i : 3 - i
                let alpha = 1.0 - (Double(along) + 0.5) / 4
                if horizontal {
                    let by = y + snap((h - t) / 2, scale)
                    ops.append(.shade(Rect.fromLTRB(x + w * Double(i) / 4, by,
                                                    x + w * Double(i + 1) / 4, by + t),
                                      alpha))
                } else {
                    let bx = x + snap((w - t) / 2, scale)
                    ops.append(.shade(Rect.fromLTRB(bx, y + h * Double(i) / 4,
                                                    bx + t, y + h * Double(i + 1) / 4),
                                      alpha))
                }
            }
            return ops
        }
        // A commit node: circle at the band centre, radius to the nearest
        // edge, with stubs from the edges to the rim.
        func node(_ mask: UInt32) -> [BoxPlanOp] {
            let bx = x + snap((w - t) / 2, scale) + t / 2
            let by = y + snap((h - t) / 2, scale) + t / 2
            let r = min(min(bx - x, by - y), min(x + w - bx, y + h - by))
            var ops: [BoxPlanOp] = []
            if mask & 1 != 0 {                           // up stub
                ops.append(.fill(Rect.fromLTRB(bx - t / 2, y, bx + t / 2, by - r + t / 2)))
            }
            if mask & 2 != 0 {                           // right stub
                ops.append(.fill(Rect.fromLTRB(bx + r - t / 2, by - t / 2, x + w, by + t / 2)))
            }
            if mask & 4 != 0 {                           // down stub
                ops.append(.fill(Rect.fromLTRB(bx - t / 2, by + r - t / 2, bx + t / 2, y + h)))
            }
            if mask & 8 != 0 {                           // left stub
                ops.append(.fill(Rect.fromLTRB(x, by - t / 2, bx - r + t / 2, by + t / 2)))
            }
            if mask & 0x10 != 0 {
                ops.append(.disc(Offset(bx, by), r))
            } else {
                let oval = Rect.fromLTRB(bx - r + t / 2, by - r + t / 2,
                                         bx + r - t / 2, by + r - t / 2)
                ops.append(.stroke(from: Offset(bx + r - t / 2, by),
                                   segments: [.arc(oval: oval, start: 0, sweep: .pi),
                                              .arc(oval: oval, start: .pi, sweep: .pi)],
                                   thickness: t))
            }
            return ops
        }
        switch scalar {
        case 0xF5D0: return lines(BoxArms(left: 1, right: 1))
        case 0xF5D1: return lines(BoxArms(up: 1, down: 1))
        case 0xF5D2: return fading(horizontal: true, towardEnd: true)
        case 0xF5D3: return fading(horizontal: true, towardEnd: false)
        case 0xF5D4: return fading(horizontal: false, towardEnd: true)
        case 0xF5D5: return fading(horizontal: false, towardEnd: false)
        case 0xF5D6: return bend(0x256D)                 //  ╭, down+right
        case 0xF5D7: return bend(0x256E)                 //  ╮, down+left
        case 0xF5D8: return bend(0x2570)                 //  ╰, up+right
        case 0xF5D9: return bend(0x256F)                 //  ╯, up+left
        case 0xF5DA: return lines(BoxArms(up: 1, down: 1)) + bend(0x2570)
        case 0xF5DB: return lines(BoxArms(up: 1, down: 1)) + bend(0x256D)
        case 0xF5DC: return bend(0x2570) + bend(0x256D)
        case 0xF5DD: return lines(BoxArms(up: 1, down: 1)) + bend(0x256F)
        case 0xF5DE: return lines(BoxArms(up: 1, down: 1)) + bend(0x256E)
        case 0xF5DF: return bend(0x256F) + bend(0x256E)
        case 0xF5E0: return bend(0x256E) + lines(BoxArms(left: 1, right: 1))
        case 0xF5E1: return bend(0x256D) + lines(BoxArms(left: 1, right: 1))
        case 0xF5E2: return bend(0x256D) + bend(0x256E)
        case 0xF5E3: return bend(0x256F) + lines(BoxArms(left: 1, right: 1))
        case 0xF5E4: return bend(0x2570) + lines(BoxArms(left: 1, right: 1))
        case 0xF5E5: return bend(0x2570) + bend(0x256F)
        case 0xF5E6: return lines(BoxArms(up: 1, down: 1)) + bend(0x256F) + bend(0x2570)
        case 0xF5E7: return lines(BoxArms(up: 1, down: 1)) + bend(0x256E) + bend(0x256D)
        case 0xF5E8: return lines(BoxArms(left: 1, right: 1)) + bend(0x256E) + bend(0x256F)
        case 0xF5E9: return lines(BoxArms(left: 1, right: 1)) + bend(0x2570) + bend(0x256D)
        case 0xF5EA: return lines(BoxArms(up: 1, down: 1)) + bend(0x256F) + bend(0x256D)
        case 0xF5EB: return lines(BoxArms(up: 1, down: 1)) + bend(0x2570) + bend(0x256E)
        case 0xF5EC: return lines(BoxArms(left: 1, right: 1)) + bend(0x256F) + bend(0x256D)
        case 0xF5ED: return lines(BoxArms(left: 1, right: 1)) + bend(0x2570) + bend(0x256E)
        case 0xF5EE: return node(0x10)
        case 0xF5EF: return node(0)
        default:
            // F5F0–F60D: nodes with stubs, filled/open alternating.
            // Bits: 1 up, 2 right, 4 down, 8 left, 0x10 filled.
            let masks: [UInt32] = [
                0x12, 0x02, 0x18, 0x08, 0x1A, 0x0A, 0x14, 0x04, 0x11, 0x01,
                0x15, 0x05, 0x16, 0x06, 0x1C, 0x0C, 0x13, 0x03, 0x19, 0x09,
                0x17, 0x07, 0x1D, 0x0D, 0x1E, 0x0E, 0x1B, 0x0B, 0x1F, 0x0F,
            ]
            return node(masks[Int(scalar - 0xF5F0)])
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
