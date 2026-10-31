// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// PDF export: the same RichLayout that paints pages on screen paints each
/// page into a recorded Picture, and the engine's Skia PDF backend writes
/// them with the fonts embedded. Layout happens at 100% in logical pixels
/// (96/in); the canvas is scaled to PDF points (72/in) first.
enum PdfExport {
    static func write(_ document: RichDocument, pageSetup: PageSetup, theme: RichTextTheme,
                      to path: String, title: String, layoutOnly: Bool = false) -> Bool {
        // A document with comments or tracked changes prints with its
        // markup, as Word prints it by default: the page smaller, its
        // balloons beside it (`MarkupFrame`, `PdfMarkup`), its deleted
        // text gone into them.
        let markup = hasMarkup(document) ? PdfMarkup(document) : nil
        let document = markup?.document ?? document
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
        while layout.hasPendingImages || WriterMetafiles.hasPendingImages || WriterGroups.hasPendingImages, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        #endif

        // (`--trace-rules`: laid out, and every header and text box with it,
        // as a PDF is written from them; no page of it is.)
        if layoutOnly { return true }

        var pages: [PdfDocument.Page] = []
        for p in 0 ..< layout.pageCount {
            let rect = layout.pageRect(p)
            // (Each page at its own section's size.)
            let pageSetup = layout.pageSetup(forPage: p)
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder,
                                      cullRect: Rect.fromLTWH(0, 0, pageSetup.width, pageSetup.height))
            if let markup {
                let frame = MarkupFrame(pageSetup)
                let pane = Paint()
                pane.color = Color(0xFFF2F2F2)
                canvas.drawRect(frame.pane, pane)
                canvas.save()
                canvas.translate(frame.left, frame.top)
                canvas.scale(frame.scale, frame.scale)
                markup.paint(page: p, layout: layout, setup: pageSetup, theme: theme, zoom: zoom, canvas: canvas)
            }
            canvas.scale(1 / (theme.pixelsPerPoint * zoom), 1 / (theme.pixelsPerPoint * zoom))
            canvas.translate(0, -rect.top)
            layout.paint(canvas, visible: rect, document: document, selection: nil, caret: nil,
                         pageBackground: nil)
            if markup != nil { canvas.restore() }
            pages.append(PdfDocument.Page(picture: recorder.endRecording(),
                                          width: pageSetup.width, height: pageSetup.height))
        }
        return PdfDocument.write(to: path, pages: pages, title: title, author: PdfExport.authorName())
    }
}

extension PdfExport {
    /// Whether Word prints the document with its markup: it carries a
    /// comment or a tracked change (inserted, deleted or reformatted text).
    /// (A comment Word prints no balloon for is no markup: comment.docx's,
    /// alone in the document, prints a plain page — `PdfMarkup.silentComments`.)
    static func hasMarkup(_ document: RichDocument) -> Bool {
        let silent = PdfMarkup.silentComments(document)
        return document.paragraphs.contains { p in
            // (A deleted paragraph mark is a tracked change too, with its
            // "Deleted: ¶" balloon: tdf120336's one empty paragraph.)
            p.style.markRevision?.kind == .deleted ||
            (p.style.markRevision != nil && p.style.sectionXML != nil) ||
            p.runs.contains { $0.style.comments.contains { !silent.contains($0) } || $0.style.revision.map(Self.hasBalloon) == true || $0.style.formatChange != nil }
        }
    }

    /// Whether a tracked change has a balloon in Word's print: a deletion
    /// and a move do; an insertion is only underlined where it stands, and
    /// a document whose changes are all insertions prints as any other
    /// page, at full size, with no markup area (lo CT-with-frame: its two
    /// insertions print at 72pt, the margin, in Word's PDF; ours scaled the
    /// page for balloons that were not there). An inserted section
    /// break has one ("Inserted: Section Break"): lo-512aa398's prints with
    /// the frame, where zh-25381d22's and zh-86547e97's inserted paragraph
    /// marks, and a run inserted in a table cell (lo-e998b55c), do not.
    static func hasBalloon(_ revision: RevisionMark) -> Bool {
        if revision.kind == .inserted, !revision.moved { RuleTrace.hit("insertion-has-no-balloon"); return false }
        return true
    }

    /// Where a page printed with its markup stands on the paper, as Word
    /// prints it (POI's six markup prints, Word 16, letter and A4): the
    /// page and a markup area 3.7in wide from its text's right edge are
    /// scaled together to the paper's width, with 36.5pt to spare
    /// (k 0.693-0.737); the page 8.6pt from the paper's left and 5.2pt
    /// under the middle top to bottom; a grey pane over the markup area
    /// from 9.1pt past the text, 257.3pt wide (unscaled). Word for Windows
    /// (lab bp on the Windows box, and word-win's five pane prints, within
    /// 0.3pt) leaves nothing to spare: the page and the 3.7in area fill the
    /// paper's width, the page at the paper's left edge and centred top to
    /// bottom, the pane from 9pt past the text to the paper's edge, 257.4pt.
    struct MarkupFrame {
        let scale: Double
        let left: Double
        let top: Double
        let pane: Rect
        init(_ setup: PageSetup) {
            let textRight = setup.width - setup.marginRight
            if DocxFormat.wordOnWindows {
                scale = setup.width / (textRight + 266.4)
                left = 0
                top = (setup.height - scale * setup.height) / 2
                pane = Rect.fromLTWH(scale * (textRight + 9), top, scale * 257.4, scale * setup.height)
                return
            }
            scale = setup.width / (textRight + 266.4 + 36.5)
            left = 8.6
            top = (setup.height - scale * setup.height) / 2 + 5.2
            pane = Rect.fromLTWH(left + scale * (textRight + 9.1), top, scale * 257.3, scale * setup.height)
        }
    }

    /// The document's author: the user's full name where there is a user.
    static func authorName() -> String {
        #if os(WASI)
        return ""
        #else
        return NSFullUserName()
        #endif
    }
}
