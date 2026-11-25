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
        /// A numeric row: applies on Enter, and puts the shown value back when the text is not a number.
        func row(_ id: String, _ label: String, _ shown: String, min lo: Double, unit: String? = nil, _ apply: @escaping (Double) -> Void) -> Widget {
            let c = _field(id, shown)
            return Row(children: [
                SizedBox(width: 110, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 90, height: 30, child: FluentTextBox(
                    controller: c,
                    onSubmitted: { [weak self] text in
                        let t = FormatShapePaneState.digits(text)
                        if let v = Double(t), v >= lo, v < 100000 { apply(v) }
                        else { c.text = shown; self?._shown[id] = shown }
                    }, enabled: some)),
                SizedBox(width: 6, height: nil, child: Text(unit ?? (id.hasSuffix("rotation") ? "°" : "pt"), style: caption)),
            ])
        }
        /// A colour row: six hex digits, applied on Enter, the shape's own transparency kept.
        func hexRow(_ id: String, _ label: String, _ colour: Color?, enabled: Bool, _ apply: @escaping (Color) -> Void) -> Widget {
            let shown = colour.map { Self.hex($0) } ?? ""
            let c = _field(id, shown)
            return Row(children: [
                SizedBox(width: 110, height: nil, child: Text(label, style: caption)),
                SizedBox(key: ValueKey(id), width: 90, height: 30, child: FluentTextBox(
                    controller: c,
                    onSubmitted: { [weak self] text in
                        if let v = Self.parseHex(text) { apply(Color((colour.map { $0.value & 0xFF000000 } ?? 0xFF000000) | v)) }
                        else { c.text = shown; self?._shown[id] = shown }
                    }, enabled: enabled)),
            ])
        }
        let drawn = deck.selection.filter { $0.preset?.isLine != true }
        let fillOn = drawn.contains { $0.fill != nil }
        let lineOn = deck.selection.contains { $0.outline != nil }
        let first = deck.selection.first
        let transparency = first?.fill.map { Self.text(100 - Double($0.value >> 24) / 255 * 100) } ?? ""
        let alt = _field("fmt.alt", deck.selectedAltText ?? "")
        let hasPicture = deck.selection.contains { $0.picture != nil }
        let locked = some && deck.selection.allSatisfy { $0.aspectLocked }
        let header = Row(children: [
            Expanded(child: Text("Format Shape", style: fluent.typography.bodyStrong)),
            Padding(key: ValueKey("fmt.close"), padding: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                    child: IconButton(icon: Icon(FluentSystemIcons.close, size: 14, color: fluent.resources.textFillColorPrimary),
                                      onPressed: _w.onClose)),
        ])
        let body = Column(crossAxisAlignment: .start, children: [
            Text("Fill & Line", style: fluent.typography.bodyStrong), gap(10),
            Text("Fill", style: caption), gap(4),
            Checkbox(key: ValueKey("fmt.fill.none"), checked: some && !fillOn, onChanged: { v in
                guard !drawn.isEmpty else { return }
                if v ?? false { deck.setFill(nil) } else { deck.setFill(deck.theme.accents[0], scheme: "accent1") }
            }, content: Text("No fill")), gap(6),
            hexRow("fmt.fill.color", "Colour (hex)", drawn.first?.fill, enabled: fillOn) { deck.setFill($0) }, gap(6),
            row("fmt.fill.transparency", "Transparency", transparency, min: 0, unit: "%") { deck.setFillTransparency($0) }, gap(14),
            Text("Line", style: caption), gap(4),
            Checkbox(key: ValueKey("fmt.line.none"), checked: some && !lineOn, onChanged: { v in
                guard some else { return }
                if v ?? false { deck.setOutline(nil) } else { deck.setOutline(first?.fill.map { Color(0xFF000000 | ($0.value & 0xFFFFFF)) } ?? deck.theme.accents[0]) }
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
            ]), gap(14),
            Text("Size & Properties", style: fluent.typography.bodyStrong), gap(10),
            Text("Size", style: caption), gap(4),
            row("fmt.height", "Height", _common { $0.frame.height }, min: 1) { deck.setSize(height: $0) }, gap(6),
            row("fmt.width", "Width", _common { $0.frame.width }, min: 1) { deck.setSize(width: $0) }, gap(6),
            row("fmt.rotation", "Rotation", _common { $0.rotation }, min: -360) { deck.setRotation($0) }, gap(6),
            Checkbox(key: ValueKey("fmt.lock"), checked: locked, onChanged: { v in
                if some { deck.setAspectLock(v ?? false) }
            }, content: Text("Lock aspect ratio")), gap(14),
            Text("Position (top left corner)", style: caption), gap(4),
            row("fmt.left", "Horizontal", box.map { Self.text($0.left) } ?? "", min: -100000) { deck.setPosition(left: $0) }, gap(6),
            row("fmt.top", "Vertical", box.map { Self.text($0.top) } ?? "", min: -100000) { deck.setPosition(top: $0) }, gap(14),
            Text("Alt text", style: caption), gap(4),
            SizedBox(key: ValueKey("fmt.alt"), width: 240, height: 30, child: FluentTextBox(
                controller: alt, placeholderText: hasPicture ? "Describe the picture" : "Pictures only",
                onSubmitted: { text in deck.setAltText(text) }, enabled: hasPicture)),
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
