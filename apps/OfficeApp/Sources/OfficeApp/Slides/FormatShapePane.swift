// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Format Shape pane (S-SH-6), Size & Properties: height, width, turn, the aspect lock, the
// position of the top left corner, and the alt text. Each field applies on Enter as one undoable
// step; a value that is not a number puts the old one back. It follows the selection and the
// deck, so dragging a shape updates its numbers.

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

final class FormatShapePane: StatefulWidget {
    let deck: DeckController
    let onClose: () -> Void

    init(deck: DeckController, onClose: @escaping () -> Void) {
        self.deck = deck
        self.onClose = onClose
        super.init()
    }

    override func createState() -> State<StatefulWidget> { FormatShapePaneState() }
}

final class FormatShapePaneState: State<StatefulWidget> {
    private var _w: FormatShapePane { widget as! FormatShapePane }
    private var _controllers: [String: TextEditingController] = [:]
    private var _shown: [String: String] = [:]

    /// A number as the field shows it: at most two decimals, no trailing zeros.
    static func text(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        if r == r.rounded() { return "\(Int(r))" }
        return "\(r)"
    }

    /// The number in what was typed: spaces, degree signs and a trailing "pt" dropped.
    static func digits(_ text: String) -> String {
        var t = ""
        for ch in text where ch != " " && ch != "°" { t.append(ch) }
        if t.hasSuffix("pt") { t.removeLast(2) }
        if t.hasSuffix("%") { t.removeLast() }
        return t
    }

    /// Six upper-case hex digits of a colour, without its transparency.
    /// The dash styles the pane offers, in the order its button steps through them (preset name, label).
    static let arrowKinds: [(String?, String)] = [(nil, "None"), ("triangle", "Arrow"), ("arrow", "Open arrow"), ("stealth", "Stealth arrow"),
                                                  ("diamond", "Diamond"), ("oval", "Oval")]
    static let dashStyles: [(String?, String)] = [(nil, "Solid"), ("sysDot", "Round dot"), ("sysDash", "Square dot"),
                                                  ("dash", "Dash"), ("dashDot", "Dash dot"), ("lgDash", "Long dash"), ("lgDashDot", "Long dash dot")]

    static func hex(_ c: Color) -> String {
        let h = String(c.value & 0xFFFFFF, radix: 16, uppercase: true)
        return String(repeating: "0", count: 6 - h.count) + h
    }

    /// The colour bits in "#RRGGBB" or "RRGGBB"; nil when it is not six hex digits.
    static func parseHex(_ text: String) -> Int? {
        var t = ""
        for ch in text where ch != " " && ch != "#" { t.append(ch) }
        guard t.count == 6, let v = Int(t, radix: 16) else { return nil }
        return v
    }

    /// The controller for `id`, its text brought up to `value` when that has changed since it was last set.
    private func _field(_ id: String, _ value: String) -> TextEditingController {
        let c = _controllers[id] ?? { let n = TextEditingController(text: value); _controllers[id] = n; _shown[id] = value; return n }()
        if _shown[id] != value { c.text = value; _shown[id] = value }
        return c
    }

    /// The common value of `get` over the selection, or "" when the shapes differ.
    /// PowerPoint's default outer shadow: black at 60% transparency, 4 pt blur, 3 pt out at 45 degrees.
    static let defaultShadow = CharShadow(color: Color(0x66000000), dx: 3 * 0.7071, dy: 3 * 0.7071, blur: 4)
    static func angle(_ s: CharShadow) -> Double {
        var d = atan2(s.dy, s.dx) * 180 / .pi
        if d < 0 { d += 360 }
        return d
    }

    private func _common(_ get: (SlideShape) -> Double) -> String {
        let deck = _w.deck
        guard let first = deck.selection.first.map(get) else { return "" }
        return deck.selection.allSatisfy({ abs(get($0) - first) < 0.005 }) ? Self.text(first) : ""
    }

    override func build(_ context: any BuildContext) -> Widget {
        AnimatedBuilder(animation: _w.deck, builder: { [self] ctx, _ in _panel(ctx) })
    }

