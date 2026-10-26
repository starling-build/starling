// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter

enum WriterLinks {
    /// Word contents entries refer to bookmarks in the open document, not
    /// fragments of the browser's URL. Never hand those to the host, even
    /// when a destination has been deleted.
    @discardableResult
    static func follow(_ link: String, in controller: RichDocumentController,
                       openURL: (String) -> Void) -> Bool {
        guard link.hasPrefix("#") else {
            openURL(link)
            return true
        }
        let name = String(link.dropFirst())
        guard !name.isEmpty else { return false }
        let paragraphs = controller.document.paragraphs
        guard let index = paragraphs.firstIndex(where: { $0.bookmarks.contains(name) }) else {
            return false
        }
        let previous = controller.selection
        controller.moveTo(RichPosition(paragraph: index, offset: 0), reveal: .top)
        // Scrolling can leave the caret at the destination. Following the
        // link again must still reveal it when the selection is unchanged.
        if controller.selection == previous { controller.notifyListeners() }
        return true
    }
}
