import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SelectionHighlightTests: XCTestCase {

    /// A Title paragraph (28pt, line spacing 1.0) wrapped over several lines,
    /// following another Title paragraph: the paragraph builder returns the
    /// first line's selection box a third of a pixel ABOVE the paragraph's
    /// top, so the page mapping must not hand it to the previous paragraph
    /// and clip it to a sliver there (seen on screen 2026-09-30: "This page
    /// is …" selected, only a hairline drawn above it).
    func testFirstLineOfAWrappedTitleParagraphHighlightsFully() {
        _ = OfficeFonts.register()
        let title = RichParagraphStyle(spaceAfter: 4, lineSpacing: 1.0)
        let big = CharStyle(fontSize: 28)
        var doc = RichDocument(plainText: "")
        doc.paragraphs = [
            RichParagraph(text: "A document editor built on the Starling SDK", charStyle: big, style: title),
            RichParagraph(text: "This page is a document like any other: click anywhere and type. "
                          + "The Home tab has the usual formatting, Insert adds tables, pictures, "
                          + "links and page breaks.", charStyle: big, style: title),
        ]
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: doc.paragraphs.count)
        layout.pageSetup = PageSetup(width: 612, height: 792)
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(doc)

        let sel = RichSelection(anchor: RichPosition(paragraph: 1, offset: 0),
                                focus: RichPosition(paragraph: 1, offset: doc.paragraphs[1].length))
        let flow = layout.selectionRects(sel, doc)
        let rects = layout.canvasSelectionRects(sel, doc)
        XCTAssertGreaterThan(rects.count, 2, "the paragraph should wrap")
        let lineHeight = 28 * 96.0 / 72.0
        for r in rects {
            XCTAssertGreaterThan(r.height, lineHeight * 0.8, "collapsed highlight \(r) (flow: \(flow))")
        }
        // And every flow rect stays inside its paragraph's body.
        let g = layout.geometry(1)
        for r in flow {
            XCTAssertGreaterThanOrEqual(r.top, g.textTop - 0.001, "\(r) starts above its paragraph")
            XCTAssertLessThanOrEqual(r.bottom, g.textTop + g.painter.height + 0.001, "\(r) ends below its paragraph")
        }
    }
}
