import XCTest
import Flutter
import OfficeText
@testable import OfficeApp

final class NotesPlaceholderTests: XCTestCase {
    func testPlaceholderOnlyNotesPageSurvivesSave() throws {
        // Build a deck with a note, then empty the note in the XML so the page keeps only placeholders.
        let d0 = DeckController()
        d0.slides[0].notes.load(RichDocument(paragraphs: [RichParagraph(text: "x", runs: [Run(length: 1)], style: RichParagraphStyle())]))
        var pk = PptxPackage(try Zip.read(try Pptx.write(d0)))
        let np = "ppt/notesSlides/notesSlide1.xml"
        var xml = String(data: pk.parts[np]!, encoding: .utf8)!
        XCTAssertTrue(xml.contains("<a:t>x</a:t>"))
        xml = xml.replacingOccurrences(of: "<a:t>x</a:t>", with: "<a:t></a:t>")
        pk.parts[np] = Data(xml.utf8)
        let src = try Zip.write(pk.parts.keys.sorted().map { ZipEntry(name: $0, data: pk.parts[$0]!) })
        let (state, theme, package) = try Pptx.read(src)
        let d = DeckController()
        d.load(state, theme: theme, package: package)
        let out = PptxPackage(try Zip.read(try Pptx.write(d)))
        XCTAssertNotNil(out.parts[np], "placeholder-only notes page is kept")
        // An emptied note that did have text is dropped.
        d0.slides[0].notes.load(RichDocument())
        let (s2, t2, k2) = try Pptx.read(try Pptx.write(d0))
        let d2 = DeckController(); d2.load(s2, theme: t2, package: k2)
        XCTAssertNil(PptxPackage(try Zip.read(try Pptx.write(d2))).parts[np])
    }
}
