// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-FN-1: the text of one footnote or endnote, in a dialog. The note's mark is shown above the box; OK
// is one undo step (`setNoteText`). A note holding anything the plain box would lose (bold, a link, a
// picture) says so and cannot be edited here.

import Flutter
import FlutterSwiftBridge
import OfficeText

final class NoteDialog: StatelessWidget {
    let title: String
    let text: TextEditingController
    /// nil: the note can be edited; else why not.
    let refusal: String?
    let onOK: () -> Void
    let onCancel: () -> Void

    init(title: String, text: TextEditingController, refusal: String?, onOK: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.text = text
        self.refusal = refusal
        self.onOK = onOK
        self.onCancel = onCancel
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let page: Widget = refusal.map { Text($0, style: fluent.typography.body) }
            ?? SizedBox(width: nil, height: 120, child: FluentTextBox(controller: text, maxLines: 6, autofocus: true))
        return DialogShell(title: title, tabs: [DialogTab(title: title, page: page)], okEnabled: refusal == nil,
                           onOK: onOK, onCancel: onCancel)
    }
}
