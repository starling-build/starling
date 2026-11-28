// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Home > Shapes as PowerPoint shows it: one panel, each group a heading over a grid of shape icons, every shape named in
/// its tooltip. The panel has a fixed height and scrolls, so it stays inside a small window (a submenu per group ran
/// off the bottom: Basic Shapes alone is 45 rows).
final class ShapeGridMenuItem: MenuFlyoutItemBase {
    static let columns = 12
    static let cell = 24.0
    static let height = 420.0

    let ink: Color
    let onChoose: (ShapePreset) -> Void

    init(ink: Color, onChoose: @escaping (ShapePreset) -> Void) {
        self.ink = ink; self.onChoose = onChoose
        super.init(key: ValueKey("shape-grid"))
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let close: () -> Void = {
            if let scope = FlyoutScope.maybeOf(context) { scope.close() } else { Navigator.maybeOf(context)?.maybePop() }
        }
        var rows: [Widget] = []
        for group in ShapeGallery.groups {
            rows.append(Padding(padding: EdgeInsets(left: 2, top: rows.isEmpty ? 0 : 8, right: 0, bottom: 4),
                                child: Text(group.name, style: TextStyle(fontWeight: .w600))))
            rows.append(Wrap(children: group.presets.map { preset in
                Tooltip(message: preset.name, child: GestureDetector(
                    key: ValueKey("shape-grid-\(preset.rawValue)"),
                    onTap: { [onChoose] in close(); onChoose(preset) },
                    child: SizedBox(width: Self.cell, height: Self.cell,
                                    child: CustomPaint(painter: _ShapeIconPainter(preset: preset, ink: ink)))))
            }))
        }
        return SizedBox(key: ValueKey("shape-grid-panel"), width: Double(Self.columns) * Self.cell, height: Self.height,
                        child: SingleChildScrollView(child: Column(crossAxisAlignment: .start, children: rows)))
    }
}

/// One shape's outline, drawn from its preset geometry inside the cell.
private final class _ShapeIconPainter: CustomPainter {
    let preset: ShapePreset
    let ink: Color

    init(preset: ShapePreset, ink: Color) {
        self.preset = preset; self.ink = ink
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let r = Rect.fromLTWH(4, 5, size.width - 8, size.height - 10)
        let path: Path
        if preset.isLine {
            path = Path(); path.moveTo(r.left, r.bottom); path.lineTo(r.right, r.top)
        } else if let p = PresetGeometry.path(preset.rawValue, in: r) {
            path = p
        } else { return }
        let p = Paint()
        p.style = .stroke
        p.isAntiAlias = true
        p.strokeWidth = 1
        p.color = ink
        canvas.drawPath(path, p)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let o = oldDelegate as? _ShapeIconPainter else { return true }
        return o.preset != preset || o.ink != ink
    }
}
