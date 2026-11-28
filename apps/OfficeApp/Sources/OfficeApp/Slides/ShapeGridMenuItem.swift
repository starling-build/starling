// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Home > Shapes as PowerPoint shows it: one panel, each group a heading over a grid of shape icons, every shape named in
/// its tooltip. The panel has a fixed height and scrolls, so it stays inside a small window (a submenu per group ran
/// off the bottom: Basic Shapes alone is 45 rows).
final class ShapeGridMenuItem: MenuFlyoutItemBase, RibbonPopupChoosing {
    static let columns = 12
    static let cell = 24.0
    static let height = 420.0

    let ink: Color
    let hover: Color
    let recent: [ShapePreset]
    let onChoose: (ShapePreset) -> Void
    let outlinesOnly: Bool

    /// `recent`: the shapes picked lately, newest first, shown as PowerPoint's Recently Used Shapes row.
    /// `outlinesOnly`: leave out the Lines group, as Picture Format > Crop to Shape does (a line encloses nothing).
    init(ink: Color, hover: Color, recent: [ShapePreset] = [], outlinesOnly: Bool = false, onChoose: @escaping (ShapePreset) -> Void) {
        self.ink = ink; self.hover = hover; self.recent = recent; self.onChoose = onChoose; self.outlinesOnly = outlinesOnly
        super.init(key: ValueKey(outlinesOnly ? "crop-shape-grid" : "shape-grid"))
    }

    func closing(_ also: @escaping () -> Void) -> MenuFlyoutItemBase {
        ShapeGridMenuItem(ink: ink, hover: hover, recent: recent, outlinesOnly: outlinesOnly) { [onChoose] in onChoose($0); also() }
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let close: () -> Void = {
            if let scope = FlyoutScope.maybeOf(context) { scope.close() } else { Navigator.maybeOf(context)?.maybePop() }
        }
        var rows: [Widget] = []
        let groups = (recent.isEmpty ? [] : [ShapeGallery.Group(name: "Recently Used Shapes", presets: recent)])
            + ShapeGallery.groups.filter { !outlinesOnly || $0.name != "Lines" }
        for (gi, group) in groups.enumerated() {
            let recentRow = gi == 0 && !recent.isEmpty
            rows.append(Padding(padding: EdgeInsets(left: 2, top: rows.isEmpty ? 0 : 8, right: 0, bottom: 4),
                                child: Text(group.name, style: TextStyle(fontWeight: .w600))))
            rows.append(Wrap(children: group.presets.map { preset in
                Tooltip(message: preset.name, child: _ShapeCell(
                    key: ValueKey(recentRow ? "shape-grid-recent-\(preset.rawValue)" : "shape-grid-\(preset.rawValue)"),
                    preset: preset, ink: ink, hover: hover, size: Self.cell,
                    onTap: { [onChoose] in close(); onChoose(preset) }))
            }))
        }
        return SizedBox(key: ValueKey("shape-grid-panel"), width: Double(Self.columns) * Self.cell, height: Self.height,
                        child: SingleChildScrollView(child: Column(crossAxisAlignment: .start, children: rows)))
    }
}

/// One icon of the grid, shaded while the pointer is over it.
private final class _ShapeCell: StatefulWidget {
    let preset: ShapePreset
    let ink: Color
    let hover: Color
    let size: Double
    let onTap: () -> Void

    init(key: (any Key)?, preset: ShapePreset, ink: Color, hover: Color, size: Double, onTap: @escaping () -> Void) {
        self.preset = preset; self.ink = ink; self.hover = hover; self.size = size; self.onTap = onTap
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { _ShapeCellState() }
}

private final class _ShapeCellState: State<StatefulWidget> {
    var hovered = false
    private var w: _ShapeCell { widget as! _ShapeCell }

    override func build(_ context: any BuildContext) -> Widget {
        let icon = SizedBox(width: w.size, height: w.size,
                            child: CustomPaint(painter: _ShapeIconPainter(preset: w.preset, ink: w.ink)))
        return MouseRegion(onEnter: { [weak self] _ in self?.setState { self?.hovered = true } },
                           onExit: { [weak self] _ in self?.setState { self?.hovered = false } },
                           child: GestureDetector(onTap: w.onTap, child: hovered
                               ? DecoratedBox(decoration: BoxDecoration(color: w.hover, borderRadius: BorderRadius.circular(3)), child: icon)
                               : icon))
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
        let p = Paint()
        p.style = .stroke
        p.isAntiAlias = true
        p.strokeWidth = 1
        p.color = ink
        if preset.isLine {
            let path = Path(); path.moveTo(r.left, r.bottom); path.lineTo(r.right, r.top)
            canvas.drawPath(path, p)
            return
        }
        // Every contour the shape strokes, so a smiley's mouth and a bracket show as well as the outline.
        guard let g = PresetGeometry.geometry(preset.rawValue, width: r.width * Pptx.emu, height: r.height * Pptx.emu) else { return }
        for sub in g.subpaths where sub.stroke { canvas.drawPath(FreeformGeometry.path(sub, in: r), p) }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let o = oldDelegate as? _ShapeIconPainter else { return true }
        return o.preset != preset || o.ink != ink
    }
}
