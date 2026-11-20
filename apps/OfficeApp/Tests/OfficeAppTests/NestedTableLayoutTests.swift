// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
@testable import OfficeApp
#if canImport(PDFKit)
import PDFKit
#endif

final class NestedTableLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func document(parentWidth: Double, fixed: Bool, percent: Double?) -> RichDocument {
        var innerStyle = TableStyle(borders: false)
        innerStyle.cellMarginLeft = 0
        innerStyle.cellMarginRight = 0
        innerStyle.cellMarginTop = 0
        innerStyle.cellMarginBottom = 0
        innerStyle.textOutdent = 0
        innerStyle.width = percent == nil ? 200 : nil
        innerStyle.widthPercent = percent
        var edge = RichParagraph(text: "EDGE", style: RichParagraphStyle(alignment: .right, spaceAfter: 0))
        edge.cell = CellRef(table: "inner", row: 0, column: 0)
        var image = ImageAttachment(data: Data(), width: 240, height: 45)
        image.effectLeft = 1.5
        image.sourceWidth = 240
        image.sourceHeight = 45
        var style = CharStyle()
        style.inlineImage = image.id
        var picture = RichParagraph(text: "\n\u{FFFC}", runs: [Run(length: 1, style: CharStyle()), Run(length: 1, style: style)])
        picture.inlineImages = [image.id: image]
        picture.cell = CellRef(table: "inner", row: 1, column: 0)
        var box = RichTextBox(paragraphs: [edge, picture])
        box.growsToFit = true
        box.insetLeft = 0; box.insetRight = 0; box.insetTop = 0; box.insetBottom = 0
        box.tableStyles = ["inner": innerStyle]
        box.tableColumns = ["inner": [200]]
        var block = ImageAttachment(data: Data(), width: 200, height: 1, name: "table")
        block.textBox = box
        var paragraph = RichParagraph(image: block)
        paragraph.cell = CellRef(table: "outer", row: 0, column: 0)
        var doc = RichDocument(paragraphs: [paragraph])
        var outerStyle = innerStyle
        outerStyle.widthPercent = nil
        outerStyle.width = parentWidth
        outerStyle.fixedLayout = fixed
        doc.tableStyles = ["outer": outerStyle]
        doc.tableColumns = ["outer": [parentWidth]]
        return doc
    }

    #if canImport(PDFKit)
    private func rightEdge(_ doc: RichDocument) throws -> Double {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("nested-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: path) }
        XCTAssertTrue(PdfExport.write(doc, pageSetup: .letter, theme: theme, to: path.path, title: "Nested table"))
        let pdf = try XCTUnwrap(PDFDocument(url: path))
        let selection = try XCTUnwrap(pdf.findString("EDGE", withOptions: []).first)
        return selection.bounds(for: try XCTUnwrap(pdf.page(at: 0))).maxX - PageSetup.letter.marginLeft
    }

    func testFixedParentKeepsPreferredWidthDespiteOversizePicture() throws {
        // Word nested-minima pages 1 and 8: a 240pt image with 1.5pt
        // effect spacing overflows a 200pt child, even in a 300pt parent.
        for width in [200.0, 300.0] {
            XCTAssertEqual(try rightEdge(document(parentWidth: width, fixed: true, percent: nil)), 200, accuracy: 0.3)
        }
    }

    func testNestedPercentageUsesFixedParentCellWidth() throws {
        // Word pages 2/9, and image-inline-minima page 6: percentages
        // use the parent's available width, including shares below 100%.
        for (width, percent) in [(200.0, 100.0), (300.0, 100.0), (200.0, 42.74)] {
            XCTAssertEqual(try rightEdge(document(parentWidth: width, fixed: true, percent: percent)), width * percent / 100, accuracy: 0.3)
        }
    }

    func testAutofittingParentStillAllowsNestedPictureToWidenTable() throws {
        // Word nested-minima pages 4/5: do not apply the fixed-parent
        // rule to an autofitting parent.
        XCTAssertEqual(try rightEdge(document(parentWidth: 200, fixed: false, percent: 100)), 241.5, accuracy: 0.3)
    }
    #endif
}
