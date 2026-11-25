// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText

/// What a screen reader sees of the Writer page: one text field holding the body paragraphs (one per
/// line) with the caret and selection in it, so the platform bridges (AT-SPI, VoiceOver) can read the
/// text, follow the caret and say what is selected. Table cells and text boxes are not in it yet.
enum WriterAccessibility {
    /// The body as a screen reader reads it, and the selection in UTF-16 units of that text.
    static func reading(of controller: RichDocumentController) -> (text: String, selection: TextSelection) {
        let doc = controller.document
        let paragraphs = doc.paragraphs
        var starts: [Int] = []
        var text = ""
        var at = 0
        for (i, p) in paragraphs.enumerated() {
            starts.append(at)
            text += p.text
            at += p.text.utf16.count
            guard i < paragraphs.count - 1 else { break }
            // Cells of one table row read as a tab-separated line, as Word's own text does.
            let next = paragraphs[i + 1].cell
            let sep = (p.cell != nil && next != nil && p.cell!.table == next!.table && p.cell!.row == next!.row
                       && p.cell!.column != next!.column) ? "\t" : "\n"
            text += sep; at += 1
        }
        // Text boxes hold their own paragraphs: they follow the body, one per line, after the caret's range.
        let end = at
        for box in paragraphs.flatMap({ p in ([p.image].compactMap { $0 } + p.inlineImages.inOrder).compactMap { $0.textBox } }) {
            for p in box.paragraphs where !p.text.isEmpty { text += "\n" + p.text }
        }
        func flat(_ pos: RichPosition) -> Int {
            guard !starts.isEmpty else { return 0 }
            let i = min(max(pos.paragraph, 0), starts.count - 1)
            return min(starts[i] + max(pos.offset, 0), end)
        }
        let s = controller.selection
        return (text, TextSelection(baseOffset: flat(s.anchor), extentOffset: flat(s.focus)))
    }

    /// `page` wrapped so its text and caret are announced; rebuilt whenever the document or caret changes.
    static func wrap(_ page: Widget, controller: RichDocumentController, focused: Bool) -> Widget {
        AnimatedBuilder(animation: controller, builder: { _, child in
            let r = reading(of: controller)
            return Semantics(label: "Document", value: r.text, textField: true, focused: focused,
                             textSelection: r.selection, child: child)
        }, child: page)
    }
}
