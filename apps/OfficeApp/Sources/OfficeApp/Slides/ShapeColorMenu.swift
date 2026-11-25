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

    init(theme: [UInt32], recent: [UInt32], noneLabel: String,
         onChoose: @escaping (ColorChoice) -> Void, onMore: @escaping () -> Void) {
        self.theme = theme; self.recent = recent; self.noneLabel = noneLabel
        self.onChoose = onChoose; self.onMore = onMore
        super.init(key: ValueKey("shape-color-grid"))
    }

    override func buildItem(_ context: any BuildContext) -> Widget {
        let close: () -> Void = {
            if let scope = FlyoutScope.maybeOf(context) { scope.close() } else { Navigator.maybeOf(context)?.maybePop() }
        }
        return ColorPicker(theme: theme, recent: recent, noneLabel: noneLabel,
                           onChoose: { [onChoose] c in close(); onChoose(c) },
                           onMore: { [onMore] in close(); onMore() })
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
        if outline { setOutline(color); return }
        if case .theme(let slot, 100, 0) = choice, slot >= 4 { setFill(color, scheme: "accent\(slot - 3)") } else { setFill(color) }
    }
}
