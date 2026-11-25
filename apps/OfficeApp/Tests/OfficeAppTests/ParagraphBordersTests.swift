// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-PA-4: paragraph borders and shading through the controller, saved and read back.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

final class ParagraphBordersTests: XCTestCase {
    private func controller() -> RichDocumentController {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "one"), RichParagraph(text: "two"), RichParagraph(text: "three")]))
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0), focus: RichPosition(paragraph: 1, offset: 1))
        return c
    }

    func testBordersAndShadingApplyToEveryTouchedParagraphInOneUndo() {
        let c = controller()
        c.setParagraphBorders([.top, .bottom], CellBorderLine(style: "double", width: 1.5, color: Color(0xFFFF0000)))
        c.setParagraphShading(Color(0xFF00FF00))
        for i in 0 ... 1 {
            let st = c.document.paragraphs[i].style
            XCTAssertEqual(st.borders?.top?.width, 1.5)
            XCTAssertEqual(st.borders?.bottom?.style, "double")
            XCTAssertNil(st.borders?.left)
            XCTAssertEqual(st.fill, Color(0xFF00FF00))
        }
        XCTAssertNil(c.document.paragraphs[2].style.borders)
        c.undo()
        c.undo()
        XCTAssertNil(c.document.paragraphs[0].style.borders)
        XCTAssertNil(c.document.paragraphs[0].style.fill)
    }

    func testRemovingTheLastSideLeavesNoBorders() {
        let c = controller()
        c.setParagraphBorders([.left], CellBorderLine())
        c.setParagraphBorders([.left], nil)
        XCTAssertNil(c.document.paragraphs[0].style.borders)
    }

    func testBordersAndShadingSurviveASave() throws {
        let c = controller()
        c.setParagraphBorders([.top, .bottom, .left, .right], CellBorderLine(style: "dashed", width: 1, color: Color(0xFF0000FF)))
        c.setParagraphShading(Color(0xFFFFFF00))
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let st = back.paragraphs[0].style
        XCTAssertEqual(st.borders?.top?.style, "dashed")
        XCTAssertEqual(st.borders?.right?.width, 1)
        XCTAssertEqual(st.borders?.left?.color, Color(0xFF0000FF))
        XCTAssertEqual(st.fill, Color(0xFFFFFF00))
        XCTAssertNil(back.paragraphs[2].style.borders)
    }

    func testInsideBorderIsKeptAndSaved() throws {
        let c = controller()
        c.setParagraphBorders([.top, .bottom, .left, .right], CellBorderLine())
        c.setParagraphBorders([.insideH], CellBorderLine(style: "single", width: 2.25, color: Color(0xFF00AA00)))
        XCTAssertEqual(c.document.paragraphs[1].style.borders?.between?.width, 2.25)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].style.borders?.between?.color, Color(0xFF00AA00))
        c.setParagraphBorders([.insideH], nil)
        XCTAssertNil(c.document.paragraphs[0].style.borders?.between)
    }
}
