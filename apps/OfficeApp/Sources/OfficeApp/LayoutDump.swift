// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter

/// The document's lines and pages as text, laid out the way the window
/// lays it out (100%, the session's theme and font substitution). The
/// same text from `OfficeApp --layout file.docx` natively and from
/// `starling.debug('layout')` in the browser; `diff` them to find where
/// the two platforms break a line differently.
enum OfficeLayoutDump {
    static func text(_ document: RichDocument, pageSetup: PageSetup) -> String {
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        let layout = RichLayout(theme: theme, paragraphCount: document.paragraphs.count)
        layout.scale = 1.0
        layout.pageSetup = pageSetup
        layout.width = pageSetup.columnWidth * theme.pixelsPerPoint
        return layout.lineDump(document)
    }
}
