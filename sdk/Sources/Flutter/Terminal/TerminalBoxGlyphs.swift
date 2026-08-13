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
// the block elements including the eighths, and the three shades. That is
// essentially all of what real terminal output uses. The rest of U+2500's
// block — dashes, doubles, rounded corners, and the mixed light/heavy joins —
// keeps coming from the font, where it is correct and merely soft. Adding
// them here is a matter of extending `arms(for:)`.

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
        case 0x2580...0x2593: return true
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
        default: return nil
        }
    }
}
