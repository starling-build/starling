// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The shared colour picker (U-shared). The model is `ColorChoice` (what a
// document must be told: automatic, none, a plain RGB, or a THEME colour with
// its luminance change, so a theme-aware file keeps its link to the theme) and
// `ColorMath` (the OOXML lumMod/lumOff arithmetic that makes the tints). The
// panel is `ColorPicker`: automatic / no colour, the theme grid, the standard
// colours, recent colours, and "More Colors…", which opens `CustomColorDialog`.

import Flutter
import FlutterSwiftBridge

/// What the user chose.
enum ColorChoice: Equatable {
    case automatic
    case none
    case rgb(UInt32)
    /// A theme slot (0…9: Background 1, Text 1, Background 2, Text 2, Accent 1…6) with OOXML's `lumMod` and
    /// `lumOff` in percent (a plain slot colour is 100 / 0).
    case theme(slot: Int, lumMod: Int, lumOff: Int)

    /// The colour to draw, given the document's theme colours (RRGGBB, in slot order); nil for automatic and none.
    func resolved(theme: [UInt32]) -> UInt32? {
        switch self {
        case .automatic, .none: return nil
        case .rgb(let c): return c
        case .theme(let slot, let mod, let off):
            guard slot >= 0, slot < theme.count else { return nil }
            return ColorMath.adjusted(theme[slot], lumMod: mod, lumOff: off)
        }
    }
}

enum ColorMath {
    /// Office's default theme, slot order: Background 1, Text 1, Background 2, Text 2, Accent 1…6.
    static let officeTheme: [UInt32] = [0xFFFFFF, 0x000000, 0xE7E6E6, 0x44546A, 0x4472C4,
                                        0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47]
    static let slotNames = ["Background 1", "Text 1", "Background 2", "Text 2",
                            "Accent 1", "Accent 2", "Accent 3", "Accent 4", "Accent 5", "Accent 6"]

    /// The five tints under a slot, top to bottom, as (lumMod, lumOff, name). Background 1 darkens and Text 1
    /// lightens, in steps of their own; the rest are lighter 80/60/40 then darker 25/50.
    static func tints(slot: Int, base: UInt32) -> [(mod: Int, off: Int, name: String)] {
        if base == 0xFFFFFF { return [(95, 0, "Darker 5%"), (85, 0, "Darker 15%"), (75, 0, "Darker 25%"), (65, 0, "Darker 35%"), (50, 0, "Darker 50%")] }
        if base == 0x000000 { return [(50, 50, "Lighter 50%"), (65, 35, "Lighter 35%"), (75, 25, "Lighter 25%"), (85, 15, "Lighter 15%"), (95, 5, "Lighter 5%")] }
        return [(20, 80, "Lighter 80%"), (40, 60, "Lighter 60%"), (60, 40, "Lighter 40%"), (75, 0, "Darker 25%"), (50, 0, "Darker 50%")]
    }