    private func _panel(_ context: any BuildContext) -> Widget {
        let deck = _w.deck
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        let some = !deck.selection.isEmpty
        let box = deck.selection.reduce(nil as Rect?) { acc, s in
            acc.map { Rect.fromLTRB(min($0.left, s.frame.left), min($0.top, s.frame.top),
                                    max($0.right, s.frame.right), max($0.bottom, s.frame.bottom)) } ?? s.frame
        }
        func gap(_ h: Double) -> Widget { SizedBox(width: nil, height: h, child: nil) }
        /// A numeric row: applies on Enter or on leaving the box (Tab, a click elsewhere), as PowerPoint's pane does, and
        /// puts the shown value back when the text is not a number.
        func row(_ id: String, _ label: String, _ shown: String, min lo: Double, unit: String? = nil, _ apply: @escaping (Double) -> Void) -> Widget {
            let c = _field(id, shown)
            let submit: (String) -> Void = { [weak self] text in
                let t = FormatShapePaneState.digits(text)
                if let v = Double(t), v >= lo, v < 100000 { apply(v) }
                else { c.text = shown; self?._shown[id] = shown }
            }
            return Row(children: [
                SizedBox(width: 110, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 90, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: c,
                    onSubmitted: submit, enabled: some,
                    onFocusChanged: { focused in if !focused, c.text != shown { submit(c.text) } })),
                SizedBox(width: 6, height: nil, child: Text(unit ?? (id.hasSuffix("rotation") ? "°" : "pt"), style: caption)),
            ])
        }
        /// A colour row: six hex digits, applied on Enter, the shape's own transparency kept.
        func hexRow(_ id: String, _ label: String, _ colour: Color?, enabled: Bool, _ apply: @escaping (Color) -> Void) -> Widget {
            let shown = colour.map { Self.hex($0) } ?? ""
            let c = _field(id, shown)
            let submit: (String) -> Void = { [weak self] text in
                if let v = Self.parseHex(text) { apply(Color((colour.map { Int64($0.value) & 0xFF00_0000 } ?? Int64(0xFF00_0000)) | Int64(v))) }
                else { c.text = shown; self?._shown[id] = shown }
            }
            return Row(children: [
                SizedBox(width: 110, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 90, height: Chrome.fieldHeight, child: FluentTextBox(
                    controller: c,
                    onSubmitted: submit, enabled: enabled,
                    onFocusChanged: { focused in if !focused, c.text != shown { submit(c.text) } })),
            ])
        }
        let drawn = deck.selection.filter { $0.preset?.isLine != true }
        let fillOn = drawn.contains { $0.fill != nil }
        let lineOn = deck.selection.contains { $0.outline != nil }
        let first = deck.selection.first
        let transparency = first?.fill.map { Self.text(100 - Double($0.value >> 24) / 255 * 100) } ?? ""
        let shadow = first?.shadow
        let shadowOn = some && shadow != nil
        func shadowShown(_ f: (CharShadow) -> String) -> String { shadow.map(f) ?? "" }
        func editShadow(_ f: (inout CharShadow) -> Void) {
            guard var sh = deck.selection.first?.shadow else { return }
            f(&sh); deck.setShadow(sh)
        }
        let alt = _field("fmt.alt", deck.selectedAltText ?? "")
        let hasPicture = deck.selection.contains { $0.picture != nil }
        let locked = some && deck.selection.allSatisfy { $0.aspectLocked }
        let header = Row(children: [
            Expanded(child: Text("Format Shape", style: fluent.typography.bodyStrong)),
            Padding(key: ValueKey("fmt.close"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                    child: IconButton(icon: Icon(FluentSystemIcons.close, size: 14, color: fluent.resources.textFillColorPrimary),
                                      onPressed: _w.onClose)),
        ])
        var fx: [Widget] = []
        fx.append(Text("Effects", style: fluent.typography.bodyStrong)); fx.append(gap(10))
        fx.append(Text("Shadow", style: caption)); fx.append(gap(4))
        fx.append(Checkbox(key: ValueKey("fmt.shadow.on"), checked: shadowOn, onChanged: { (v: Bool?) in
            guard some else { return }
            deck.setShadow((v ?? false) ? Self.defaultShadow : nil)
        }, content: Text("Outer shadow")))
        fx.append(gap(6))
        let shadowAlpha: String = shadowShown { (sh: CharShadow) -> String in Self.text(100 - Double(sh.color.value >> 24) / 255 * 100) }
        fx.append(row("fmt.shadow.transparency", "Transparency", shadowAlpha, min: 0, unit: "%") { (v: Double) in
            let alpha = Int((max(0, min(100, 100 - v)) / 100 * 255).rounded())
            editShadow { (sh: inout CharShadow) in sh.color = Color((alpha << 24) | (sh.color.value & 0xFFFFFF)) }
        })
        fx.append(gap(6))
        fx.append(row("fmt.shadow.blur", "Blur", shadowShown { (sh: CharShadow) -> String in Self.text(sh.blur) }, min: 0) { (v: Double) in
            editShadow { (sh: inout CharShadow) in sh.blur = v }
        })
        fx.append(gap(6))
        fx.append(row("fmt.shadow.distance", "Distance", shadowShown { (sh: CharShadow) -> String in Self.text(hypot(sh.dx, sh.dy)) }, min: 0) { (v: Double) in
            editShadow { (sh: inout CharShadow) in let a = atan2(sh.dy, sh.dx); sh.dx = cos(a) * v; sh.dy = sin(a) * v }
        })
        fx.append(gap(6))
        fx.append(row("fmt.shadow.angle", "Angle", shadowShown { (sh: CharShadow) -> String in Self.text(Self.angle(sh)) }, min: 0) { (v: Double) in
            editShadow { (sh: inout CharShadow) in let d = hypot(sh.dx, sh.dy); let a = v * Double.pi / 180; sh.dx = cos(a) * d; sh.dy = sin(a) * d }
        })
        fx.append(gap(14))
        fx.append(Text("3-D rotation", style: caption)); fx.append(gap(4))
        let camera = first.map { $0.camera ?? ($0.scene3d?.cameraName.isEmpty == false ? $0.scene3d!.cameraName : "orthographicFront") } ?? "orthographicFront"
        fx.append(Row(children: [
            SizedBox(width: 110, height: nil, child: Text("Preset", style: caption)),
            SizedBox(key: ValueKey("fmt.rotation3d"), width: 120, height: 30, child: Button(onPressed: some ? {
                let presets = Extrusion.rotationPresets
                let at = presets.firstIndex { $0.0 == camera } ?? 0
                deck.setCamera(presets[(at + 1) % presets.count].0)
            } : nil, child: Text(Extrusion.rotationPresets.first { $0.0 == camera }?.1 ?? camera))),
        ]))
        fx.append(gap(14))
        // Glow and soft edges: what the ribbon's Shape Effects presets set, with the size typed.
        let glowOn = some && first?.glowRadius != nil
        fx.append(Text("Glow", style: caption)); fx.append(gap(4))
        fx.append(Checkbox(key: ValueKey("fmt.glow.on"), checked: glowOn, onChanged: { (v: Bool?) in
            guard some else { return }
            deck.setGlow(radius: (v ?? false) ? 10 : nil, color: ShapeEffectPresets.glowColor(deck.theme.accents[0]))
        }, content: Text("Glow")))
        fx.append(gap(6))
        fx.append(row("fmt.glow.size", "Size", first?.glowRadius.map { Self.text($0) } ?? "", min: 0) { (v: Double) in
            guard let f = deck.selection.first else { return }
            deck.setGlow(radius: v > 0 ? v : nil, color: f.glowColor ?? ShapeEffectPresets.glowColor(deck.theme.accents[0]))
        })
        fx.append(gap(14))
        fx.append(Text("Soft edges", style: caption)); fx.append(gap(4))
        fx.append(row("fmt.softedge.size", "Size", first?.softEdge.map { Self.text($0) } ?? "", min: 0) { (v: Double) in
            deck.setSoftEdge(v > 0 ? v : nil)
        })
        fx.append(gap(14))
        let effects = Column(crossAxisAlignment: .start, children: fx)
        // Gradient fill: one row per stop, add/remove, reverse and the angle.
        var gr: [Widget] = [
            Checkbox(key: ValueKey("fmt.grad.on"), checked: deck.selectionGradient != nil, onChanged: { v in
                guard !drawn.isEmpty else { return }
                if v ?? false { deck.editGradient { _ in } }
                else { deck.setFill(drawn.first?.fill ?? deck.theme.accents[0]) }
            }, content: Text("Gradient fill")),
        ]
        if let g = deck.selectionGradient {
            gr.append(gap(6))
            for (i, stop) in g.stops.enumerated() {
                let hexId = "fmt.grad.color.\(i)", posId = "fmt.grad.pos.\(i)"
                let hexShown = Self.hex(stop.color), posShown = Self.text(stop.position * 100)
                let hc = _field(hexId, hexShown), pc = _field(posId, posShown)
                gr.append(Row(children: [
                    SizedBox(width: 44, height: nil, child: Text("Stop \(i + 1)", style: caption)),
                    SizedBox(key: ValueKey(hexId), width: 82, height: Chrome.fieldHeight, child: FluentTextBox(
                        controller: hc,
                        onSubmitted: { [weak self] text in
                            if let v = Self.parseHex(text) {
                                deck.editGradient { gg in
                                    guard gg.stops.indices.contains(i) else { return }
                                    gg.stops[i].color = Color((Int64(gg.stops[i].color.value) & 0xFF00_0000) | Int64(v))
                                }
                            } else { hc.text = hexShown; self?._shown[hexId] = hexShown }
                        })),
                    SizedBox(width: 6, height: nil, child: nil),
                    SizedBox(key: ValueKey(posId), width: 50, height: Chrome.fieldHeight, child: FluentTextBox(
                        controller: pc,
                        onSubmitted: { [weak self] text in
                            if let v = Double(Self.digits(text)), v >= 0, v <= 100 {
                                deck.editGradient { gg in if gg.stops.indices.contains(i) { gg.stops[i].position = v / 100 } }
                            } else { pc.text = posShown; self?._shown[posId] = posShown }
                        })),
                    SizedBox(width: 14, height: nil, child: Text("%", style: caption)),
                    IconButton(key: ValueKey("fmt.grad.remove.\(i)"), icon: Icon(FluentSystemIcons.close, size: 12, color: fluent.resources.textFillColorPrimary),
                               onPressed: g.stops.count > 2 ? { deck.removeGradientStop(at: i) } : nil),
                ]))
                gr.append(gap(4))
            }
            gr.append(Row(children: [
                Button(key: ValueKey("fmt.grad.add"), onPressed: { deck.addGradientStop() }, child: Text("Add stop")),
                SizedBox(width: 8, height: nil, child: nil),
                Button(key: ValueKey("fmt.grad.reverse"), onPressed: { deck.reverseGradient() }, child: Text("Reverse")),
            ]))
            gr.append(gap(6))
            gr.append(row("fmt.grad.angle", "Angle", Self.text(g.angle), min: -360, unit: "°") { (v: Double) in deck.editGradient { $0.angle = v } })
        }
        gr.append(gap(14))
        let gradient = Column(crossAxisAlignment: .start, children: gr)
        // Picture: its transparency, by slider or typed percent (PowerPoint's Format Picture > Picture Transparency).
        let pictureAlpha = deck.selection.first { $0.picture != nil }?.pictureAlpha
        let picture: Widget = pictureAlpha.map { a in
            let percent = ((1 - a) * 100).rounded()
            return Column(crossAxisAlignment: .start, children: [
                Text("Picture", style: fluent.typography.bodyStrong), gap(10),
                Text("Picture Transparency", style: caption), gap(4),
                SizedBox(key: ValueKey("fmt.pic.alpha.slider"), width: 240, height: nil, child: Slider(
                    value: percent, onChanged: { deck.setPictureTransparencyLive($0.rounded()) },
                    onChangeEnd: { _ in deck.endPictureTransparencyDrag() }, min: 0, max: 100)), gap(6),
                row("fmt.pic.alpha", "Transparency", Self.text(percent), min: 0, unit: "%") { deck.setPictureTransparency(min(100, $0)) },
                gap(14),
            ])
        } ?? SizedBox(width: nil, height: 0, child: nil)
        let body = Column(crossAxisAlignment: .start, children: [
            Text("Fill & Line", style: fluent.typography.bodyStrong), gap(10),
            Text("Fill", style: caption), gap(4),
            Checkbox(key: ValueKey("fmt.fill.none"), checked: some && !fillOn, onChanged: { v in
                guard !drawn.isEmpty else { return }
                if v ?? false { deck.setFill(nil) } else { deck.setFill(deck.theme.accents[0], scheme: "accent1") }
            }, content: Text("No fill")), gap(6),
            hexRow("fmt.fill.color", "Colour (hex)", drawn.first?.fill, enabled: fillOn) { deck.setFill($0) }, gap(6),
            row("fmt.fill.transparency", "Transparency", transparency, min: 0, unit: "%") { deck.setFillTransparency($0) }, gap(10),
            gradient,
            Text("Line", style: caption), gap(4),
            Checkbox(key: ValueKey("fmt.line.none"), checked: some && !lineOn, onChanged: { v in
                guard some else { return }
                if v ?? false { deck.setOutline(nil) } else { deck.setOutline(first?.fill.map { Color(Int64(0xFF00_0000) | Int64($0.value & 0xFFFFFF)) } ?? deck.theme.accents[0]) }
            }, content: Text("No line")), gap(6),
            hexRow("fmt.line.color", "Colour (hex)", first?.outline, enabled: lineOn) { deck.setOutline($0) }, gap(6),
            row("fmt.line.width", "Width", _common { $0.outlineWidth }, min: 0) { deck.setOutlineWidth($0) }, gap(6),
            Row(children: [
                SizedBox(width: 110, height: nil, child: Text("Dash type", style: caption)),
                SizedBox(key: ValueKey("fmt.line.dash"), width: 120, height: 30, child: Button(onPressed: lineOn ? {
                    let styles = Self.dashStyles
                    let at = styles.firstIndex { $0.0 == first?.outlineDash } ?? 0
                    deck.setOutlineDash(styles[(at + 1) % styles.count].0)
                } : nil, child: Text(Self.dashStyles.first { $0.0 == first?.outlineDash }?.1 ?? first?.outlineDash ?? "Solid"))),
            ]), gap(6),
            Row(children: [
                SizedBox(width: 110, height: nil, child: Text("Arrow start", style: caption)),
                SizedBox(key: ValueKey("fmt.line.head"), width: 120, height: 30, child: Button(onPressed: lineOn ? {
                    let at = Self.arrowKinds.firstIndex { $0.0 == first?.headEnd?.kind } ?? 0
                    deck.setLineEnd(start: true, kind: Self.arrowKinds[(at + 1) % Self.arrowKinds.count].0)
                } : nil, child: Text(Self.arrowKinds.first { $0.0 == first?.headEnd?.kind }?.1 ?? first?.headEnd?.kind ?? "None"))),
            ]), gap(6),
            Row(children: [
                SizedBox(width: 110, height: nil, child: Text("Arrow end", style: caption)),
                SizedBox(key: ValueKey("fmt.line.tail"), width: 120, height: 30, child: Button(onPressed: lineOn ? {
                    let at = Self.arrowKinds.firstIndex { $0.0 == first?.tailEnd?.kind } ?? 0
                    deck.setLineEnd(start: false, kind: Self.arrowKinds[(at + 1) % Self.arrowKinds.count].0)
                } : nil, child: Text(Self.arrowKinds.first { $0.0 == first?.tailEnd?.kind }?.1 ?? first?.tailEnd?.kind ?? "None"))),
            ]), gap(14),
            picture, Text("Size & Properties", style: fluent.typography.bodyStrong), gap(10),
            Text("Size", style: caption), gap(4),
            row("fmt.height", "Height", _common { $0.frame.height }, min: 1) { deck.setSize(height: $0) }, gap(6),
            row("fmt.width", "Width", _common { $0.frame.width }, min: 1) { deck.setSize(width: $0) }, gap(6),
            row("fmt.scale.height", "Scale height", _common { s in s.scaleBase.map { s.frame.height / $0.height * 100 } ?? 100 }, min: 1, unit: "%") { deck.setScale(height: $0) }, gap(6),
            row("fmt.scale.width", "Scale width", _common { s in s.scaleBase.map { s.frame.width / $0.width * 100 } ?? 100 }, min: 1, unit: "%") { deck.setScale(width: $0) }, gap(6),
            row("fmt.rotation", "Rotation", _common { $0.rotation }, min: -360) { deck.setRotation($0) }, gap(6),
            Checkbox(key: ValueKey("fmt.lock"), checked: locked, onChanged: { v in
                if some { deck.setAspectLock(v ?? false) }
            }, content: Text("Lock aspect ratio")), gap(14),
            Text("Position (top left corner)", style: caption), gap(4),
            row("fmt.left", "Horizontal", box.map { Self.text($0.left) } ?? "", min: -100000) { deck.setPosition(left: $0) }, gap(6),
            row("fmt.top", "Vertical", box.map { Self.text($0.top) } ?? "", min: -100000) { deck.setPosition(top: $0) }, gap(14),
            Text("Alt text", style: caption), gap(4),
            SizedBox(key: ValueKey("fmt.alt"), width: 240, height: Chrome.fieldHeight, child: FluentTextBox(
                controller: alt, placeholderText: hasPicture ? "Describe the picture" : "Pictures only",
                onSubmitted: { text in deck.setAltText(text) }, enabled: hasPicture)), gap(14),
            effects,
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
