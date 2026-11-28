// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Format Background pane: the slide's background as a solid colour, a gradient (its own stops,
// linear or radial), a picture or a pattern (or the theme's own), with its transparency; Hide background
// graphics; for this slide or all of them; Reset Background. Each change is one undoable step.

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
    private enum Kind: Equatable { case theme, solid, gradient, picture, pattern }
    enum GradientType: Equatable { case linear, radial, rectangular }
    private var _w: FormatBackgroundPane { widget as! FormatBackgroundPane }
    private var _controllers: [String: TextEditingController] = [:]
    private var _shown: [String: String] = [:]
    /// The gradient stop the Colour, Position and Transparency fields edit.
    private var _stop = 0

    private func _field(_ id: String, _ value: String) -> TextEditingController {
        let c = _controllers[id] ?? { let n = TextEditingController(text: value); _controllers[id] = n; _shown[id] = value; return n }()
        if _shown[id] != value { c.text = value; _shown[id] = value }
        return c
    }

    private func _kind(_ f: SlideFill?) -> Kind {
        guard let f else { return .theme }
        if f.isPattern { return .pattern }
        if f.image != nil { return .picture }
        if f.stops.count >= 2 { return .gradient }
        return f.color != nil ? .solid : .theme
    }

    /// A gradient from `colour` to a darker shade of it, top to bottom.
    static func gradient(from colour: Color) -> SlideFill {
        SlideFill(color: colour, stops: [.init(position: 0, color: colour), .init(position: 1, color: DeckController.darker(colour))], angle: 90)
    }

    /// PowerPoint's pattern grid, in its order (the 48 presets of its Pattern fill).
    static let patterns = ["pct5", "pct10", "pct20", "pct25", "pct30", "pct40", "pct50", "pct60", "pct70", "pct75", "pct80", "pct90",
                           "ltDnDiag", "ltUpDiag", "dkDnDiag", "dkUpDiag", "wdDnDiag", "wdUpDiag", "ltVert", "ltHorz", "narVert", "narHorz", "dkVert", "dkHorz",
                           "dashDnDiag", "dashUpDiag", "dashHorz", "dashVert", "smConfetti", "lgConfetti", "zigZag", "wave", "diagBrick", "horzBrick", "weave", "plaid",
                           "divot", "dotGrid", "dotDmnd", "shingle", "trellis", "sphere", "smGrid", "lgGrid", "smCheck", "lgCheck", "openDmnd", "solidDmnd"]
        .filter { PatternFill.rows[$0] != nil }

    /// A colour at `percent` transparency (0 opaque, 100 clear), as the Transparency fields set it.
    static func transparent(_ c: Color, _ percent: Double) -> Color {
        c.withAlpha(Int(((100 - percent) / 100 * 255).rounded()))
    }

    static func transparency(_ c: Color) -> Double { ((255 - Double(c.alpha)) / 255 * 100).rounded() }

    static func gradientType(_ f: SlideFill) -> GradientType {
        switch f.path { case nil: return .linear; case .circle?: return .radial; default: return .rectangular }
    }

    /// `f` as a gradient of `type`: radial and rectangular ones radiate from the middle.
    static func withType(_ f: SlideFill, _ type: GradientType) -> SlideFill {
        var g = f
        g.path = type == .linear ? nil : (type == .radial ? .circle : .rect)
        g.fillTo = Rect.fromLTRB(0.5, 0.5, 0.5, 0.5)
        g.fillToExact = nil
        g.tile = nil
        return g
    }

    /// A stop added after stop `i`: halfway to the next one (or between the last two), in the colour the
    /// gradient has there. Returns the new stop's index.
    static func addStop(_ f: inout SlideFill, after i: Int) -> Int {
        guard f.stops.count >= 2 else { return i }
        let a = min(max(i, 0), f.stops.count - 2)
        let at = (f.stops[a].position + f.stops[a + 1].position) / 2
        f.stops.insert(.init(position: at, color: SlideFill.colorAt(f.stops, at)), at: a + 1)
        return a + 1
    }

    /// Stop `i` moved to `position` (0...1), the stops kept in order. Returns where it lands.
    static func moveStop(_ f: inout SlideFill, _ i: Int, to position: Double) -> Int {
        var s = f.stops[i]
        s.position = position
        f.stops.remove(at: i)
        let at = f.stops.firstIndex(where: { $0.position > position }) ?? f.stops.count
        f.stops.insert(s, at: at)
        return at
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
        let base = (fill?.color ?? deck.theme.backgroundFill.color ?? deck.theme.background).withAlpha(255)
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
        func comboRow<T: Equatable>(_ id: String, _ label: String, _ value: T, _ items: [(T, String)], _ apply: @escaping (T) -> Void) -> Widget {
            Row(children: [
                SizedBox(width: 110, height: nil, child: Text(label, style: caption)),
                SizedBox(width: 150, height: nil, child: ComboBox<T>(
                    key: ValueKey(id), value: value, items: items.map { ComboBoxItem<T>(value: $0.0, child: Text($0.1)) },
                    onChanged: { v in if let v { apply(v) } })),
            ])
        }
        var controls: [Widget] = []
        switch kind {
        case .solid:
            let colour = fill?.color ?? base
            controls = [
                hexRow("bg.color", "Colour (hex)", colour) { c in deck.setBackground(SlideFill(color: c.withAlpha(colour.alpha))) }, gap(6),
                numRow("bg.transparency", "Transparency", Self.transparency(colour), unit: "%", 0...100) { t in
                    deck.setBackground(SlideFill(color: Self.transparent(colour, t)))
                },
            ]
        case .gradient:
            if let f = fill {
                let i = min(_stop, f.stops.count - 1)
                let stop = f.stops[i]
                let type = Self.gradientType(f)
                func with(_ edit: (inout SlideFill) -> Void) { var g = f; edit(&g); g.color = g.stops.first?.color; deck.setBackground(g) }
                controls = [
                    comboRow("bg.gradtype", "Type", type, [(.linear, "Linear"), (.radial, "Radial"), (.rectangular, "Rectangular")]) { t in
                        var g = Self.withType(f, t); g.color = g.stops.first?.color; deck.setBackground(g)
                    }, gap(6),
                ] + (type == .linear ? [numRow("bg.angle", "Angle", f.angle, unit: "°", -360...360) { a in with { $0.angle = a } }, gap(10)] : [gap(4)]) + [
                    Text("Gradient stops", style: caption), gap(4),
                    comboRow("bg.stop", "Stop", i, f.stops.indices.map { ($0, "Stop \($0 + 1) of \(f.stops.count)") }) { [weak self] n in
                        self?.setState { self?._stop = n }
                    }, gap(6),
                    hexRow("bg.stop.color", "Colour (hex)", stop.color) { c in with { $0.stops[i].color = c.withAlpha(stop.color.alpha) } }, gap(6),
                    numRow("bg.stop.position", "Position", (stop.position * 100).rounded(), unit: "%", 0...100) { [weak self] p in
                        var g = f; let at = Self.moveStop(&g, i, to: p / 100); g.color = g.stops.first?.color
                        self?._stop = at; deck.setBackground(g)
                    }, gap(6),
                    numRow("bg.stop.transparency", "Transparency", Self.transparency(stop.color), unit: "%", 0...100) { t in
                        with { $0.stops[i].color = Self.transparent(stop.color, t) }
                    }, gap(6),
                    Row(children: [
                        Button(key: ValueKey("bg.stop.add"), onPressed: { [weak self] in
                            var g = f; let at = Self.addStop(&g, after: i); g.color = g.stops.first?.color
                            self?._stop = at; deck.setBackground(g)
                        }, child: Text("Add stop")),
                        SizedBox(width: 8, height: nil, child: nil),
                        Button(key: ValueKey("bg.stop.remove"), onPressed: f.stops.count > 2 ? { [weak self] in
                            var g = f; g.stops.remove(at: i); g.color = g.stops.first?.color
                            self?._stop = max(0, i - 1); deck.setBackground(g)
                        } : nil, child: Text("Remove stop")),
                    ]),
                ]
            }
        case .pattern:
            if let f = fill {
                let fg = f.patternFg ?? deck.theme.text, bg = f.patternBg ?? base
                let chosen = f.patternPreset
                let tiles = Wrap(children: Self.patterns.map { preset in
                    Tooltip(message: preset, child: GestureDetector(
                        key: ValueKey("bg.pattern.\(preset)"),
                        onTap: { deck.setBackground(PatternFill.fill(preset: preset, foreground: fg, background: bg)) },
                        child: Padding(padding: EdgeInsets(left: 0, top: 0, right: 2, bottom: 2), child: DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: preset == chosen ? fluent.accentColor.normal : fluent.resources.controlStrokeColorDefault,
                                                                         width: preset == chosen ? 2 : 1)),
                            child: SizedBox(width: 26, height: 26, child: CustomPaint(painter: PatternSwatchPainter(preset: preset, fg: fg, bg: bg)))))))
                })
                controls = [
                    tiles, gap(8),
                    hexRow("bg.pattern.fg", "Foreground", fg) { c in deck.setBackground(PatternFill.fill(preset: chosen ?? "pct5", foreground: c, background: bg)) }, gap(6),
                    hexRow("bg.pattern.bg", "Background", bg) { c in deck.setBackground(PatternFill.fill(preset: chosen ?? "pct5", foreground: fg, background: c)) },
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
            radio("bg.kind.pattern", "Pattern fill", .pattern) { PatternFill.fill(preset: "pct5", foreground: deck.theme.text, background: base) }, gap(4),
            radio("bg.kind.theme", "Theme background", .theme) { nil }, gap(8),
            Checkbox(key: ValueKey("bg.hide"), checked: deck.currentSlide.hideMasterShapes, onChanged: { (v: Bool?) in
                deck.setHideBackgroundGraphics(v ?? false)
            }, content: Text("Hide background graphics")), gap(14),
        ] + controls + [
            gap(16),
            Row(children: [
                Button(key: ValueKey("bg.all"), onPressed: { deck.applyBackgroundToAll() }, child: Text("Apply to All")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("bg.reset"), onPressed: { deck.resetBackground() }, child: Text("Reset Background")),
            ]),
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

/// One pattern preset in its two colours, as the Pattern fill grid shows it: its 8×8 cell, 3 px a pixel.
final class PatternSwatchPainter: CustomPainter {
    let preset: String
    let fg: Color
    let bg: Color
    init(preset: String, fg: Color, bg: Color) { self.preset = preset; self.fg = fg; self.bg = bg; super.init() }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let p = Paint()
        p.color = bg
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p)
        guard let rows = PatternFill.rows[preset] else { return }
        p.color = fg
        let cell = 3.0
        for y in 0 ..< Int((size.height / cell).rounded(.up)) {
            let bits = rows[y % 8]
            for x in 0 ..< Int((size.width / cell).rounded(.up)) where bits & (1 << UInt8(x % 8)) != 0 {
                canvas.drawRect(Rect.fromLTWH(Double(x) * cell, Double(y) * cell, cell, cell), p)
            }
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let o = oldDelegate as? PatternSwatchPainter else { return true }
        return o.preset != preset || o.fg != fg || o.bg != bg
    }
}