    static func toHSL(_ rgb: UInt32) -> (h: Double, s: Double, l: Double) {
        let r = Double((rgb >> 16) & 255) / 255, g = Double((rgb >> 8) & 255) / 255, b = Double(rgb & 255) / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
        guard mx != mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    static func fromHSL(_ h: Double, _ s: Double, _ l: Double) -> UInt32 {
        func hue(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        var r = l, g = l, b = l
        if s != 0 {
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
            r = hue(p, q, h + 1.0 / 3); g = hue(p, q, h); b = hue(p, q, h - 1.0 / 3)
        }
        func byte(_ v: Double) -> UInt32 { UInt32(min(255, max(0, (v * 255).rounded()))) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// OOXML `lumMod` / `lumOff` (percent) applied to `rgb`'s HSL luminance.
    static func adjusted(_ rgb: UInt32, lumMod: Int, lumOff: Int) -> UInt32 {
        if lumMod == 100 && lumOff == 0 { return rgb }
        let (h, s, l) = toHSL(rgb)
        return fromHSL(h, s, min(1, max(0, l * Double(lumMod) / 100 + Double(lumOff) / 100)))
    }

    /// "#RRGGBB", "RRGGBB" or "RGB" to RRGGBB; nil otherwise.
    static func parseHex(_ text: String) -> UInt32? {
        var s = text.trimmingWhitespace()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return v
    }

    static func hex(_ rgb: UInt32) -> String {
        let digits = Array("0123456789ABCDEF")
        var s = "#"
        for shift in stride(from: 20, through: 0, by: -4) { s.append(digits[Int((rgb >> UInt32(shift)) & 15)]) }
        return s
    }

    /// The ten standard colours, with their names.
    static let standard: [(rgb: UInt32, name: String)] = [
        (0xC00000, "Dark Red"), (0xFF0000, "Red"), (0xFFC000, "Orange"), (0xFFFF00, "Yellow"), (0x92D050, "Light Green"),
        (0x00B050, "Green"), (0x00B0F0, "Light Blue"), (0x0070C0, "Blue"), (0x002060, "Dark Blue"), (0x7030A0, "Purple")]
}

/// The most recently used colours, newest first, without repeats.
struct RecentColors {
    private(set) var list: [UInt32] = []
    let limit: Int
    init(limit: Int = 10) { self.limit = limit }
    mutating func use(_ rgb: UInt32) {
        list.removeAll { $0 == rgb }
        list.insert(rgb, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
    }
}

/// The picker panel. `onMore` is called for "More Colors…"; the owner shows `CustomColorDialog`.
final class ColorPicker: StatelessWidget {
    let theme: [UInt32]
    let recent: [UInt32]
    /// Labels for the two special entries; nil leaves the entry out.
    let automaticLabel: String?
    let noneLabel: String?
    let onChoose: (ColorChoice) -> Void
    let onMore: () -> Void

    init(theme: [UInt32] = ColorMath.officeTheme, recent: [UInt32] = [], automaticLabel: String? = nil, noneLabel: String? = nil,
         onChoose: @escaping (ColorChoice) -> Void, onMore: @escaping () -> Void) {
        self.theme = theme
        self.recent = recent
        self.automaticLabel = automaticLabel
        self.noneLabel = noneLabel
        self.onChoose = onChoose
        self.onMore = onMore
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func swatch(_ rgb: UInt32, _ tip: String, _ choice: ColorChoice) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 3, bottom: 3), child: Tooltip(
                message: tip,
                child: KeyboardRow(label: tip, activate: { [onChoose] in onChoose(choice) }, child: GestureDetector(onTap: { [onChoose] in onChoose(choice) }, behavior: .opaque, child: SizedBox(width: 18, height: 18, child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(Int64(0xFF000000 | UInt64(rgb))),
                        border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1))))))))
        }
        func entry(_ label: String, _ action: @escaping () -> Void) -> Widget {
            KeyboardRow(label: label, activate: action, child: GestureDetector(onTap: action, behavior: .opaque, child: Padding(
                padding: EdgeInsets(left: 2, top: 4, right: 2, bottom: 4), child: Text(label))))
        }
        // Rows of the grid: the base colours, then the five tints under each.
        var rows: [[Widget]] = Array(repeating: [], count: 6)
        for slot in 0..<min(10, theme.count) {
            let base = theme[slot], name = ColorMath.slotNames[slot]
            rows[0].append(swatch(base, name, .theme(slot: slot, lumMod: 100, lumOff: 0)))
            for (i, t) in ColorMath.tints(slot: slot, base: base).enumerated() {
                rows[i + 1].append(swatch(ColorMath.adjusted(base, lumMod: t.mod, lumOff: t.off), "\(name), \(t.name)",
                                          .theme(slot: slot, lumMod: t.mod, lumOff: t.off)))
            }
        }
        var items: [Widget] = []
        if let a = automaticLabel { items.append(entry(a) { [onChoose] in onChoose(.automatic) }) }
        if let n = noneLabel { items.append(entry(n) { [onChoose] in onChoose(.none) }) }
        items.append(Text("Theme Colors", style: caption))
        items.append(Column(crossAxisAlignment: .start, children: rows.map { Row(mainAxisSize: .min, children: $0) }))
        items.append(Chrome.vgap(6))
        items.append(Text("Standard Colors", style: caption))
        items.append(Row(mainAxisSize: .min, children: ColorMath.standard.map { swatch($0.rgb, $0.name, .rgb($0.rgb)) }))
        if !recent.isEmpty {
            items.append(Chrome.vgap(6))
            items.append(Text("Recent Colors", style: caption))
            items.append(Row(mainAxisSize: .min, children: recent.map { swatch($0, ColorMath.hex($0), .rgb($0)) }))
        }
        items.append(Chrome.vgap(6))
        items.append(entry("More Colors…") { [onMore] in onMore() })
        return Padding(padding: EdgeInsets(all: 8), child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: items))
    }
}

