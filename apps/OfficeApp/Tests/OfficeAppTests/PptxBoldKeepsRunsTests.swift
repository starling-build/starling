import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Bolding one word must patch that run's own a:rPr and keep the rest of the shape as the file wrote it (smtClean, theme
/// colours, symbol faces), also where the model's text is not the file's character for character: a blank line between two
/// breaks (the reader adds a zero-width mark), a symbol face's private codes (read as the glyphs they show), and a date field.
/// The edit-loss sweep found KEY02, lo-tdf106638, lo-tdf147121 and lo-numfmt rewritten whole by that edit.
final class PptxBoldKeepsRunsTests: XCTestCase {
    private func deck(_ shapes: [String]) throws -> (DeckState, DeckTheme, PptxPackage) {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = "ppt/slides/slide2.xml"
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        var sps = ""
        for (i, body) in shapes.enumerated() {
            sps += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(91 + i)\" name=\"T\(i)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
                + "<p:spPr><a:xfrm><a:off x=\"1270000\" y=\"\(1270000 + i * 1300000)\"/><a:ext cx=\"5080000\" cy=\"1270000\"/></a:xfrm>"
                + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>"
                + "<p:txBody><a:bodyPr/><a:lstStyle/>\(body)</p:txBody></p:sp>"
        }
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: sps + "</p:spTree>")
        package.parts[part] = Data(slide.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        return try Pptx.read(try Zip.write(entries))
    }

    private func boldFirstWordAndSave(_ body: String, word: String) throws -> String {
        var (state, theme, pkg) = try deck([body])
        let si = 1
        let hi = try XCTUnwrap(state.slides[si].shapes.firstIndex { $0.name == "T0" })
        var doc = try XCTUnwrap(state.slides[si].shapes[hi].text)
        let pi = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.containsSubstring(word) })
        let t = doc.paragraphs[pi].text
        let r = try XCTUnwrap(t.range(of: word))
        let lo = t.utf16.distance(from: t.startIndex, to: r.lowerBound)
        doc.paragraphs[pi].applyStyle(lo ..< lo + word.utf16.count) { $0.bold = true }
        state.slides[si].shapes[hi].text = doc
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let xml = String(data: try XCTUnwrap(out.parts["ppt/slides/slide2.xml"]), encoding: .utf8)!
        let start = try XCTUnwrap(xml.range(of: "name=\"T0\""))
        let end = try XCTUnwrap(xml.range(of: "</p:sp>", range: start.upperBound ..< xml.endIndex))
        return String(xml[start.lowerBound ..< end.lowerBound])
    }

    func testBlankLineBetweenBreaksKeepsTheRuns() throws {
        let sp = try boldFirstWordAndSave(
            "<a:p><a:r><a:rPr lang=\"en-US\" smtClean=\"0\"/><a:t>Welcome here</a:t></a:r><a:br><a:rPr lang=\"en-US\"/></a:br>"
            + "<a:br><a:rPr lang=\"en-US\"/></a:br><a:r><a:rPr lang=\"en-US\" smtClean=\"0\"><a:solidFill><a:schemeClr val=\"accent2\"/></a:solidFill></a:rPr>"
            + "<a:t>Third</a:t></a:r><a:br><a:rPr lang=\"en-US\"/></a:br><a:endParaRPr lang=\"en-US\" smtClean=\"0\"/></a:p>", word: "Welcome")
        XCTAssertTrue(sp.containsSubstring("<a:schemeClr val=\"accent2\"/>"), sp)
        XCTAssertTrue(sp.containsSubstring("<a:endParaRPr lang=\"en-US\" smtClean=\"0\"/>"), sp)
        XCTAssertTrue(sp.containsSubstring("b=\"1\""), sp)
        XCTAssertTrue(sp.containsSubstring("<a:t>Welcome</a:t>"), sp)
    }

    func testSymbolRunKeepsItsFace() throws {
        let sp = try boldFirstWordAndSave(
            "<a:p><a:r><a:rPr lang=\"fr-FR\" smtClean=\"0\"><a:solidFill><a:schemeClr val=\"tx2\"/></a:solidFill><a:sym typeface=\"Wingdings\"/></a:rPr>"
            + "<a:t>\u{F0E0} </a:t></a:r><a:r><a:rPr lang=\"fr-FR\" smtClean=\"0\"/><a:t>strat\u{E9}gique</a:t></a:r></a:p>", word: "strat\u{E9}gique")
        XCTAssertTrue(sp.containsSubstring("<a:sym typeface=\"Wingdings\"/>"), sp)
        XCTAssertTrue(sp.containsSubstring("<a:t>\u{F0E0} </a:t>"), sp)
        XCTAssertTrue(sp.containsSubstring("<a:schemeClr val=\"tx2\"/>"), sp)
        XCTAssertTrue(sp.containsSubstring("b=\"1\""), sp)
    }

    func testBoldDateFieldKeepsItsField() throws {
        let sp = try boldFirstWordAndSave(
            "<a:p><a:fld id=\"{B0F4A3C1-1111-2222-3333-444455556666}\" type=\"datetime1\"><a:rPr lang=\"en-US\" smtClean=\"0\">"
            + "<a:solidFill><a:schemeClr val=\"accent1\"/></a:solidFill></a:rPr><a:t>June 21</a:t></a:fld></a:p>", word: "June")
        XCTAssertTrue(sp.containsSubstring("type=\"datetime1\""), sp)
        XCTAssertTrue(sp.containsSubstring("<a:schemeClr val=\"accent1\"/>"), sp)
        XCTAssertTrue(sp.containsSubstring("smtClean=\"0\""), sp)
        XCTAssertTrue(sp.containsSubstring("b=\"1\""), sp)
    }
}
