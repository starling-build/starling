// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Excel's icon sets, drawn as shapes: arrows, traffic lights, signs,
// symbols, flags, red-to-black, ratings and quarters. Index 0 is the
// lowest icon of the set (a red down arrow), the last the highest.

import Flutter
import FlutterSwiftBridge
import Foundation

enum IconSets {
    private static let red = Color(0xFFE0453A), yellow = Color(0xFFF2B623), green = Color(0xFF3FAE5A)
    private static let gray = Color(0xFF8C8C8C), black = Color(0xFF262626), pink = Color(0xFFF4A6A0)

    /// Draw icon `index` of `set` in the square `r`.
    static func paint(_ set: String, _ index: Int, _ canvas: any Canvas, in r: Rect) {
        let p = Paint()
        p.style = .fill
        p.isAntiAlias = true
        let n = Int(set.prefix(1)) ?? 3
        let i = max(0, min(n - 1, index))
        let cx = r.center.dx, cy = r.center.dy, s = r.width / 2
        func circle(_ c: Color) { p.color = c; canvas.drawCircle(Offset(cx, cy), s * 0.85, p) }
        switch set {
        case "3Arrows", "3ArrowsGray", "4Arrows", "4ArrowsGray", "5Arrows", "5ArrowsGray":
            // Angles from down (−90°) to up (+90°), evenly over the set.
            let angle = -Double.pi / 2 + Double.pi * Double(i) / Double(n - 1)
            let colors: [Color] = n == 3 ? [red, yellow, green] : n == 4 ? [red, yellow, yellow, green] : [red, yellow, yellow, yellow, green]
            p.color = set.hasSuffix("Gray") ? gray : colors[i]
            _arrow(canvas, center: Offset(cx, cy), size: s, angle: angle, p)
        case "3TrafficLights1", "3TrafficLights2":
            if set == "3TrafficLights2" { p.color = black; canvas.drawCircle(Offset(cx, cy), s, p) }
            circle([red, yellow, green][i])
        case "4TrafficLights":
            circle([black, red, yellow, green][i])
        case "4RedToBlack":
            circle([black, gray, pink, red][i])
        case "3Signs":
            p.color = [red, yellow, green][i]
            let path = Path()
            switch i {
            case 0: path.moveTo(cx, cy - s); path.lineTo(cx + s, cy); path.lineTo(cx, cy + s); path.lineTo(cx - s, cy)   // diamond
            case 1: path.moveTo(cx, cy - s); path.lineTo(cx + s, cy + s * 0.8); path.lineTo(cx - s, cy + s * 0.8)        // triangle
            default: path.addOval(Rect.fromLTWH(cx - s * 0.85, cy - s * 0.85, s * 1.7, s * 1.7))
            }
            path.close()
            canvas.drawPath(path, p)
        case "3Symbols", "3Symbols2":
            let c = [red, yellow, green][i]
            if set == "3Symbols" { circle(c) }
            let stroke = Paint()
            stroke.style = .stroke
            stroke.isAntiAlias = true
            stroke.strokeWidth = max(1.2, s * 0.28)
            stroke.color = set == "3Symbols" ? Color(0xFFFFFFFF) : c
            let k = s * 0.45
            switch i {
            case 0:
                canvas.drawLine(Offset(cx - k, cy - k), Offset(cx + k, cy + k), stroke)
                canvas.drawLine(Offset(cx + k, cy - k), Offset(cx - k, cy + k), stroke)
            case 1:
                canvas.drawLine(Offset(cx, cy - k * 1.2), Offset(cx, cy + k * 0.3), stroke)
                canvas.drawLine(Offset(cx, cy + k * 0.8), Offset(cx, cy + k * 0.95), stroke)
            default:
                let tick = Path()
                tick.moveTo(cx - k, cy); tick.lineTo(cx - k * 0.2, cy + k * 0.8); tick.lineTo(cx + k, cy - k * 0.8)
                canvas.drawPath(tick, stroke)
            }
        case "3Flags":
            let pole = Paint()
            pole.style = .stroke
            pole.strokeWidth = max(1, s * 0.15)
            pole.color = black
            canvas.drawLine(Offset(cx - s * 0.6, cy - s), Offset(cx - s * 0.6, cy + s), pole)
            p.color = [red, yellow, green][i]
            let flag = Path()
            flag.moveTo(cx - s * 0.6, cy - s); flag.lineTo(cx + s, cy - s * 0.5); flag.lineTo(cx - s * 0.6, cy)
            flag.close()
            canvas.drawPath(flag, p)
        case "4Rating", "5Rating":
            // Bars rising left to right; as many filled as the rating.
            let bars = n - 1, w = r.width / Double(bars) * 0.7
            for b in 0 ..< bars {
                let h = r.height * Double(b + 1) / Double(bars)
                p.color = b < i ? Color(0xFF3B6FB6) : Color(0xFFD0D7E2)
                canvas.drawRect(Rect.fromLTWH(r.left + Double(b) * r.width / Double(bars), r.bottom - h, w, h), p)
            }
        case "5Quarters":
            let ring = Paint()
            ring.style = .stroke
            ring.strokeWidth = max(1, s * 0.15)
            ring.color = black
            canvas.drawCircle(Offset(cx, cy), s * 0.85, ring)
            if i > 0 {
                p.color = black
                let wedge = Path()
                wedge.moveTo(cx, cy)
                wedge.arcTo(Rect.fromLTWH(cx - s * 0.85, cy - s * 0.85, s * 1.7, s * 1.7), -Double.pi / 2, Double.pi / 2 * Double(i), false)
                wedge.close()
                canvas.drawPath(wedge, p)
            }
        default:
            circle([red, yellow, green, green, green][min(i, 4)])
        }
    }

    /// A block arrow pointing at `angle` (0 = right, π/2 = up).
    private static func _arrow(_ canvas: any Canvas, center c: Offset, size s: Double, angle: Double, _ p: Paint) {
        // In arrow space (pointing right), then rotated; y is up there, down on screen.
        let pts: [(Double, Double)] = [(-s, -s * 0.28), (s * 0.1, -s * 0.28), (s * 0.1, -s * 0.75), (s, 0),
                                       (s * 0.1, s * 0.75), (s * 0.1, s * 0.28), (-s, s * 0.28)]
        let cosA = cos(angle), sinA = sin(angle)
        let path = Path()
        for (k, (x, y)) in pts.enumerated() {
            let px = c.dx + x * cosA - y * sinA
            let py = c.dy - (x * sinA + y * cosA)
            if k == 0 { path.moveTo(px, py) } else { path.lineTo(px, py) }
        }
        path.close()
        canvas.drawPath(path, p)
    }
}