/// "More Colors…": a custom colour by hex or by red, green and blue (0–255), with a preview.
final class CustomColorDialog: StatefulWidget {
    let initial: UInt32
    let onOK: (UInt32) -> Void
    let onCancel: () -> Void
    init(initial: UInt32, onOK: @escaping (UInt32) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onOK = onOK
        self.onCancel = onCancel
        super.init()
    }
    override func createState() -> State<StatefulWidget> { CustomColorDialogState() }
}

final class CustomColorDialogState: State<StatefulWidget> {
    private var _w: CustomColorDialog { widget as! CustomColorDialog }
    private(set) var rgb: UInt32 = 0
    private let _hex = TextEditingController()
    private let _r = TextEditingController(), _g = TextEditingController(), _b = TextEditingController()

    override func initState() {
        super.initState()
        rgb = _w.initial
        sync(except: nil)
    }

    /// True while `sync` writes the fields: a field reports the new text as if
    /// typed, and acting on it would write over the field being typed in (a
    /// six-digit hex stopped at its third digit, read as the short form).
    private var _syncing = false

    /// Writes `rgb` into every field but the one being typed in.
    private func sync(except: TextEditingController?) {
        let fields: [(TextEditingController, String)] = [
            (_hex, ColorMath.hex(rgb)), (_r, String((rgb >> 16) & 255)), (_g, String((rgb >> 8) & 255)), (_b, String(rgb & 255))]
        _syncing = true
        defer { _syncing = false }
        for (c, s) in fields where c !== except { c.text = s }
    }

    private func typedHex(_ s: String) {
        guard !_syncing, let v = ColorMath.parseHex(s) else { return }
        setState { self.rgb = v; self.sync(except: self._hex) }
    }

    private func typedChannel(_ shift: UInt32, _ s: String) {
        guard !_syncing, let n = Int(s.trimmingWhitespace()), n >= 0, n <= 255 else { return }
        setState {
            self.rgb = (self.rgb & ~(255 << shift)) | UInt32(n) << shift
            self.sync(except: shift == 16 ? self._r : shift == 8 ? self._g : self._b)
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        func field(_ label: String, _ c: TextEditingController, _ width: Double, _ on: @escaping (String) -> Void) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 10, bottom: 0), child: Column(crossAxisAlignment: .start, children: [
                Text(label), Chrome.vgap(2),
                SizedBox(width: width, height: Chrome.fieldHeight, child: FluentTextBox(controller: c, onChanged: on)),
            ]))
        }
        let page = Column(crossAxisAlignment: .start, children: [
            Row(crossAxisAlignment: .end, children: [
                field("Hex", _hex, 100) { [weak self] in self?.typedHex($0) },
                field("Red", _r, 56) { [weak self] in self?.typedChannel(16, $0) },
                field("Green", _g, 56) { [weak self] in self?.typedChannel(8, $0) },
                field("Blue", _b, 56) { [weak self] in self?.typedChannel(0, $0) },
            ]),
            Chrome.vgap(12),
            Row(children: [
                Text("New"), Chrome.gap(8),
                SizedBox(width: 60, height: 24, child: DecoratedBox(decoration: BoxDecoration(color: Color(Int64(0xFF000000 | UInt64(rgb)))))),
                Chrome.gap(16), Text("Current"), Chrome.gap(8),
                SizedBox(width: 60, height: 24, child: DecoratedBox(decoration: BoxDecoration(color: Color(Int64(0xFF000000 | UInt64(_w.initial)))))),
            ]),
        ])
        return DialogShell(title: "More Colors", page: page, width: 420,
                           onOK: { [weak self] in guard let self else { return }; self._w.onOK(self.rgb) },
                           onCancel: { [weak self] in self?._w.onCancel() })
    }
}
