// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The strip Font Color → More Colors… opens: Word's theme colours in
/// six tints and shades, the ten standard colours, and a hex field. A
/// swatch applies and closes; the hex field applies on Enter or Apply.
final class ColorBar: StatelessWidget {
    let hex: TextEditingController
    let onPick: (Color) -> Void
    let onApplyHex: () -> Void
    let onClose: () -> Void

    init(hex: TextEditingController, onPick: @escaping (Color) -> Void,
         onApplyHex: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.hex = hex
        self.onPick = onPick
        self.onApplyHex = onApplyHex
        self.onClose = onClose
        super.init()
    }

    /// Word's Office theme, left to right: the base row, then 80/60/40 %
    /// lighter and 25/50 % darker. White darkens and black lightens in
    /// steps of their own, as Word shows them.
    static let theme: [[Color]] = {
        let bases: [UInt32] = [0xFFFFFF, 0x000000, 0xE7E6E6, 0x44546A, 0x4472C4,
                               0xED7D31, 0xA5A5A5, 0xFFC000, 0x5B9BD5, 0x70AD47]
        func mix(_ c: UInt32, toward t: Double, by f: Double) -> Color {
            func ch(_ shift: UInt32) -> UInt32 {
                let v = Double((c >> shift) & 0xFF)
                return UInt32((v + (t - v) * f).rounded()) & 0xFF
            }
            return Color(Int(0xFF000000 | ch(16) << 16 | ch(8) << 8 | ch(0)))
        }
        var rows = Array(repeating: [Color](), count: 6)
        for (k, b) in bases.enumerated() {
            let steps: [Color]
            switch k {
            case 0: steps = [0.05, 0.15, 0.25, 0.35, 0.5].map { mix(b, toward: 0, by: $0) }
            case 1: steps = [0.5, 0.35, 0.25, 0.15, 0.05].map { mix(b, toward: 255, by: $0) }
            default: steps = [mix(b, toward: 255, by: 0.8), mix(b, toward: 255, by: 0.6), mix(b, toward: 255, by: 0.4),
                              mix(b, toward: 0, by: 0.25), mix(b, toward: 0, by: 0.5)]
            }
            rows[0].append(Color(Int(0xFF000000 | b)))
            for (i, s) in steps.enumerated() { rows[i + 1].append(s) }
        }
        return rows
    }()

    static let standard: [Color] = [0xC00000, 0xFF0000, 0xFFC000, 0xFFFF00, 0x92D050,
                                    0x00B050, 0x00B0F0, 0x0070C0, 0x002060, 0x7030A0].map { Color(Int(0xFF000000 | $0)) }

    /// "#RRGGBB" or "RRGGBB" (also RGB shorthand), else nil.
    static func parse(_ text: String) -> Color? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return Color(Int(0xFF000000 | v))
    }

    static func hex(_ color: Color) -> String {
        String(format: "#%06X", UInt32(truncatingIfNeeded: color.value) & 0xFFFFFF)
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let caption = fluent.typography.caption?.copyWith(color: fluent.resources.textFillColorSecondary)
        func swatch(_ color: Color) -> Widget {
            Padding(padding: EdgeInsets(left: 0, top: 0, right: 3, bottom: 3), child: Tooltip(
                message: Self.hex(color),
                child: GestureDetector(onTap: { [onPick] in onPick(color) }, child: SizedBox(width: 15, height: 15, child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: color,
                        border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1)))))))
        }
        let themeGrid = Column(crossAxisAlignment: .start, children: Self.theme.map { row in
            Row(mainAxisSize: .min, children: row.map(swatch))
        })
        let standardRow = Row(mainAxisSize: .min, children: Self.standard.map(swatch))
        let items: [Widget] = [
            SizedBox(width: 60, height: nil, child: Text("Font Color", style: fluent.typography.body)),
            Column(crossAxisAlignment: .start, children: [Text("Theme Colors", style: caption), Chrome.vgap(2), themeGrid]),
            Chrome.gap(16),
            Column(crossAxisAlignment: .start, children: [Text("Standard Colors", style: caption), Chrome.vgap(2), standardRow]),
            Chrome.gap(16),
            Column(crossAxisAlignment: .start, children: [
                Text("Hex", style: caption), Chrome.vgap(2),
                Row(mainAxisSize: .min, children: [
                    SizedBox(width: 110, height: 30, child: FluentTextBox(
                        controller: hex, placeholderText: "#RRGGBB", onSubmitted: { [onApplyHex] _ in onApplyHex() })),
                    Chrome.gap(6),
                    FilledButton(onPressed: onApplyHex, child: Text("Apply")),
                ]),
            ]),
            Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
            Chrome.icon(FluentSystemIcons.chromeClose, "Close (Esc)", fluent, action: onClose),
        ]
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 4),
                           child: Row(crossAxisAlignment: .start, children: items)))
    }
}
