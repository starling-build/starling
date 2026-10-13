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
        // Laid out fifteen times finer than the screen's pixel — twenty
        // steps to the point, Word's own twip: the engine rounds every
        // line's height to a whole pixel, which at 96 to the inch is
        // three quarters of a point a line and a line or two a page.
        let zoom = Double(ProcessInfo.processInfo.environment["OFFICE_PDF_SCALE"] ?? "") ?? 15.0
        layout.scale = zoom
        layout.pageSetup = pageSetup
        layout.width = pageSetup.columnWidth * theme.pixelsPerPoint * zoom
        layout.ensureLaidOut(document)
        // The pictures are decoded off to the side and painted as grey
        // boxes until they are: wait for them (the decoding runs on the
        // main queue, which nothing is turning here), but not for ever.
        // (A header's or a text box's own layout is made when it is first
        // painted, and its pictures asked for then: the pages are painted
        // once to nowhere first.)
        #if !os(WASI)
        for p in 0 ..< layout.pageCount {
            let recorder = NativePictureRecorder()
            let rect = layout.pageRect(p)
            let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, rect.width, rect.height))
            canvas.translate(0, -rect.top)
            layout.paint(canvas, visible: rect, document: document, selection: nil, caret: nil, pageBackground: nil)
            _ = recorder.endRecording()
        }
        let deadline = Date().addingTimeInterval(8)
        while layout.hasPendingImages, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        #endif

        var pages: [PdfDocument.Page] = []
        for p in 0 ..< layout.pageCount {
            let rect = layout.pageRect(p)
            // (Each page at its own section's size.)
            let pageSetup = layout.pageSetup(forPage: p)
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder,
                                      cullRect: Rect.fromLTWH(0, 0, pageSetup.width, pageSetup.height))
            canvas.scale(1 / (theme.pixelsPerPoint * zoom), 1 / (theme.pixelsPerPoint * zoom))
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
