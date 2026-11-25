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
        let paragraphs = controller.document.paragraphs
        var starts: [Int] = []
        var text = ""
        var at = 0
        for (i, p) in paragraphs.enumerated() {
            starts.append(at)
            text += p.text
            at += p.text.utf16.count
            if i < paragraphs.count - 1 { text += "\n"; at += 1 }
        }
        func flat(_ pos: RichPosition) -> Int {
            guard !starts.isEmpty else { return 0 }
            let i = min(max(pos.paragraph, 0), starts.count - 1)
            return min(starts[i] + max(pos.offset, 0), at)
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
