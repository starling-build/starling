// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

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
        let items: [Widget] = [
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
            Chrome.colorMenu(FluentSystemIcons.textColor, "Color", fluent, colors: OfficeColors.text, none: "Automatic") { color in
                change { $0.char.color = color }
            },
            Chrome.gap(12),
            Chrome.toggle(FluentSystemIcons.alignLeft, "Align Left", entry.paragraph.alignment == .left, fluent) { change { $0.paragraph.alignment = .left } },
            Chrome.toggle(FluentSystemIcons.alignCenter, "Center", entry.paragraph.alignment == .center, fluent) { change { $0.paragraph.alignment = .center } },
            Chrome.toggle(FluentSystemIcons.alignRight, "Align Right", entry.paragraph.alignment == .right, fluent) { change { $0.paragraph.alignment = .right } },
            Chrome.gap(12),
            Chrome.spinner("Before", entry.paragraph.spaceBefore, fluent, step: 2) { v in change { $0.paragraph.spaceBefore = v } },
            Chrome.gap(4),
            Chrome.spinner("After", entry.paragraph.spaceAfter, fluent, step: 2) { v in change { $0.paragraph.spaceAfter = v } },
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
        return DecoratedBox(
            decoration: BoxDecoration(
                color: fluent.resources.layerFillColorDefault,
                border: Border(bottom: BorderSide(color: fluent.resources.dividerStrokeColorDefault, width: 1))),
            child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 8, bottom: 6),
                           child: Row(crossAxisAlignment: .center, children: items)))
    }
}
