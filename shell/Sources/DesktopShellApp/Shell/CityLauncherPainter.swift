// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Cream enamel and bronze trim, with four inset Painted-Lady colors.
/// Code-native geometry stays crisp at every display scale.
final class CityLauncherPainter: CustomPainter {
    let hovered: Bool
    let pressed: Bool

    init(hovered: Bool, pressed: Bool) {
        self.hovered = hovered
        self.pressed = pressed
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        canvas.save()
        canvas.scale(size.width / 52, size.height / 52)
        if pressed { canvas.translate(0, 1) }
        let paint = Paint()
        paint.color = Color(0xFF574028)
        canvas.drawCircle(Offset(26, 26), 25, paint)
        paint.color = hovered ? Color(0xFFC6A572) : Color(0xFFA68A5F)
        canvas.drawCircle(Offset(26, 25.5), 23.5, paint)
        paint.color = pressed ? Color(0xFFD4C7AB)
            : (hovered ? Color(0xFFFFF3D7) : Color(0xFFE8DFC9))
        canvas.drawCircle(Offset(26, 26), 22, paint)

        let colors = [Color(0xFF52766A), Color(0xFFAF604D),
                      Color(0xFFAA874B), Color(0xFF628499)]
        for i in 0..<4 {
            let x = 14.0 + Double(i % 2) * 14
            let y = 14.0 + Double(i / 2) * 14
            // A recessed bronze outline and a fine light lower edge.
            paint.color = Color(0xFF806342)
            canvas.drawRect(Rect.fromLTWH(x, y, 10, 10), paint)
            paint.color = colors[i]
            canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, 8, 8), paint)
            paint.color = Color(0x55FFF4DB)
            canvas.drawRect(Rect.fromLTWH(x + 1, y + 8, 8, 1), paint)
        }
        canvas.restore()
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? CityLauncherPainter else { return true }
        return old.hovered != hovered || old.pressed != pressed
    }
}
