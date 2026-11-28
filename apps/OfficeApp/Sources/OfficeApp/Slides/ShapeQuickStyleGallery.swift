// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Shape Format > Shape Styles as PowerPoint shows it: the Theme Styles grid, seven colours across by six styles down,
/// each drawn as a small "Abc" box in its own look and named in its tooltip. Resting the pointer on one shows it on
/// the selected shapes; a click applies it.
final class ShapeQuickStyleMenuItem: MenuFlyoutItemBase {
    static let cellWidth = 44.0
    static let cellHeight = 32.0

    let deck: DeckController
    let hover: Color

    init(deck: DeckController, hover: Color) {
        self.deck = deck; self.hover = hover
        super.init(key: ValueKey("quick-styles"))
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let close: () -> Void = {
            if let scope = FlyoutScope.maybeOf(context) { scope.close() } else { Navigator.maybeOf(context)?.maybePop() }
        }
        let colors = deck.tableStyleColors()
        let current = deck.currentQuickStyle
        let rows: [Widget] = ShapeQuickStyle.rows.indices.map { r in
            Row(children: ShapeQuickStyle.columns.indices.map { c in
                let style = ShapeQuickStyle(row: r, column: c)
                return Tooltip(message: style.name, child: _QuickStyleCell(
                    key: ValueKey("quick-style-\(r)-\(c)"), look: style.look(colors), selected: style == current,
                    hover: hover, width: Self.cellWidth, height: Self.cellHeight,
                    onEnter: { [deck] in deck.previewQuickStyle(style) },
                    onExit: { [deck] in deck.endQuickStylePreview() },
                    onTap: { [deck] in close(); deck.applyQuickStyle(style) }))
            })
        }
        return Column(key: ValueKey("quick-styles-panel"), crossAxisAlignment: .start, children: [
            Padding(padding: EdgeInsets(left: 2, top: 0, right: 0, bottom: 4), child: Text("Theme Styles", style: TextStyle(fontWeight: .w600))),
        ] + rows)
    }
}

/// One gallery entry: the style's fill, line and text colour on a rounded box, shaded while the pointer is over it.
private final class _QuickStyleCell: StatefulWidget {
    let look: ShapeQuickStyle.Look
    let selected: Bool
    let hover: Color
    let width: Double, height: Double
    let onEnter: () -> Void, onExit: () -> Void, onTap: () -> Void

    init(key: (any Key)?, look: ShapeQuickStyle.Look, selected: Bool, hover: Color, width: Double, height: Double,
         onEnter: @escaping () -> Void, onExit: @escaping () -> Void, onTap: @escaping () -> Void) {
        self.look = look; self.selected = selected; self.hover = hover; self.width = width; self.height = height
        self.onEnter = onEnter; self.onExit = onExit; self.onTap = onTap
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { _QuickStyleCellState() }
}

private final class _QuickStyleCellState: State<StatefulWidget> {
    var hovered = false
    private var w: _QuickStyleCell { widget as! _QuickStyleCell }

    override func build(_ context: any BuildContext) -> Widget {
        let look = w.look
        let gradient = look.gradient.map { g in
            LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                           colors: g.stops.map(\.color), stops: g.stops.map(\.position)) as GradientBase
        }
        let shadow = look.shadow.map { [BoxShadow(color: $0.color, offset: Offset($0.dx, $0.dy), blurRadius: $0.blur)] } ?? []
        let swatch = DecoratedBox(
            decoration: BoxDecoration(color: gradient == nil ? look.fill : nil,
                                      border: look.outline.map { Border.all(color: $0, width: max(1, look.outlineWidth)) },
                                      borderRadius: BorderRadius.circular(2), boxShadow: shadow, gradient: gradient),
            child: Center(child: Text("Abc", style: TextStyle(color: look.text, fontSize: 11))))
        let ring = hovered || w.selected
        let padded = Padding(padding: EdgeInsets(left: 4, top: 4, right: 4, bottom: 4), child: swatch)
        let cell = SizedBox(width: w.width, height: w.height, child: ring
            ? DecoratedBox(decoration: BoxDecoration(color: w.hover, borderRadius: BorderRadius.circular(3)), child: padded)
            : padded)
        return MouseRegion(onEnter: { [weak self] _ in self?.setState { self?.hovered = true }; self?.w.onEnter() },
                           onExit: { [weak self] _ in self?.setState { self?.hovered = false }; self?.w.onExit() },
                           child: GestureDetector(onTap: w.onTap, child: cell))
    }

    /// The menu closed (Escape, a click elsewhere) with the pointer still on this entry: put the shapes back.
    override func dispose() {
        if hovered { w.onExit() }
        super.dispose()
    }
}
