import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A plain save keeps each notes page as the file wrote it while its text is unchanged: its own shape names and ids, locks,
/// language tags, smtClean and the date and number placeholders. The edit-loss sweep found 14 decks (SampleShow,
/// 2411-Performance_Up, 60810...) whose notes pages were rebuilt from the model on every save. An edited note is still rewritten.
final class PptxNotesKeptTests: XCTestCase {
    private let marked = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>\
        <p:sp><p:nvSpPr><p:cNvPr id="7" name="Espace r\u{E9}serv\u{E9} des notes 6"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>\
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="fr-FR" dirty="0" smtClean="0"/><a:t>Open with the numbers.</a:t></a:r><a:endParaRPr lang="fr-FR" dirty="0"/></a:p></p:txBody></p:sp>\
        <p:sp><p:nvSpPr><p:cNvPr id="8" name="Slide Number Placeholder 7"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldNum" sz="quarter" idx="5"/></p:nvPr></p:nvSpPr><p:spPr/>\
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:fld id="{3C1F4C2A-0000-4000-8000-000000000001}" type="slidenum"><a:rPr lang="fr-FR"/><a:t>1</a:t></a:fld><a:endParaRPr lang="fr-FR"/></a:p></p:txBody></p:sp>\
        </p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>
        """

    private func deckWithMarkedNotes() throws -> (DeckState, DeckTheme, PptxPackage, String) {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let part = try XCTUnwrap(package.rel("ppt/slides/slide1.xml", kind: "notesSlide")?.target)
        package.parts[part] = Data(marked.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        return (state, theme, pkg, part)
    }

    private func savedNotes(_ state: DeckState, _ theme: DeckTheme, _ pkg: PptxPackage) throws -> String {
        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let part = try XCTUnwrap(out.rel("ppt/slides/slide1.xml", kind: "notesSlide")?.target)
        return String(data: try XCTUnwrap(out.parts[part]), encoding: .utf8)!
    }

    func testPlainSaveKeepsTheNotesPage() throws {
        let (state, theme, pkg, _) = try deckWithMarkedNotes()
        let xml = try savedNotes(state, theme, pkg)
        XCTAssertTrue(xml.containsSubstring("name=\"Espace r\u{E9}serv\u{E9} des notes 6\""), xml)
        XCTAssertTrue(xml.containsSubstring("<a:rPr lang=\"fr-FR\" dirty=\"0\" smtClean=\"0\"/>"), xml)
        XCTAssertTrue(xml.containsSubstring("type=\"slidenum\""), xml)
    }

    func testEditedNoteIsRewritten() throws {
        var (state, theme, pkg, _) = try deckWithMarkedNotes()
        state.slides[0].notes = RichDocument(paragraphs: [RichParagraph(text: "Start with the map.")])
        let xml = try savedNotes(state, theme, pkg)
        XCTAssertTrue(xml.containsSubstring("Start with the map."), xml)
        XCTAssertFalse(xml.containsSubstring("Open with the numbers."), xml)
    }
}
