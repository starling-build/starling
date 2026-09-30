// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class FormatsTests: XCTestCase {
    private func sample() -> RichDocument {
        var paragraphs: [RichParagraph] = []
        paragraphs.append(RichParagraph(text: "Title — with an em dash", style: RichParagraphStyle(heading: 1)))
        var body = RichParagraph(text: "Plain, then bold, then italic, then both.")
        body.applyStyle(12 ..< 16) { $0.bold = true }
        body.applyStyle(23 ..< 29) { $0.italic = true }
        body.applyStyle(36 ..< 40) { $0.bold = true; $0.italic = true; $0.underline = true }
        paragraphs.append(body)
        paragraphs.append(RichParagraph(text: "First bullet", style: RichParagraphStyle(list: .bullet)))
        paragraphs.append(RichParagraph(text: "Nested bullet", style: RichParagraphStyle(list: .bullet, listLevel: 1)))
        paragraphs.append(RichParagraph(text: "Numbered", style: RichParagraphStyle(list: .numbered)))
        paragraphs.append(RichParagraph(text: "Centred 中文 😀", style: RichParagraphStyle(alignment: .center)))
        var mono = RichParagraph(text: "code here", charStyle: CharStyle(fontFamily: OfficeFonts.mono))
        mono.style.indentLeft = 36
        paragraphs.append(mono)
        return RichDocument(paragraphs: paragraphs)
    }

    func testRtfRoundTrip() throws {
        let doc = sample()
        let rtf = RtfFormat.render(doc)
        XCTAssertTrue(rtf.hasPrefix("{\\rtf1"))
        let back = try XCTUnwrap(RtfFormat.parse(rtf))
        XCTAssertEqual(back.paragraphs.map(\.text), doc.paragraphs.map(\.text))
        XCTAssertEqual(back.paragraphs[0].style.heading, 1)
        XCTAssertEqual(back.paragraphs[1].runs.map(\.length), doc.paragraphs[1].runs.map(\.length))
        XCTAssertTrue(back.paragraphs[1].runs[1].style.bold)
        XCTAssertTrue(back.paragraphs[1].runs[3].style.italic)
        XCTAssertTrue(back.paragraphs[1].runs[5].style.underline)
        XCTAssertEqual(back.paragraphs[2].style.list, .bullet)
        XCTAssertEqual(back.paragraphs[3].style.listLevel, 1)
        XCTAssertEqual(back.paragraphs[4].style.list, .numbered)
        XCTAssertEqual(back.paragraphs[5].style.alignment, .center)
        XCTAssertEqual(back.paragraphs[6].runs[0].style.fontFamily, OfficeFonts.mono)
        XCTAssertEqual(back.paragraphs[6].style.indentLeft, 36)
        XCTAssertTrue(back.isValid)
    }

    func testRtfFromTextEdit() throws {
        // What macOS TextEdit writes for "Hello **bold** world" with a bullet.
        let rtf = """
        {\\rtf1\\ansi\\ansicpg1252\\cocoartf2822
        {\\fonttbl\\f0\\fswiss\\fcharset0 Helvetica;\\f1\\fswiss\\fcharset0 Helvetica-Bold;}
        {\\colortbl;\\red255\\green255\\blue255;\\red255\\green0\\blue0;}
        \\pard\\tx560\\pardirnatural\\partightenfactor0
        \\f0\\fs24 \\cf0 Hello \\f1\\b bold\\f0\\b0  world\\
        \\pard\\tx220\\tx720\\li720\\fi-720\\pardirnatural\\partightenfactor0
        \\ls1\\ilvl0\\cf2 {\\listtext\\uc0\\u8226 \\tab}red item\\
        }
        """
        let doc = try XCTUnwrap(RtfFormat.parse(rtf))
        XCTAssertEqual(doc.paragraphs.count, 2)
        XCTAssertEqual(doc.paragraphs[0].text, "Hello bold world")
        XCTAssertEqual(doc.paragraphs[0].runs.map(\.length), [6, 4, 6])
        XCTAssertTrue(doc.paragraphs[0].runs[1].style.bold)
        XCTAssertEqual(doc.paragraphs[1].text, "red item")
        XCTAssertEqual(doc.paragraphs[1].style.list, .bullet)
        XCTAssertEqual(doc.paragraphs[1].runs[0].style.color, Color(0xFFFF0000))
    }

    func testMarkdownRoundTrip() {
        let doc = sample()
        let md = MarkdownFormat.render(doc)
        XCTAssertTrue(md.hasPrefix("# Title"))
        let back = MarkdownFormat.parse(md)
        XCTAssertEqual(back.paragraphs.map(\.text), doc.paragraphs.map(\.text))
        XCTAssertEqual(back.paragraphs[0].style.heading, 1)
        XCTAssertTrue(back.paragraphs[1].runs[1].style.bold)
        XCTAssertTrue(back.paragraphs[1].runs[3].style.italic)
        XCTAssertEqual(back.paragraphs[2].style.list, .bullet)
        XCTAssertEqual(back.paragraphs[3].style.listLevel, 1)
        XCTAssertEqual(back.paragraphs[4].style.list, .numbered)
        XCTAssertEqual(back.paragraphs[6].runs[0].style.fontFamily, OfficeFonts.mono)
    }

    func testMarkdownInline() {
        let doc = MarkdownFormat.parse("A [link](https://example.com) and `code` and ~~gone~~ and *it* plus a lone * star.")
        let p = doc.paragraphs[0]
        XCTAssertEqual(p.text, "A link and code and gone and it plus a lone * star.")
        XCTAssertEqual(p.runs(in: 2 ..< 6)[0].style.link, "https://example.com")
        XCTAssertTrue(p.runs(in: 20 ..< 24)[0].style.strikethrough)
        XCTAssertTrue(p.runs(in: 29 ..< 31)[0].style.italic)
    }
}
