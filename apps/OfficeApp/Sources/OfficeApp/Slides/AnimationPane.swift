// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Animation Pane (S7): the current slide's entrances in the order they
// play, numbered by the click that starts them, beside the slide. A row
// selects its shape; the pane's buttons reorder and remove.

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class AnimationPane: StatelessWidget {
    let deck: DeckController
    let onClose: () -> Void

    init(deck: DeckController, onClose: @escaping () -> Void) {
        self.deck = deck
        self.onClose = onClose
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let ink = fluent.resources.textFillColorPrimary
        let accent = fluent.accentColor.defaultBrushFor(fluent.brightness)
        let slide = deck.currentSlide
        let numbers = AnimationPlan.clickNumbers(slide.animations)
        let selected = deck.selectedAnimations.first.flatMap { slide.animations.firstIndex(of: $0) }
        var rows: [Widget] = []
        for (i, a) in slide.animations.enumerated() {
            let shape = slide.shapes.first { $0.id == a.shapeId }
            var label = shape?.name ?? "Shape"
            if let p = a.paragraph, let text = shape?.text?.document.paragraphs[safe: p]?.text {
                label = text.count > 28 ? String(text.prefix(28)) + "…" : text
            } else if let text = shape?.text?.document.plainText(), !text.isEmpty {
                label = text.count > 28 ? String(text.prefix(28)) + "…" : text
            }
            let isSelected = deck.selection.contains { $0.id == a.shapeId }
            let number = a.start == .onClick ? "\(numbers[i])" : ""
            let marker: Widget = a.start == .afterPrevious
                ? Icon(FluentSystemIcons.clock, size: 12, color: fluent.resources.textFillColorSecondary)
                : SizedBox(width: 12, height: 12, child: nil)
            rows.append(Listener(
                onPointerDown: { [deck] _ in if let shape { deck.selectShapes([shape]) } },
                behavior: .opaque,
                child: ColoredBox(
                    color: isSelected ? accent.withOpacity(0.14) : Color(0x00000000),
                    child: Padding(padding: EdgeInsets(left: 8, top: 6, right: 8, bottom: 6), child: Row(children: [
                        SizedBox(width: 22, height: nil, child: Text(number, style: fluent.typography.bodyStrong)),
                        marker,
                        SizedBox(width: 6, height: nil, child: nil),
                        SizedBox(width: 70, height: nil, child: Text(a.effect.name, style: fluent.typography.caption?.copyWith(color: accent))),
                        Expanded(child: Text(label, style: fluent.typography.caption, overflow: .ellipsis, maxLines: 1)),
                    ])))))
        }
        if rows.isEmpty {
            rows.append(Padding(padding: EdgeInsets(left: 8, top: 8, right: 8, bottom: 8), child: Text(
                slide.animationsKept
                    ? "This slide's animations come from the file and are kept as they are."
                    : "Select a shape, then pick an animation on the Animations tab.",
                style: fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary))))
        }
        let toolbar = Row(children: [
            Chrome.icon(FluentSystemIcons.chevronUp, "Move earlier", fluent) { [deck] in
                if let i = selected { deck.moveAnimation(i, by: -1) }
            },
            Chrome.icon(FluentSystemIcons.chevronDown, "Move later", fluent) { [deck] in
                if let i = selected { deck.moveAnimation(i, by: 1) }
            },
            Chrome.icon(FluentSystemIcons.delete, "Remove", fluent) { [deck] in
                if let i = selected { deck.removeAnimation(i) }
            },
        ])
        let header = Row(children: [
            Expanded(child: Text("Animation Pane", style: fluent.typography.bodyStrong)),
            IconButton(icon: Icon(FluentSystemIcons.close, size: 14, color: ink), onPressed: onClose),
        ])
        return SizedBox(width: 300, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border(left: BorderSide(color: fluent.resources.controlStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 12), child: Column(
                crossAxisAlignment: .stretch, children: [
                    header,
                    SizedBox(width: nil, height: 8, child: nil),
                    toolbar,
                    SizedBox(width: nil, height: 6, child: nil),
                    Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: .stretch, children: rows))),
                ]))))
    }
}
