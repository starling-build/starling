// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// Word's horizontal ruler: inch ticks across the page width, the margins
/// shaded, centred over the page exactly as RichEditable centres it (same
/// arithmetic: max(pad, (width − page) / 2)).
final class Ruler: StatelessWidget {
    let setup: PageSetup
    let zoom: Double
    let pixelsPerPoint: Double
    let sidePadding: Double
    let indentLeft: Double   // points, the current paragraph's

    init(setup: PageSetup, zoom: Double, pixelsPerPoint: Double, sidePadding: Double, indentLeft: Double) {
        self.setup = setup
        self.zoom = zoom
        self.pixelsPerPoint = pixelsPerPoint
        self.sidePadding = sidePadding
        self.indentLeft = indentLeft
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        return SizedBox(width: nil, height: 22, child: CustomPaint(
            painter: _RulerPainter(setup: setup, px: pixelsPerPoint * zoom, pad: sidePadding,
                                   indentLeft: indentLeft,
                                   background: OfficeAppearance.canvas(fluent),
                                   paper: fluent.brightness == .dark ? Color(0xFF3A3A3A) : Color(0xFFFFFFFF),
                                   margin: fluent.brightness == .dark ? Color(0xFF28364E) : Color(0xFFDBE3F0),
                                   ink: fluent.resources.textFillColorSecondary,
                                   accent: fluent.accentColor.defaultBrushFor(fluent.brightness)),
            child: SizedBox(expand: ())))
    }
}

private final class _RulerPainter: CustomPainter {
    let setup: PageSetup
    let px: Double
    let pad: Double
    let indentLeft: Double
    let background: Color
    let paper: Color
    let margin: Color
    let ink: Color
    let accent: Color

    init(setup: PageSetup, px: Double, pad: Double, indentLeft: Double, background: Color,
         paper: Color, margin: Color, ink: Color, accent: Color) {
        self.setup = setup
        self.px = px
        self.pad = pad
        self.indentLeft = indentLeft
        self.background = background
        self.paper = paper
        self.margin = margin
        self.ink = ink
        self.accent = accent
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let fill = Paint()
        fill.style = .fill
        fill.color = background
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), fill)

        let pageW = setup.width * px
        let originX = max(pad, ((size.width - pageW) / 2).rounded())
        let top = 4.0
        let h = size.height - 8
        fill.color = margin
        canvas.drawRect(Rect.fromLTWH(originX, top, pageW, h), fill)
        let contentL = originX + setup.marginLeft * px
        let contentW = setup.contentWidth * px
        fill.color = paper
        canvas.drawRect(Rect.fromLTWH(contentL, top, contentW, h), fill)

        // Ticks every eighth of an inch from the left margin; numbers per inch.
        let line = Paint()
        line.style = .stroke
        line.strokeWidth = 1
        line.color = ink
        let inch = 72 * px
        var k = -Int((setup.marginLeft * px) / (inch / 8))
        let maxK = Int((pageW - setup.marginLeft * px) / (inch / 8))
        let mid = top + h / 2
        while k <= maxK {
            let x = (contentL + Double(k) * inch / 8).rounded() + 0.5
            if x >= originX && x <= originX + pageW {
                if k % 8 == 0 {
                    let n = abs(k / 8)
                    if n > 0 {
                        let tp = TextPainter(text: TextSpan(text: "\(n)", style: Flutter.TextStyle(color: ink, fontSize: 9)),
                                             textAlign: .center, textDirection: .ltr)
                        tp.layout(minWidth: 0, maxWidth: 20)
                        tp.paint(canvas, Offset(x - tp.width / 2, mid - tp.height / 2))
                        tp.dispose()
                    }
                } else if k % 4 == 0 {
                    canvas.drawLine(Offset(x, mid - 4), Offset(x, mid + 4), line)
                } else if k % 2 == 0 {
                    canvas.drawLine(Offset(x, mid - 2), Offset(x, mid + 2), line)
                }
            }
            k += 1
        }

        // Indent markers: a small accent triangle pair at the left indent
        // and a square at the right margin.
        let marker = Paint()
        marker.style = .fill
        marker.color = accent
        let ix = contentL + indentLeft * px
        let tri = Path()
        tri.moveTo(ix - 4, top)
        tri.lineTo(ix + 4, top)
        tri.lineTo(ix, top + 5)
        tri.close()
        canvas.drawPath(tri, marker)
        let tri2 = Path()
        tri2.moveTo(ix - 4, top + h)
        tri2.lineTo(ix + 4, top + h)
        tri2.lineTo(ix, top + h - 5)
        tri2.close()
        canvas.drawPath(tri2, marker)
        let rx = contentL + contentW
        let tri3 = Path()
        tri3.moveTo(rx - 4, top + h)
        tri3.lineTo(rx + 4, top + h)
        tri3.lineTo(rx, top + h - 5)
        tri3.close()
        canvas.drawPath(tri3, marker)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool { true }
}
