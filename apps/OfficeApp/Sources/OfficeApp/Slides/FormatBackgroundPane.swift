// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Format Background pane: the slide's background as a solid colour, a gradient or a picture
// (or the theme's own), for this slide or all of them. Each change is one undoable step.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class FormatBackgroundPane: StatefulWidget {
    let deck: DeckController
    let onPicture: () -> Void
    let onClose: () -> Void

    init(deck: DeckController, onPicture: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.deck = deck
        self.onPicture = onPicture
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { FormatBackgroundPaneState() }
}

final class FormatBackgroundPaneState: State<StatefulWidget> {
    private enum Kind: Equatable { case theme, solid, gradient, picture }
    private var _w: FormatBackgroundPane { widget as! FormatBackgroundPane }
    private var _controllers: [String: TextEditingController] = [:]
    private var _shown: [String: String] = [:]

    private func _field(_ id: String, _ value: String) -> TextEditingController {
        let c = _controllers[id] ?? { let n = TextEditingController(text: value); _controllers[id] = n; _shown[id] = value; return n }()
        if _shown[id] != value { c.text = value; _shown[id] = value }
        return c
    }

    private func _kind(_ f: SlideFill?) -> Kind {
        guard let f else { return .theme }
        if f.image != nil { return .picture }
        if f.stops.count >= 2 { return .gradient }
        return f.color != nil ? .solid : .theme
    }

    /// A gradient from `colour` to a darker shade of it, top to bottom.
    static func gradient(from colour: Color) -> SlideFill {
        SlideFill(color: colour, stops: [.init(position: 0, color: colour), .init(position: 1, color: DeckController.darker(colour))], angle: 90)
    }

    override func build(_ context: any BuildContext) -> Widget {
        AnimatedBuilder(animation: _w.deck, builder: { [self] ctx, _ in _panel(ctx) })
    }

    private func _panel(_ context: any BuildContext) -> Widget {
        let deck = _w.deck
        let onPicture = _w.onPicture
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        let fill = deck.currentSlide.background ?? deck.currentSlide.inheritedBackground
        let kind = _kind(fill)
        let base = fill?.color ?? deck.theme.backgroundFill.color ?? deck.theme.background
        func gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }
        func radio(_ id: String, _ label: String, _ k: Kind, _ make: @escaping () -> SlideFill?) -> Widget {
            RadioButton<Kind>(key: ValueKey(id), value: k, groupValue: kind,
                              onChanged: { _ in
                                  if k == .picture { onPicture() } else { deck.setBackground(make()) }
                              }, content: Text(label))
        }
        func hexRow(_ id: String, _ label: String, _ colour: Color, _ apply: @escaping (Color) -> Void) -> Widget {
            let shown = FormatShapePaneState.hex(colour)
            let c = _field(id, shown)
            return Row(children: [
                SizedBox(width: 110, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 90, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: c,
                    onSubmitted: { [weak self] text in
                        if let v = FormatShapePaneState.parseHex(text) { apply(Color(Int64(0xFF00_0000) | Int64(v))) }
                        else { c.text = shown; self?._shown[id] = shown }
                    })),
            ])
        }
        func numRow(_ id: String, _ label: String, _ value: Double, unit: String, _ range: ClosedRange<Double>, _ apply: @escaping (Double) -> Void) -> Widget {
            let shown = FormatShapePaneState.text(value)
            let c = _field(id, shown)
            return Row(children: [
                SizedBox(width: 110, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 90, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: c,
                    onSubmitted: { [weak self] text in
                        if let v = Double(FormatShapePaneState.digits(text)), range.contains(v) { apply(v) }
                        else { c.text = shown; self?._shown[id] = shown }
                    })),
                SizedBox(width: 6, height: nil, child: Text(unit, style: caption)),
            ])
        }
        var controls: [Widget] = []
        switch kind {
        case .solid:
            controls = [hexRow("bg.color", "Colour (hex)", base) { deck.setBackground(SlideFill(color: $0)) }]
        case .gradient:
            if let f = fill {
                let first = f.stops.first!, last = f.stops.last!
                func with(_ edit: (inout SlideFill) -> Void) { var g = f; edit(&g); g.color = g.stops.first?.color; deck.setBackground(g) }
                controls = [
                    hexRow("bg.stop1", "Start colour", first.color) { c in with { $0.stops[0].color = c } }, gap(6),
                    hexRow("bg.stop2", "End colour", last.color) { c in with { $0.stops[$0.stops.count - 1].color = c } }, gap(6),
                    numRow("bg.angle", "Angle", f.angle, unit: "°", -360...360) { a in with { $0.angle = a } },
                ]
            }
        case .picture:
            if let f = fill {
                controls = [
                    Button(key: ValueKey("bg.choose"), onPressed: onPicture, child: Text("Choose picture…")), gap(6),
                    numRow("bg.transparency", "Transparency", (1 - f.imageAlpha) * 100, unit: "%", 0...100) { t in
                        var g = f; g.imageAlpha = 1 - t / 100; deck.setBackground(g)
                    }, gap(6),
                    Checkbox(key: ValueKey("bg.tile"), checked: f.tiled, onChanged: { v in
                        var g = f; g.tiled = v ?? false; deck.setBackground(g)
                    }, content: Text("Tile picture as texture")),
                ]
            }
        case .theme:
            controls = [Text("The theme's own background.", style: caption)]
        }
        let header = Row(children: [
            Expanded(child: Text("Format Background", style: fluent.typography.bodyStrong)),
            IconButton(key: ValueKey("bg.close"), icon: Icon(FluentSystemIcons.close, size: 14, color: fluent.resources.textFillColorPrimary),
                       onPressed: _w.onClose),
        ])
        let body = Column(crossAxisAlignment: .start, children: [
            Text("Fill", style: caption), gap(4),
            radio("bg.kind.solid", "Solid fill", .solid) { SlideFill(color: base) }, gap(4),
            radio("bg.kind.gradient", "Gradient fill", .gradient) { Self.gradient(from: base) }, gap(4),
            radio("bg.kind.picture", "Picture fill…", .picture) { nil }, gap(4),
            radio("bg.kind.theme", "Theme background", .theme) { nil }, gap(14),
        ] + controls + [
            gap(16),
            Button(key: ValueKey("bg.all"), onPressed: { deck.setBackground(deck.currentSlide.background, all: true) },
                   child: Text("Apply to All Slides")),
        ])
        return SizedBox(width: 300, height: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border(left: BorderSide(color: fluent.resources.controlStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 12, right: 12, bottom: 12), child: Column(
                crossAxisAlignment: .stretch, children: [
                    header, gap(8),
                    Expanded(child: SingleChildScrollView(child: body)),
                ]))))
    }
}
