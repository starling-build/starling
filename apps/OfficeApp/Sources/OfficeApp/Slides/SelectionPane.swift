// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Selection Pane (S-AR-1b): every shape of the current slide, front first,
// with an eye to show or hide it and buttons to move it in the stack. A row
// selects its shape (Shift or Ctrl adds), which is the only way to reach a
// hidden one.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class SelectionPane: StatelessWidget {
    let deck: DeckController
    let onClose: () -> Void
    let modifiers: () -> KeyModifiers

    init(deck: DeckController, modifiers: @escaping () -> KeyModifiers = { [] }, onClose: @escaping () -> Void) {
        self.deck = deck
        self.modifiers = modifiers
        self.onClose = onClose
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        // The pane follows the deck itself: a hide or a reorder renumbers its rows.
        AnimatedBuilder(animation: deck, builder: { [self] ctx, _ in _panel(ctx) })
    }

    private func _panel(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let ink = fluent.resources.textFillColorPrimary
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let shapes = deck.currentSlide.shapes
        var rows: [Widget] = []
        // Front of the stack first, as PowerPoint lists it.
        for (i, shape) in shapes.enumerated().reversed() {
            let selected = deck.isSelected(shape)
            let hidden = shape.invisible
            let byGroup = shape.group?.hidden == true
            let label = shape.name.isEmpty ? "Shape \(i + 1)" : shape.name
            let color = hidden ? fluent.resources.textFillColorDisabled : ink
            rows.append(ColoredBox(
                color: selected ? accent.withOpacity(0.14) : Color(0x00000000),
                child: Row(children: [
                    Padding(key: ValueKey("selpane.eye.\(i)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child:
                        FlatButton(child: Text(hidden ? "○" : "●", style: fluent.typography.body?.copyWith(color: color)),
                                   tip: hidden ? "Show" : "Hide", enabled: !byGroup) { [deck] in deck.setHidden(shape, !hidden) }),
                    Expanded(child: KeyboardRow(label: label, activate: { [deck] in deck.selectShapes([shape]) }, child: Listener(
                        key: ValueKey("selpane.row.\(i)"),
                        onPointerDown: { [deck, modifiers] _ in
                            let m = modifiers()
                            if deck.selectMultiple || m.contains(.shift) || m.contains(.control) || m.contains(.meta) { deck.toggleSelected(shape) }
                            else { deck.selectShapes([shape]) }
                        },
                        behavior: .opaque,
                        child: Padding(padding: EdgeInsets(left: 4, top: 8, right: 4, bottom: 8),
                                       child: Text(label, style: fluent.typography.body?.copyWith(color: color),
                                                   overflow: .ellipsis, maxLines: 1))))),
                    Padding(key: ValueKey("selpane.front.\(i)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child:
                        Chrome.icon(FluentSystemIcons.chevronUp, "Bring forward", fluent, enabled: i < shapes.count - 1) { [deck] in
                            deck.moveInStack(shape, by: 1) }),
                    Padding(key: ValueKey("selpane.back.\(i)"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), child:
                        Chrome.icon(FluentSystemIcons.chevronDown, "Send backward", fluent, enabled: i > 0) { [deck] in
                            deck.moveInStack(shape, by: -1) }),
                ])))
        }
        if rows.isEmpty {
            rows.append(Padding(padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 8), child: Text(
                "This slide has no shapes.", style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary))))
        }
        let header = Row(children: [
            Expanded(child: Text("Selection Pane", style: fluent.typography.bodyStrong)),
            Padding(key: ValueKey("selpane.close"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                    child: IconButton(icon: Icon(FluentSystemIcons.close, size: 14, color: ink), onPressed: onClose)),
        ])
        return SizedBox(width: 300, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border(left: BorderSide(color: fluent.resources.controlStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 12), child: Column(
                crossAxisAlignment: .stretch, children: [
                    header,
                    SizedBox(width: nil, height: 8, child: nil),
                    Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))),
                ]))))
    }
}
