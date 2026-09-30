// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// PDF export: the same RichLayout that paints pages on screen paints each
/// page into a recorded Picture, and the engine's Skia PDF backend writes
/// them with the fonts embedded. Layout happens at 100% in logical pixels
/// (96/in); the canvas is scaled to PDF points (72/in) first.
enum PdfExport {
    static func write(_ document: RichDocument, pageSetup: PageSetup, theme: RichTextTheme,
                      to path: String, title: String) -> Bool {
        let layout = RichLayout(theme: theme, paragraphCount: document.paragraphs.count)
        layout.scale = 1.0
        layout.pageSetup = pageSetup
        layout.width = pageSetup.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(document)

        var pages: [PdfDocument.Page] = []
        for p in 0 ..< layout.pageCount {
            let rect = layout.pageRect(p)
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder,
                                      cullRect: Rect.fromLTWH(0, 0, pageSetup.width, pageSetup.height))
            canvas.scale(1 / theme.pixelsPerPoint, 1 / theme.pixelsPerPoint)
            canvas.translate(0, -rect.top)
            layout.paint(canvas, visible: rect, document: document, selection: nil, caret: nil,
                         pageBackground: nil)
            pages.append(PdfDocument.Page(picture: recorder.endRecording(),
                                          width: pageSetup.width, height: pageSetup.height))
        }
        return PdfDocument.write(to: path, pages: pages, title: title, author: PdfExport.authorName())
    }
}

extension PdfExport {
    /// The document's author: the user's full name where there is a user.
    static func authorName() -> String {
        #if os(WASI)
        return ""
        #else
        return NSFullUserName()
        #endif
    }
}
