// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class HtmlTests: XCTestCase {
    func testHtmlFromABrowser() throws {
        // What Safari puts on the pasteboard for a selection: a fragment
        // with inline styles, entities, comments and a script to skip.
        let html = """
        <!DOCTYPE html><html><head><title>x</title><style>p{margin:0}</style></head><body>
        <h1>Title &amp; more</h1>
        <!-- a comment -->
        <p>Plain <b>bold</b> and <span style="font-style: italic; color: #ff0000">red italic</span>
        with a <a href="https://example.com/?a=1&amp;b=2">link</a>.<br>Second line.</p>
        <ul><li>one</li><li>two <strong>2</strong></li></ul>
        <ol><li>first</li></ol>
        <blockquote>A quote</blockquote>
        <pre>let x = 1
          indented</pre>
        <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2 &lt; 3</td></tr></table>
        <script>alert('no')</script>
        <p>After.</p>
        </body></html>
        """
        let ps = try XCTUnwrap(HtmlFormat.parse(html))
        let doc = RichDocument(paragraphs: ps)
        XCTAssertEqual(ps.map(\.text), ["Title & more", "Plain bold and red italic with a link.\nSecond line.",
                                         "one", "two 2", "first", "A quote", "let x = 1", "  indented",
                                         "A", "B", "1", "2 < 3", "After."])
        XCTAssertEqual(ps[0].style.heading, 1)
        XCTAssertTrue(ps[1].runs(in: 6 ..< 10)[0].style.bold)
        let red = ps[1].runs(in: 15 ..< 25)[0].style
        XCTAssertTrue(red.italic)
        XCTAssertEqual(red.color, Color(0xFFFF0000))
        XCTAssertEqual(ps[1].runs(in: 33 ..< 37)[0].style.link, "https://example.com/?a=1&b=2")
        XCTAssertEqual(ps[2].style.list, .bullet)
        XCTAssertEqual(ps[4].style.list, .numbered)
        XCTAssertEqual(doc.styles.id(of: ps[5].style), "Quote")
        XCTAssertEqual(doc.styles.id(of: ps[6].style), "Code")
        XCTAssertEqual(ps[8].cell?.row, 0); XCTAssertEqual(ps[8].cell?.column, 0)
        XCTAssertEqual(ps[11].cell?.row, 1); XCTAssertEqual(ps[11].cell?.column, 1)
        XCTAssertTrue(ps[8].runs[0].style.bold)   // th
        XCTAssertTrue(doc.isValid)
    }

    func testHtmlRoundTrip() throws {
        var doc = RichDocument(plainText: "Heading\nBody with bold and a link.\nitem\nquoted")
        doc.styles = OfficeStyles.sheet
        doc.styles.apply("Heading2", to: &doc.paragraphs[0].style)
        doc.paragraphs[1].applyStyle(10 ..< 14) { $0.bold = true; $0.color = Color(0xFF00AA00) }
        doc.paragraphs[1].applyStyle(21 ..< 25) { $0.link = "https://s.dev" }
        doc.paragraphs[2].style.list = .bullet
        doc.styles.apply("Quote", to: &doc.paragraphs[3].style)
        let html = HtmlFormat.render(doc.paragraphs, styles: doc.styles)
        XCTAssertTrue(html.contains("<h2>Heading</h2>"))
        XCTAssertTrue(html.contains("<ul><li>item</li></ul>"))
        let back = try XCTUnwrap(HtmlFormat.parse(html))
        XCTAssertEqual(back.map(\.text), doc.paragraphs.map(\.text))
        XCTAssertEqual(back[0].style.heading, 2)
        XCTAssertEqual(back[1].runs(in: 10 ..< 14)[0].style.bold, true)
        XCTAssertEqual(back[1].runs(in: 10 ..< 14)[0].style.color, Color(0xFF00AA00))
        XCTAssertEqual(back[1].runs(in: 21 ..< 25)[0].style.link, "https://s.dev")
        XCTAssertEqual(back[2].style.list, .bullet)
        XCTAssertEqual(doc.styles.id(of: back[3].style), "Quote")
    }

    func testClipboardCodecPrefersRtfThenHtml() throws {
        let codec = OfficeClipboardCodec()
        var doc = RichDocument(plainText: "Copied bold")
        doc.paragraphs[0].applyStyle(7 ..< 11) { $0.bold = true }
        let data = codec.encode(doc.paragraphs, styles: OfficeStyles.sheet, text: "Copied bold")
        XCTAssertTrue(data.rtf?.hasPrefix("{\\rtf1") ?? false)
        XCTAssertTrue(data.html?.contains("<b>bold</b>") ?? false)
        let fromRtf = try XCTUnwrap(codec.decode(ClipboardData(text: "x", rtf: data.rtf)))
        XCTAssertEqual(fromRtf[0].text, "Copied bold")
        XCTAssertTrue(fromRtf[0].runs(in: 7 ..< 11)[0].style.bold)
        let fromHtml = try XCTUnwrap(codec.decode(ClipboardData(text: "x", html: data.html)))
        XCTAssertTrue(fromHtml[0].runs(in: 7 ..< 11)[0].style.bold)
        XCTAssertNil(codec.decode(ClipboardData(text: "plain only")))
        // The controller's paste takes the codec's fragment over the text.
        let c = RichDocumentController(plainText: "")
        c.clipboardCodec = codec
        c.paste(data: ClipboardData(text: "Copied bold", html: data.html))
        XCTAssertEqual(c.document.paragraphs[0].text, "Copied bold")
        XCTAssertTrue(c.document.paragraphs[0].runs(in: 7 ..< 11)[0].style.bold)
    }

    func testHtmlColspan() throws {
        let ps = try XCTUnwrap(HtmlFormat.parse("<table><tr><td colspan=\"2\">wide</td><td>c</td></tr><tr><td>1</td><td>2</td><td>3</td></tr></table>"))
        XCTAssertEqual(ps[0].cell?.span, 2)
        XCTAssertEqual(ps[1].cell?.column, 2)
        XCTAssertEqual(ps.map(\.text), ["wide", "c", "1", "2", "3"])
        let html = HtmlFormat.render(ps)
        XCTAssertTrue(html.contains("<td colspan=\"2\">wide</td>"))
        XCTAssertEqual(try XCTUnwrap(HtmlFormat.parse(html))[0].cell?.span, 2)
    }

    func testHtmlEntitiesNeverLoop() throws {
        // A lone surrogate, an empty numeric entity, a bare ampersand, an
        // unknown name: each stays literal, and the parser returns.
        let html = "<p>&#xD83D; and &#; and x = &#foo; and AT&amp;T &copy; 5 &lt; 6 &unknown; &</p>"
        let ps = try XCTUnwrap(HtmlFormat.parse(html))
        XCTAssertEqual(ps[0].text, "&#xD83D; and &#; and x = &#foo; and AT&T \u{00A9} 5 < 6 &unknown; &")
        // A list copied from Google Docs: items wrapped in <p> make no empty bullets.
        let list = try XCTUnwrap(HtmlFormat.parse("<ul><li><p>one</p></li><li><p>two</p></li></ul><table><td>lonely</td></table>"))
        XCTAssertEqual(list.map(\.text), ["one", "two", "lonely"])
        XCTAssertEqual(list[0].style.list, .bullet)
        XCTAssertEqual(list[2].cell?.row, 0)
    }

    func testPastedPngBecomesAPicture() {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==")!
        XCTAssertEqual(ImageAttachment.pngPixelSize(png)?.width, 1)
        let c = RichDocumentController(plainText: "")
        c.paste(data: ClipboardData(text: nil, png: png))
        XCTAssertNotNil(c.document.paragraphs.first { $0.image != nil })
    }
}
