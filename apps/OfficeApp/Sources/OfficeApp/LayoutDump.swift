// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import Foundation

/// The document's lines and pages as text, laid out the way the window
/// lays it out (100%, the session's theme and font substitution). The
/// same text from `OfficeApp --layout file.docx` natively and from
/// `starling.debug('layout')` in the browser; `diff` them to find where
/// the two platforms break a line differently.
enum OfficeLayoutDump {
    static func text(_ document: RichDocument, pageSetup: PageSetup) -> String {
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.drawn
        theme.faceResolver = OfficeFonts.face
        theme.complexFaceResolver = OfficeFonts.complexFace
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.symbolGlyphs = { face, text in face.map { Metafile.symbols(text, face: $0) } ?? text }
        theme.symbolAdvance = Metafile.symbolAdvance
        theme.wordRules = true
        theme.disablesLigatures = true
        let layout = RichLayout(theme: theme, paragraphCount: document.paragraphs.count)
        // (LAYOUT_SCALE=15 dumps the layout a PDF is written from.)
        let zoom = Double(ProcessInfo.processInfo.environment["LAYOUT_SCALE"] ?? "") ?? 1.0
        layout.scale = zoom
        layout.pageSetup = pageSetup
        layout.width = pageSetup.columnWidth * theme.pixelsPerPoint * zoom
        return layout.lineDump(document)
    }
}
