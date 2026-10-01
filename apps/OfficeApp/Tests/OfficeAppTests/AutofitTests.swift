import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class AutofitTests: XCTestCase {
    func testTheFilesScaleIsKeptNotBakedIn() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        // The body (second shape) shrunk to 77.5% by PowerPoint.
        let parts = slide.components(separatedBy: "<a:normAutofit/>")
        XCTAssertGreaterThanOrEqual(parts.count, 3, "our placeholders autofit")
        slide = parts[0] + "<a:normAutofit/>" + parts[1] + "<a:normAutofit fontScale=\"77500\"/>" + parts.dropFirst(2).joined(separator: "<a:normAutofit/>")
        package.parts["ppt/slides/slide2.xml"] = Data(slide.utf8)
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let body = try XCTUnwrap(state.slides[1].shapes.first { $0.phIdx == "1" })
        XCTAssertTrue(body.autofit)
        XCTAssertEqual(body.fontScale, 0.775)
        XCTAssertEqual(body.text?.paragraphs.first?.runs.first?.style.fontSize, 28, "sizes as typed, not shrunk")
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide2.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("<a:normAutofit fontScale=\"77500\"/>"))
    }

    func testLongTextShrinksShortTextDoesNot() {
        _ = OfficeFonts.register()
        let deck = SlidesSample.make()
        let body = deck.slides[1].shapes.first { $0.role == .body }!
        XCTAssertEqual(SlideTextCache.autofitScale(body), 1, "three bullets fit")
        let c = body.text!
        c.moveToDocumentEnd(extend: false)
        for i in 0 ..< 14 {
            c.insertParagraphBreak()
            c.insertText("Another point worth making, number \(i + 1)")
        }
        let scale = SlideTextCache.autofitScale(body)
        XCTAssertLessThan(scale, 1)
        XCTAssertTrue(SlideTextCache.autofitSteps.contains(scale))
    }
}
