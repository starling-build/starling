// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// S-SH-4: Shape Fill and Shape Outline as PowerPoint draws them: the theme grid (ten colours, five tints under
// each), the standard colours, recent colours, No Fill / No Outline and More Colors…, in the shared ColorPicker.

import Flutter
import FlutterSwiftBridge

extension DeckTheme {
    /// The ten theme slots the picker shows, in Office's order: Background 1, Text 1, Background 2, Text 2, Accent 1…6.
    /// The deck's theme has no second background or text colour of its own, so Background 2 is the background
    /// pulled a tenth toward the text colour, and Text 2 is the theme's subtle text colour.
    var slots: [UInt32] {
        func rgb(_ c: Color) -> UInt32 { UInt32(truncatingIfNeeded: c.value) & 0xFFFFFF }
        func mix(_ a: UInt32, _ b: UInt32, _ f: Double) -> UInt32 {
            var out: UInt32 = 0
            for shift in [16, 8, 0] as [UInt32] {
                let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
                out |= UInt32((x + (y - x) * f).rounded()) << shift
            }
            return out
        }
        var s = [rgb(background), rgb(text), mix(rgb(background), rgb(text), 0.1), rgb(subtle)]
        for i in 0..<6 { s.append(i < accents.count ? rgb(accents[i]) : ColorMath.officeTheme[4 + i]) }
        return s
    }
}

/// A menu entry that holds the colour picker. A pick closes the menu, then reports the choice.
final class ColorGridMenuItem: MenuFlyoutItemBase {
    let theme: [UInt32]
    let recent: [UInt32]
    let noneLabel: String
    let onChoose: (ColorChoice) -> Void
    let onMore: () -> Void
    let onEyedropper: (() -> Void)?

    init(theme: [UInt32], recent: [UInt32], noneLabel: String,
         onChoose: @escaping (ColorChoice) -> Void, onMore: @escaping () -> Void, onEyedropper: (() -> Void)? = nil) {
        self.onEyedropper = onEyedropper
        self.theme = theme; self.recent = recent; self.noneLabel = noneLabel
        self.onChoose = onChoose; self.onMore = onMore
        super.init(key: ValueKey("shape-color-grid"))
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let close: () -> Void = {
            if let scope = FlyoutScope.maybeOf(context) { scope.close() } else { Navigator.maybeOf(context)?.maybePop() }
        }
        let picker = ColorPicker(theme: theme, recent: recent, noneLabel: noneLabel,
                                 onChoose: { [onChoose] c in close(); onChoose(c) },
                                 onMore: { [onMore] in close(); onMore() })
        guard let onEyedropper else { return picker }
        return Column(mainAxisSize: .min, crossAxisAlignment: .stretch) {
            picker
            GestureDetector(onTap: { close(); onEyedropper() }, child: Padding(
                padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 6),
                child: Text("Eyedropper", key: ValueKey("shape-eyedropper"))))
        }
    }
}

extension DeckController {
    /// Applies a colour picked in Shape Fill (`outline: false`) or Shape Outline. A plain accent keeps its link to the
    /// theme; any other pick is written as the colour it resolves to. Undoable like any fill change.
    func applyShapeColor(_ choice: ColorChoice, outline: Bool) {
        guard let rgb = choice.resolved(theme: theme.slots) else {
            if case .none = choice { outline ? setOutline(nil) : setFill(nil) }
            return
        }
        let color = Color(Int64(0xFF00_0000 | UInt64(rgb)))
        recentShapeColors.use(rgb)
        var scheme: String? = nil
        if case .theme(let slot, let mod, let off) = choice { scheme = SchemeColor.spec(slot: slot, mod: mod, off: off) }
        if outline { setOutline(color, scheme: scheme) } else { setFill(color, scheme: scheme) }
    }
}


