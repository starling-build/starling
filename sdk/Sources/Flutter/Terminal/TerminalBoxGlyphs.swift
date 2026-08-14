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
// SCOPE. The uniform-weight box characters (all arms light, or all heavy),
// the half-lines, the rounded corners, the pure double-line set, and the
// block elements — eighths, quadrants, and the three shades. That is
// essentially all of what real terminal output uses: Claude Code's welcome
// frame is rounded corners plus light sides, and its logo is quadrants,
// which is what pulled the corners and quadrants in here (the font-drawn
// corner visibly failed to meet the synthesized side). What still comes
// from the font: the dashed variants and the mixed light/heavy joins,
// where the font is correct and merely soft. Adding them is a matter of
// extending `arms(for:)`.

import Foundation
import FlutterSwiftBridge

/// How a box character reaches each edge of its cell.
struct BoxArms {
    var up = 0, down = 0, left = 0, right = 0   // 0 none, 1 light, 2 heavy
    var any: Bool { up + down + left + right > 0 }
}

enum TerminalBoxGlyphs {

    /// True for every scalar this file can draw. Checked per cell, so it is a
    /// range test and a table lookup, not a dictionary.
    static func handles(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x2500...0x254B: return arms(for: scalar) != nil
        case 0x2550, 0x2551, 0x2554, 0x2557, 0x255A, 0x255D,
             0x2560, 0x2563, 0x2566, 0x2569, 0x256C: return true
        case 0x256D...0x2570: return true
        case 0x2574...0x257F: return arms(for: scalar) != nil
        case 0x2580...0x259F: return true
        default: return false
        }
    }

    /// Draw one cell. `x`/`y` are the cell's top-left in logical units.
    static func draw(_ canvas: any Canvas, scalar: UInt32,
                     x: Double, y: Double, w: Double, h: Double,
                     color: UInt32, scale: Double) {
        let paint = Paint()
        paint.color = Color(Int(color))

        if let a = arms(for: scalar) {
            drawArms(canvas, a, x: x, y: y, w: w, h: h, paint: paint, scale: scale)
            return
        }
        if (0x256D...0x2570).contains(scalar) {
            drawRounded(canvas, scalar: scalar, x: x, y: y, w: w, h: h,
                        paint: paint, scale: scale)
            return
        }
        if (0x2550...0x256C).contains(scalar) {
            drawDouble(canvas, scalar: scalar, x: x, y: y, w: w, h: h,
                       paint: paint, scale: scale)
            return
        }
        drawBlock(canvas, scalar: scalar, x: x, y: y, w: w, h: h,
                  paint: paint, color: color)
    }

    // MARK: - Lines

    /// Line thickness in logical units: one device pixel per unit of scale for
    /// a light line, doubled for a heavy one, so a line is always a whole
    /// number of device pixels and never lands half-lit.
    private static func thickness(_ weight: Int, _ scale: Double) -> Double {
        let light = max(1.0, (scale).rounded())
        return (weight >= 2 ? light * 2 : light) / scale
    }

    private static func drawArms(_ canvas: any Canvas, _ a: BoxArms,
                                 x: Double, y: Double, w: Double, h: Double,
                                 paint: Paint, scale: Double) {
        // The centre bar is as thick as the heaviest arm meeting here, so a
        // light arm joining a heavy one does not leave a notch at the join.
        let heaviest = max(max(a.up, a.down), max(a.left, a.right))
        let tv = thickness(heaviest, scale)          // horizontal bar height
        let th = thickness(heaviest, scale)          // vertical bar width
        // Centre the bars on whole device pixels; an odd thickness on an even
        // centre is what makes a line look like two grey rows instead of one.
        let cy = y + snap((h - tv) / 2, scale)
        let cx = x + snap((w - th) / 2, scale)

        // Each arm runs from the cell edge to the far side of the centre, so
        // opposite arms overlap in the middle and leave no gap.
        if a.left > 0 {
            canvas.drawRect(Rect.fromLTRB(x, cy, cx + th, cy + thickness(a.left, scale)), paint)
        }
        if a.right > 0 {
            canvas.drawRect(Rect.fromLTRB(cx, cy, x + w, cy + thickness(a.right, scale)), paint)
        }
        if a.up > 0 {
            canvas.drawRect(Rect.fromLTRB(cx, y, cx + thickness(a.up, scale), cy + tv), paint)
        }
        if a.down > 0 {
            canvas.drawRect(Rect.fromLTRB(cx, cy, cx + thickness(a.down, scale), y + h), paint)
        }
    }

    private static func snap(_ v: Double, _ scale: Double) -> Double {
        (v * scale).rounded() / scale
    }

    // MARK: - Rounded corners

    /// ╭╮╯╰ as a stroked path: two straight runs meeting in a quarter arc,
    /// with the stroke centred on the same lines the rect arms occupy, so a
    /// rounded corner continues seamlessly into a `│` above or a `─` beside
    /// it — the seam between the font's corner and our synthesized sides is
    /// what forced these in here.
    private static func drawRounded(_ canvas: any Canvas, scalar: UInt32,
                                    x: Double, y: Double, w: Double, h: Double,
                                    paint: Paint, scale: Double) {
        let th = thickness(1, scale)
        // The rect arms put a bar's LEADING edge at cx/cy; the stroke is
        // centred, so the centreline sits half a thickness further in.
        let bx = x + snap((w - th) / 2, scale) + th / 2
        let by = y + snap((h - th) / 2, scale) + th / 2
        let r = max(th, min(w, h) / 2 - th / 2)

        let stroke = Paint()
        stroke.color = paint.color
        stroke.style = .stroke
        stroke.strokeWidth = th

        let path = Path()
        let pi = Double.pi
        switch scalar {
        case 0x256D:                                     // ╭ down + right
            path.moveTo(bx, y + h)
            path.lineTo(bx, by + r)
            path.arcTo(Rect.fromLTRB(bx, by, bx + 2 * r, by + 2 * r),
                       pi, pi / 2, false)
            path.lineTo(x + w, by)
        case 0x256E:                                     // ╮ down + left
            path.moveTo(bx, y + h)
            path.lineTo(bx, by + r)
            path.arcTo(Rect.fromLTRB(bx - 2 * r, by, bx, by + 2 * r),
                       0, -pi / 2, false)
            path.lineTo(x, by)
        case 0x256F:                                     // ╯ up + left
            path.moveTo(bx, y)
            path.lineTo(bx, by - r)
            path.arcTo(Rect.fromLTRB(bx - 2 * r, by - 2 * r, bx, by),
                       0, pi / 2, false)
            path.lineTo(x, by)
        default:                                         // ╰ up + right
            path.moveTo(bx, y)
            path.lineTo(bx, by - r)
            path.arcTo(Rect.fromLTRB(bx, by - 2 * r, bx + 2 * r, by),
                       pi, -pi / 2, false)
            path.lineTo(x + w, by)
        }
        canvas.drawPath(path, stroke)
    }

    // MARK: - Doubles

    /// The pure double-line set: two light bars a light-line's width apart,
    /// centred as a pair on the same lines the single bars use. The mixed
    /// single/double hybrids (╒╓…╫) stay with the font.
    private static func drawDouble(_ canvas: any Canvas, scalar: UInt32,
                                   x: Double, y: Double, w: Double, h: Double,
                                   paint: Paint, scale: Double) {
        let th = thickness(1, scale)
        let bx = x + snap((w - th) / 2, scale) + th / 2
        let by = y + snap((h - th) / 2, scale) + th / 2
        let d = th                                       // pair offset
        let vo = bx - d, vi = bx + d                     // vertical centres
        let ho = by - d, hi = by + d                     // horizontal centres
        func hbar(_ cy: Double, _ x0: Double, _ x1: Double) {
            canvas.drawRect(Rect.fromLTRB(x0, cy - th / 2, x1, cy + th / 2), paint)
        }
        func vbar(_ cx: Double, _ y0: Double, _ y1: Double) {
            canvas.drawRect(Rect.fromLTRB(cx - th / 2, y0, cx + th / 2, y1), paint)
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
        default:                                         // ╬
            vbar(vo, y, ho + th / 2); vbar(vo, hi - th / 2, y + h)
            vbar(vi, y, ho + th / 2); vbar(vi, hi - th / 2, y + h)
            hbar(ho, x, vo + th / 2); hbar(ho, vi - th / 2, x + w)
            hbar(hi, x, vo + th / 2); hbar(hi, vi - th / 2, x + w)
        }
    }

    // MARK: - Blocks and shades

    private static func drawBlock(_ canvas: any Canvas, scalar: UInt32,
                                  x: Double, y: Double, w: Double, h: Double,
                                  paint: Paint, color: UInt32) {
        switch scalar {
        case 0x2588:                                     // █ full
            canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint)
        case 0x2580:                                     // ▀ upper half
            canvas.drawRect(Rect.fromLTWH(x, y, w, h / 2), paint)
        case 0x2584:                                     // ▄ lower half
            canvas.drawRect(Rect.fromLTWH(x, y + h / 2, w, h / 2), paint)
        case 0x258C:                                     // ▌ left half
            canvas.drawRect(Rect.fromLTWH(x, y, w / 2, h), paint)
        case 0x2590:                                     // ▐ right half
            canvas.drawRect(Rect.fromLTWH(x + w / 2, y, w / 2, h), paint)
        case 0x2581...0x2587:                            // ▁▂▃▄▅▆▇ lower eighths
            let n = Double(scalar - 0x2580)              // 1...7 eighths tall
            let fh = h * n / 8
            canvas.drawRect(Rect.fromLTWH(x, y + h - fh, w, fh), paint)
        case 0x2589...0x258F:                            // ▉▊▋▌▍▎▏ left eighths
            let n = Double(0x2590 - scalar)              // 7...1 eighths wide
            canvas.drawRect(Rect.fromLTWH(x, y, w * n / 8, h), paint)
        case 0x2594:                                     // ▔ upper eighth
            canvas.drawRect(Rect.fromLTWH(x, y, w, h / 8), paint)
        case 0x2595:                                     // ▕ right eighth
            canvas.drawRect(Rect.fromLTRB(x + w * 7 / 8, y, x + w, y + h), paint)
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
            if mask & 1 != 0 { canvas.drawRect(Rect.fromLTRB(x, y, xm, ym), paint) }
            if mask & 2 != 0 { canvas.drawRect(Rect.fromLTRB(xm, y, x + w, ym), paint) }
            if mask & 4 != 0 { canvas.drawRect(Rect.fromLTRB(x, ym, xm, y + h), paint) }
            if mask & 8 != 0 { canvas.drawRect(Rect.fromLTRB(xm, ym, x + w, y + h), paint) }
        case 0x2591, 0x2592, 0x2593:                     // ░▒▓ shades
            // A shade is a fraction of ink, and as a solid fill at that alpha
            // it is both closer to the intent and steadier than the font's
            // dither pattern, which beats against the pixel grid.
            let frac = scalar == 0x2591 ? 0.25 : (scalar == 0x2592 ? 0.5 : 0.75)
            let a = Double((color >> 24) & 0xFF) * frac
            paint.color = Color(Int((UInt32(a.rounded()) << 24) | (color & 0x00FF_FFFF)))
            canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint)
        default:
            break
        }
    }

    // MARK: - The arm table

    /// Which arms a box character extends, for the uniform-weight subset.
    /// nil means "not ours" — the font draws it.
    private static func arms(for scalar: UInt32) -> BoxArms? {
        let L = 1, H = 2
        switch scalar {
        case 0x2500: return BoxArms(left: L, right: L)          // ─
        case 0x2501: return BoxArms(left: H, right: H)          // ━
        case 0x2502: return BoxArms(up: L, down: L)             // │
        case 0x2503: return BoxArms(up: H, down: H)             // ┃
        case 0x250C: return BoxArms(down: L, right: L)          // ┌
        case 0x250F: return BoxArms(down: H, right: H)          // ┏
        case 0x2510: return BoxArms(down: L, left: L)           // ┐
        case 0x2513: return BoxArms(down: H, left: H)           // ┓
        case 0x2514: return BoxArms(up: L, right: L)            // └
        case 0x2517: return BoxArms(up: H, right: H)            // ┗
        case 0x2518: return BoxArms(up: L, left: L)             // ┘
        case 0x251B: return BoxArms(up: H, left: H)             // ┛
        case 0x251C: return BoxArms(up: L, down: L, right: L)   // ├
        case 0x2523: return BoxArms(up: H, down: H, right: H)   // ┣
        case 0x2524: return BoxArms(up: L, down: L, left: L)    // ┤
        case 0x252B: return BoxArms(up: H, down: H, left: H)    // ┫
        case 0x252C: return BoxArms(down: L, left: L, right: L) // ┬
        case 0x2533: return BoxArms(down: H, left: H, right: H) // ┳
        case 0x2534: return BoxArms(up: L, left: L, right: L)   // ┴
        case 0x253B: return BoxArms(up: H, left: H, right: H)   // ┻
        case 0x253C: return BoxArms(up: L, down: L, left: L, right: L)  // ┼
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
