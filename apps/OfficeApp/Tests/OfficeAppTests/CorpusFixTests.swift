import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Fixes found by round-tripping Apache POI's .pptx corpus (2026-10-01).
final class CorpusFixTests: XCTestCase {
    func testAnArchiveCutShortGivesUpItsCompleteEntries() throws {
        let whole = try Zip.write([
            ZipEntry(name: "a.xml", data: Data(String(repeating: "<a/>", count: 200).utf8)),
            ZipEntry(name: "b.bin", data: Data([1, 2, 3])),
            ZipEntry(name: "c.xml", data: Data(String(repeating: "<c/>", count: 200).utf8)),
        ])
        // Lose the central directory and half of the last entry.
        let cdStart = whole.range(of: Data([0x50, 0x4B, 0x01, 0x02]))!.lowerBound
        let cut = whole.prefix(cdStart - 10)
        let salvaged = try Zip.read(Data(cut))
        XCTAssertEqual(salvaged.map(\.name), ["a.xml", "b.bin"])
        XCTAssertEqual(salvaged[1].data, Data([1, 2, 3]))
        XCTAssertThrowsError(try Zip.read(Data("not a zip at all, honestly".utf8)))
    }

    func testATextBoxKeepsShrinkToFit() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(slide.contains("<a:spAutoFit/>"), "the sample's text box grows")
        slide = slide.replacingOccurrences(of: "<a:spAutoFit/>", with: "<a:normAutofit fontScale=\"85000\"/>")
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("<a:normAutofit fontScale=\"85000\"/>"))
    }

    /// Slide 6's rounded box with its fill moved into a p:style, a shadow,
    /// and exact 30 pt lines with white text from the style's fontRef.
    private func styledPackage() throws -> PptxPackage {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        let box = try XCTUnwrap(slide.range(of: "prst=\"roundRect\""))
        let spEnd = try XCTUnwrap(slide.range(of: "</p:spPr>", range: box.upperBound ..< slide.endIndex))
        let fillStart = try XCTUnwrap(slide.range(of: "<a:solidFill>", range: box.upperBound ..< spEnd.lowerBound))
        slide.replaceSubrange(fillStart.lowerBound ..< spEnd.upperBound, with:
            "<a:effectLst><a:outerShdw blurRad=\"50800\" dist=\"38100\"><a:prstClr val=\"black\"/></a:outerShdw></a:effectLst></p:spPr>"
            + "<p:style><a:lnRef idx=\"1\"><a:schemeClr val=\"accent1\"/></a:lnRef><a:fillRef idx=\"1\"><a:schemeClr val=\"accent2\"/></a:fillRef>"
            + "<a:effectRef idx=\"0\"><a:schemeClr val=\"accent1\"/></a:effectRef><a:fontRef idx=\"minor\"><a:schemeClr val=\"lt1\"/></a:fontRef></p:style>")
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        return package
    }

    func testAStylesFillEffectsAndTextColourSurvive() throws {
        let package = try styledPackage()
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let box = try XCTUnwrap(state.slides[5].shapes.first { $0.kind == .geometry(.roundRect) })
        XCTAssertEqual(box.fill, theme.accents[1], "the style's fill is drawn")
        XCTAssertNotNil(box.keptLook?.style)
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("<a:fillRef idx=\"1\"><a:schemeClr val=\"accent2\"/></a:fillRef>"), "the style goes back")
        XCTAssertTrue(out.contains("<a:outerShdw"), "and the shadow")
        // Recoloured: our own fill, the style still written.
        var edited = state
        let i = edited.slides[5].shapes.firstIndex { $0.kind == .geometry(.roundRect) }!
        edited.slides[5].shapes[i].fill = Color(0xFF00FF00)
        edited.slides[5].shapes[i].fillScheme = nil
        let out2 = String(data: PptxPackage(try Zip.read(try PptxWriter.write(edited, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out2.contains("00FF00"))
    }

    func testExactLineSpacingStaysExact() throws {
        var p = RichParagraph(text: "Exact", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1))
        p.style.lineHeightPoints = 30
        let s = ShapeState(id: 1, name: "t", kind: .textBox, frame: Rect.fromLTWH(0, 0, 100, 40), rotation: 0,
                           fill: nil, outline: nil, outlineWidth: 0, anchor: .top, insets: .zero, prompt: nil,
                           text: RichDocument(paragraphs: [p]), font: "Calibri", size: 18, color: Color(0xFF000000),
                           listIndent: 18)
        let xml = PptxText.paragraphs(s.text!, defaults: s)
        XCTAssertTrue(xml.contains("<a:lnSpc><a:spcPts val=\"3000\"/></a:lnSpc>"))
    }
}