/// A shape colour tied to a theme slot, as PowerPoint writes it: `<a:schemeClr val="accent2">` with
/// `lumMod`/`lumOff` children for a tint or shade. Held as "accent2" or "accent2|60000|40000", so a new
/// theme can recolour it.
enum SchemeColor {
    static let names = ["bg1", "tx1", "bg2", "tx2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6"]

    /// The spec for picker slot 0…9 with lumMod/lumOff in percent.
    static func spec(slot: Int, mod: Int, off: Int) -> String? {
        guard names.indices.contains(slot) else { return nil }
        return mod == 100 && off == 0 ? names[slot] : "\(names[slot])|\(mod * 1000)|\(off * 1000)"
    }

    /// Slot index and lumMod/lumOff in percent.
    static func parse(_ spec: String) -> (slot: Int, mod: Int, off: Int)? {
        let p = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let slot = names.firstIndex(of: p[0]) else { return nil }
        if p.count == 1 { return (slot, 100, 0) }
        guard p.count == 3, let m = Int(p[1]), let o = Int(p[2]) else { return nil }
        return (slot, m / 1000, o / 1000)
    }

    /// The spec of a fill that is a theme colour with at most lumMod/lumOff; nil for anything else.
    static func read(_ fill: XNode) -> String? {
        guard let c = fill.first("a:schemeClr"), let v = c["val"], let slot = names.firstIndex(of: v) else { return nil }
        var mod = 100000, off = 0
        for k in c.children {
            guard let n = k["val"].flatMap(Int.init) else { return nil }
            switch k.name {
            case "a:lumMod": mod = n
            case "a:lumOff": off = n
            default: return nil
            }
        }
        return mod == 100000 && off == 0 ? names[slot] : "\(names[slot])|\(mod)|\(off)"
    }

    static func xml(_ spec: String, alpha: Int = 255) -> String? {
        let p = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard names.contains(p[0]) else { return nil }
        var kids = ""
        if p.count == 3 { kids += "<a:lumMod val=\"\(p[1])\"/><a:lumOff val=\"\(p[2])\"/>" }
        if alpha < 255 { kids += "<a:alpha val=\"\(PptxText.alphaVal(alpha))\"/>" }
        return "<a:solidFill><a:schemeClr val=\"\(p[0])\">\(kids)</a:schemeClr></a:solidFill>"
    }

    static func resolve(_ spec: String, slots: [UInt32]) -> Color? {
        guard let (slot, mod, off) = parse(spec), slots.indices.contains(slot) else { return nil }
        let rgb = mod == 100 && off == 0 ? slots[slot] : ColorMath.adjusted(slots[slot], lumMod: mod, lumOff: off)
        return Color(Int64(0xFF00_0000 | UInt64(rgb)))
    }
}

extension DeckController {
    /// The colour the slide shows at `point` (slide points), as the eyedropper reads it: the slide is drawn
    /// whole at one pixel per point and the pixel under the point is taken. Nil outside the slide.
    func sampleSlideColor(at point: Offset) -> UInt32? {
        let w = Int(slideSize.width), h = Int(slideSize.height)
        let x = Int(point.dx), y = Int(point.dy)
        guard x >= 0, y >= 0, x < w, y < h else { return nil }
        let painter = SlidePainter(slide: currentSlide, theme: theme, slideSize: slideSize, revision: revision,
                                   cache: SlideTextCache(), placeholders: false)
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, Double(w), Double(h)))
        painter.paint(canvas, Size(Double(w), Double(h)))
        guard let image = recorder.endRecording().toImageSync(width: w, height: h),
              let data = try? image.toByteData(format: .rawRgba) else { return nil }
        let i = (y * w + x) * 4
        guard data.count >= i + 4 else { return nil }
        return UInt32(data[i]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2])
    }

    /// Eyedropper: takes the colour under `point` for the fill or outline of the selection.
    @discardableResult func pickShapeColor(at point: Offset, outline: Bool) -> Bool {
        guard let rgb = sampleSlideColor(at: point) else { return false }
        applyShapeColor(.rgb(rgb), outline: outline)
        return true
    }
}
