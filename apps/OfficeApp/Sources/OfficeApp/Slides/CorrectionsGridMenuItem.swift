// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Picture Format > Corrections as PowerPoint shows it: a 5 x 5 grid of the selected picture, each copy drawn with one
/// Brightness/Contrast pair (-40...+40 % in steps of 20; brightness across, contrast down), the pair in its tooltip and
/// the current one outlined. Before the picture has decoded, a cell is a grey of the brightness it gives.
final class CorrectionsGridMenuItem: MenuFlyoutItemBase {
    static let steps: [Double] = [-40, -20, 0, 20, 40]
    static let cellWidth = 64.0
    static let gap = 4.0

    /// The decoded picture, asked for when the grid opens (the ribbon is built before the picture has decoded).
    let image: () -> Image?
    let aspect: Double
    let current: (brightness: Double, contrast: Double)?
    let accent: Color
    let hover: Color
    let onChoose: (Double, Double) -> Void

    init(image: @escaping () -> Image?, aspect: Double, current: (brightness: Double, contrast: Double)?, accent: Color, hover: Color,
         onChoose: @escaping (Double, Double) -> Void) {
        self.image = image; self.aspect = aspect; self.current = current
        self.accent = accent; self.hover = hover; self.onChoose = onChoose
        super.init(key: ValueKey("corrections-grid"))
    }

    static func label(_ b: Double, _ c: Double) -> String {
        func sign(_ v: Double) -> String { v > 0 ? "+\(Int(v))%" : "\(Int(v))%" }
        return "Brightness: \(sign(b)) Contrast: \(sign(c))"
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let close: () -> Void = {
            if let scope = FlyoutScope.maybeOf(context) { scope.close() } else { Navigator.maybeOf(context)?.maybePop() }
        }
        let image = self.image()
        let h = (Self.cellWidth / max(0.25, min(4, aspect))).rounded()
        let rows: [Widget] = Self.steps.map { c in
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: Self.gap), child: Row(mainAxisSize: .min, children: Self.steps.map { b in
                let on = current.map { abs($0.brightness - b) < 0.5 && abs($0.contrast - c) < 0.5 } ?? false
                return Padding(padding: EdgeInsets(left: 0, top: 0, right: Self.gap, bottom: 0), child: Tooltip(message: Self.label(b, c), child: _CorrectionCell(
                    key: ValueKey("corrections-\(Int(b))-\(Int(c))"), image: image, brightness: b, contrast: c,
                    width: Self.cellWidth, height: h, selected: on, accent: accent, hover: hover,
                    onTap: { [onChoose] in close(); onChoose(b, c) })))
            }))
        }
        return Padding(padding: EdgeInsets(left: 4, top: 4, right: 0, bottom: 0),
                       child: Column(key: ValueKey("corrections-grid-panel"), mainAxisSize: .min, crossAxisAlignment: .start, children: rows))
    }
}

/// One preview, framed while the pointer is over it or while it is the picture's own setting.
private final class _CorrectionCell: StatefulWidget {
    let image: Image?
    let brightness: Double, contrast: Double
    let width: Double, height: Double
    let selected: Bool
    let accent: Color, hover: Color
    let onTap: () -> Void

    init(key: (any Key)?, image: Image?, brightness: Double, contrast: Double, width: Double, height: Double, selected: Bool,
         accent: Color, hover: Color, onTap: @escaping () -> Void) {
        self.image = image; self.brightness = brightness; self.contrast = contrast; self.width = width; self.height = height
        self.selected = selected; self.accent = accent; self.hover = hover; self.onTap = onTap
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { _CorrectionCellState() }
}

private final class _CorrectionCellState: State<StatefulWidget> {
    var hovered = false
    private var w: _CorrectionCell { widget as! _CorrectionCell }

    override func build(_ context: any BuildContext) -> Widget {
        let picture = SizedBox(width: w.width, height: w.height, child: CustomPaint(painter: _CorrectionPainter(
            image: w.image, levels: PptxReader.lumLevels(bright: w.brightness / 100, contrast: w.contrast / 100))))
        let ring: Color? = w.selected ? w.accent : hovered ? w.hover : nil
        return MouseRegion(onEnter: { [weak self] _ in self?.setState { self?.hovered = true } },
                           onExit: { [weak self] _ in self?.setState { self?.hovered = false } },
                           child: GestureDetector(onTap: w.onTap, child: DecoratedBox(
                               decoration: BoxDecoration(color: ring ?? Color(0x00000000), borderRadius: BorderRadius.circular(2)),
                               child: Padding(padding: EdgeInsets(left: 3, top: 3, right: 3, bottom: 3), child: picture))))
    }
}

/// The picture scaled to fill the cell (cut at the long side), drawn with the levels the pair gives.
private final class _CorrectionPainter: CustomPainter {
    let image: Image?
    let levels: [Double]?

    init(image: Image?, levels: [Double]?) {
        self.image = image; self.levels = levels
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let dst = Rect.fromLTWH(0, 0, size.width, size.height)
        guard let image, image.width > 0, image.height > 0 else {
            // Not decoded yet: mid grey through the same levels.
            let g = levels.map { max(0, min(1, 0.5 * $0[0] + $0[4] / 255)) } ?? 0.5
            let v = Int((g * 255).rounded())
            let p = Paint()
            p.color = Color(Int64(0xFF00_0000 | (v << 16) | (v << 8) | v))
            canvas.drawRect(dst, p)
            return
        }
        let iw = Double(image.width), ih = Double(image.height)
        let scale = max(size.width / iw, size.height / ih)
        let sw = size.width / scale, sh = size.height / scale
        let src = Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh)
        canvas.drawImageRect(image, src, dst, SlidePainter.imagePaint(alpha: 1, duotone: nil, levels: levels))
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let o = oldDelegate as? _CorrectionPainter else { return true }
        return o.image !== image || o.levels != levels
    }
}
