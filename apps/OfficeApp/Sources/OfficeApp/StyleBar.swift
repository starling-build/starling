// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

private final class MSKeyed: StatelessWidget {
    let child: Widget
    init(_ id: String, _ child: Widget) { self.child = child; super.init(key: ValueKey(id)) }
    override func build(_ context: any BuildContext) -> Widget { child }
}

/// Modify Style: the strip the gallery's "Modify…" opens. Every control
/// edits the sheet entry at once and every paragraph in the style
/// follows, so the document is the preview; the whole strip is one undo
/// step (Done, Esc, or a click in the document ends it), as Word's
/// dialog is.
final class StyleBar: StatelessWidget {
    let session: OfficeSession
    let styleId: String
    let onClose: () -> Void

    init(session: OfficeSession, styleId: String, onClose: @escaping () -> Void) {
        self.session = session
        self.styleId = styleId
        self.onClose = onClose
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let c = session.controller
        guard let entry = c.document.styles[styleId] else { return SizedBox(width: 0, height: 0, child: nil) }
        func change(_ transform: (inout RichNamedStyle) -> Void) {
            var e = entry
            transform(&e)
            c.setStyleEntry(e, coalescing: true)
        }
        let size = entry.char.fontSize ?? session.theme.fontSize
        let para = entry.paragraph
        // The line spacing a style states as a multiple (Word's Single, 1.08, 1.15, 1.5, Double…); a fixed or
        // at-least height shows as its own entry so the box never claims a multiple the style lacks.
        let multiples: [Double] = [1, 1.08, 1.15, 1.5, 2, 2.5, 3]
        // Word's 1.08 is stored as 259/240 = 1.0791…: a stated multiple within a hundredth is that entry, and any other
        // number shows to two decimals.
        let stated = para.lineHeightPoints == nil ? para.lineSpacing : -1
        let spacing = multiples.first { abs($0 - stated) < 0.005 } ?? stated
        var spacingItems = multiples.map { m in
            ComboBoxItem<Double>(value: m, child: Text(m == 1 ? "Single" : m == 2 ? "Double" : "\(m)",
                                                      style: fluent.typography.body?.copyWith(color: nil)))
        }
        if !multiples.contains(spacing) {
            let shown = spacing < 0 ? "\(para.lineHeightIsMinimum ? "At least" : "Exactly") \(Chrome.shortNumber(para.lineHeightPoints ?? 0)) pt" : Chrome.shortNumber(spacing)
            spacingItems.append(ComboBoxItem<Double>(value: spacing, child: Text(shown, style: fluent.typography.body?.copyWith(color: nil))))
        }
        // Style for the following paragraph: "" keeps this style (Word writes no w:next then).
        let itemStyle = fluent.typography.body?.copyWith(color: nil)
        let others: [RichNamedStyle] = c.document.styles.styles.filter { (s: RichNamedStyle) -> Bool in s.id != entry.id && s.paragraph.list == nil }
        var nextItems: [ComboBoxItem<String>] = [ComboBoxItem<String>(value: "", child: Text(entry.name, style: itemStyle))]
        for s in others.sorted(by: { $0.name < $1.name }) {
            nextItems.append(ComboBoxItem<String>(value: s.id, child: Text(s.name, style: itemStyle)))
        }
        let underline: Widget = MSKeyed("ms-underline", Chrome.toggle(FluentSystemIcons.textUnderline, "Underline", entry.char.underline, fluent) {
            change { (e: inout RichNamedStyle) in
                e.char.underline.toggle()
                if !e.char.underline { e.char.underlineKind = nil; e.char.underlineColor = nil }
            }
        })
        let first: [Widget] = [
            SizedBox(width: 120, height: nil, child: Text("Modify \(entry.name)", style: fluent.typography.bodyStrong)),
            SizedBox(width: 172, height: nil, child: ComboBox<String>(
                value: entry.char.fontFamily ?? session.theme.fontFamily,
                items: OfficeFonts.families.map { f in
                    ComboBoxItem<String>(value: f, child: Text(f, style: fluent.typography.body?.copyWith(color: nil)))
                },
                onChanged: { f in change { $0.char.fontFamily = f } })),
            Chrome.gap(8),
            Chrome.spinner("Size", size, fluent, step: 1, minimum: 6) { v in change { $0.char.fontSize = v } },
            Chrome.gap(8),
            Chrome.toggle(FluentSystemIcons.textBold, "Bold", entry.char.bold, fluent) { change { $0.char.bold.toggle() } },
            Chrome.toggle(FluentSystemIcons.textItalic, "Italic", entry.char.italic, fluent) { change { $0.char.italic.toggle() } },
            underline,
            Chrome.colorMenu(FluentSystemIcons.textColor, "Color", fluent, colors: OfficeColors.text, none: "Automatic") { color in
                change { $0.char.color = color }
            },
            Expanded(child: SizedBox(width: 0, height: 0, child: nil)),
            Button(onPressed: { [session] in
                // Word's defaults for this style, or the app's sheet if it has no entry.
                if let original = OfficeStyles.sheet[entry.id] { session.controller.setStyleEntry(original, coalescing: true) }
            }, child: Text("Reset")),
            Chrome.gap(8),
            FilledButton(onPressed: onClose, child: Text("Done")),
            Chrome.gap(4),
            Chrome.icon(FluentSystemIcons.chromeClose, "Close (Esc)", fluent, action: onClose),
        ]
        let second: [Widget] = [
            SizedBox(width: 120, height: nil, child: nil),
            Chrome.toggle(FluentSystemIcons.alignLeft, "Align Left", para.alignment == .left, fluent) { change { $0.paragraph.alignment = .left } },
            Chrome.toggle(FluentSystemIcons.alignCenter, "Center", para.alignment == .center, fluent) { change { $0.paragraph.alignment = .center } },
            Chrome.toggle(FluentSystemIcons.alignRight, "Align Right", para.alignment == .right, fluent) { change { $0.paragraph.alignment = .right } },
            MSKeyed("ms-justify", Chrome.toggle(FluentSystemIcons.alignJustify, "Justify", para.alignment == .justify, fluent) {
                change { $0.paragraph.alignment = .justify }
            }),
            Chrome.gap(12),
            Chrome.spinner("Before", para.spaceBefore, fluent, step: 2) { v in change { $0.paragraph.spaceBefore = v } },
            Chrome.gap(4),
            Chrome.spinner("After", para.spaceAfter, fluent, step: 2) { v in change { $0.paragraph.spaceAfter = v } },
            Chrome.gap(4),
            Chrome.spinner("Indent", para.indentLeft, fluent, step: 18) { v in change { $0.paragraph.indentLeft = v } },
            Chrome.gap(4),
            // A negative first line is a hanging indent, as Word's Special: Hanging.
            Chrome.spinner("First line", para.firstLineIndent, fluent, step: 18, minimum: -para.indentLeft) { v in
                change { $0.paragraph.firstLineIndent = v }
            },
            Chrome.gap(8),
            Tooltip(message: "Line spacing", child: SizedBox(width: 120, height: nil, child: ComboBox<Double>(
                value: spacing, items: spacingItems,
                onChanged: { (m: Double?) in guard let m, m > 0 else { return }
                    change { $0.paragraph.lineSpacing = m; $0.paragraph.lineHeightPoints = nil; $0.paragraph.lineHeightIsMinimum = false } }))),
            Chrome.gap(8),
            Text("Next", style: fluent.typography.caption),
            Chrome.gap(4),
            Tooltip(message: "Style for following paragraph", child: SizedBox(width: 150, height: nil, child: ComboBox<String>(
                value: entry.next ?? "", items: nextItems,
                onChanged: { (n: String?) in change { $0.next = (n ?? "").isEmpty ? nil : n } }))),
        ]
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                           child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                               Row(crossAxisAlignment: .center, children: first),
                               SizedBox(width: nil, height: 4, child: nil),
                               Row(crossAxisAlignment: .center, children: second),
                           ])))
    }
}
