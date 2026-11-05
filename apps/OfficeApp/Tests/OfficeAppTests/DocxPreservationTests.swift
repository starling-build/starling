// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

final class DocxPreservationTests: XCTestCase {
    private func fixture(_ body: String, relationship: String = "") throws -> RichDocument {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let i = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
        parts[i] = ZipEntry(name: "word/document.xml", data: Data((
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:body>"
            + body + "</w:body></w:document>").utf8))
        if !relationship.isEmpty {
            let r = try XCTUnwrap(parts.firstIndex { $0.name == "word/_rels/document.xml.rels" })
            var xml = String(decoding: parts[r].data, as: UTF8.self)
            xml = xml.replacingOccurrences(of: "</Relationships>", with: relationship + "</Relationships>")
            parts[r] = ZipEntry(name: parts[r].name, data: Data(xml.utf8))
        }
        return try DocxFormat.read(Zip.write(parts)).document
    }

    private func savedBody(_ doc: RichDocument) throws -> XNode {
        let entries = try Zip.read(DocxFormat.write(doc, pageSetup: .letter))
        return try XCTUnwrap(XNode.parse(try XCTUnwrap(entries.first { $0.name == "word/document.xml" }).data))
    }

    private func bookmarkText(_ root: XNode, name: String) -> String {
        var active = false, id = "", text = ""
        func walk(_ node: XNode) {
            if node.name == "w:bookmarkStart", node["w:name"] == name { id = node["w:id"] ?? ""; active = true }
            if node.name == "w:bookmarkEnd", node["w:id"] == id { active = false }
            if active, node.name == "w:t" { text += node.text }
            for child in node.children { walk(child) }
        }
        walk(root)
        return text
    }

    func testExternalHyperlinkKeepsItsBookmarkDestination() throws {
        let doc = try fixture("<w:p><w:hyperlink r:id=\"rIdTestLink\" w:anchor=\"Chapter_2\"><w:r><w:t>Read chapter</w:t></w:r></w:hyperlink></w:p>",
            relationship: "<Relationship Id=\"rIdTestLink\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"https://example.com/report.docx\" TargetMode=\"External\"/>")
        XCTAssertEqual(doc.paragraphs[0].runs[0].style.link, "https://example.com/report.docx#Chapter_2")
        let back = try DocxFormat.read(DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].runs[0].style.link, "https://example.com/report.docx#Chapter_2")
    }

    func testBookmarkKeepsItsTextRangeOnSave() throws {
        let doc = try fixture("<w:p><w:r><w:t>a</w:t></w:r><w:bookmarkStart w:id=\"7\" w:name=\"Range\"/><w:r><w:t>bc</w:t></w:r><w:bookmarkEnd w:id=\"7\"/><w:r><w:t>d</w:t></w:r></w:p>")
        XCTAssertEqual(bookmarkText(try savedBody(doc), name: "Range"), "bc")
    }

    func testBookmarkCrossesParagraphsAndSurvivesSplitAndJoin() throws {
        let doc = try fixture("<w:p><w:r><w:t>a</w:t></w:r><w:bookmarkStart w:id=\"7\" w:name=\"Range\"/><w:r><w:t>bc</w:t></w:r><w:bookmarkEnd w:id=\"7\"/><w:r><w:t>d</w:t></w:r></w:p>")
        let c = RichDocumentController(document: doc)
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 2))
        c.insertText("\n")
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["ab", "cd"])
        XCTAssertEqual(bookmarkText(try savedBody(c.document), name: "Range"), "bc")
        let reopened = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(bookmarkText(try savedBody(reopened), name: "Range"), "bc")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].bookmarkMarkers, doc.paragraphs[0].bookmarkMarkers)
        XCTAssertEqual(bookmarkText(try savedBody(c.document), name: "Range"), "bc")
        c.redo()
        XCTAssertEqual(bookmarkText(try savedBody(c.document), name: "Range"), "bc")
    }

    func testBookmarkBoundariesFollowUnicodeEditsAndUndoDeletion() throws {
        let doc = try fixture("<w:p><w:r><w:t>a</w:t></w:r><w:bookmarkStart w:id=\"7\" w:name=\"Range\"/><w:r><w:t>bc</w:t></w:r><w:bookmarkEnd w:id=\"7\"/><w:r><w:t>d</w:t></w:r></w:p>")
        let c = RichDocumentController(document: doc)
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 2))
        c.insertText("🙂")
        XCTAssertEqual(bookmarkText(try savedBody(c.document), name: "Range"), "b🙂c")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].bookmarkMarkers, doc.paragraphs[0].bookmarkMarkers)
        c.breakUndoCoalescing()
        c.selection = RichSelection(anchor: .start, focus: RichPosition(paragraph: 0, offset: 3))
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs[0].text, "d")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "abcd")
        XCTAssertEqual(c.document.paragraphs[0].bookmarkMarkers, doc.paragraphs[0].bookmarkMarkers)
        c.redo()
        XCTAssertEqual(c.document.paragraphs[0].text, "d")
    }

    func testEmptyBookmarkAndOverlappingRangesKeepTheirPositions() throws {
        let doc = try fixture("<w:p><w:bookmarkStart w:id=\"1\" w:name=\"Outer\"/><w:r><w:t>a🙂</w:t></w:r><w:bookmarkStart w:id=\"2\" w:name=\"Point\"/><w:bookmarkEnd w:id=\"2\"/><w:bookmarkStart w:id=\"3\" w:name=\"Overlap\"/><w:r><w:t>b</w:t></w:r><w:bookmarkEnd w:id=\"1\"/><w:r><w:t>c</w:t></w:r><w:bookmarkEnd w:id=\"3\"/></w:p>")
        let back = try DocxFormat.read(DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].bookmarkMarkers, doc.paragraphs[0].bookmarkMarkers)
        XCTAssertEqual(back.paragraphs[0].bookmarkMarkers.first { $0.name == "Point" }?.offset, 3)
        XCTAssertEqual(bookmarkText(try savedBody(back), name: "Outer"), "a🙂b")
        XCTAssertEqual(bookmarkText(try savedBody(back), name: "Overlap"), "bc")
    }

    func testUndoJoinRestoresAnEndMarkerToTheOriginalParagraph() throws {
        let doc = try fixture("<w:p><w:bookmarkStart w:id=\"7\" w:name=\"Range\"/><w:r><w:t>ab</w:t></w:r><w:bookmarkEnd w:id=\"7\"/></w:p><w:p><w:r><w:t>cd</w:t></w:r></w:p>")
        let c = RichDocumentController(document: doc)
        c.selection = RichSelection(caret: RichPosition(paragraph: 0, offset: 2))
        c.deleteForward()
        XCTAssertEqual(c.document.paragraphs.count, 1)
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.bookmarkMarkers), doc.paragraphs.map(\.bookmarkMarkers))
        c.redo()
        XCTAssertEqual(bookmarkText(try savedBody(c.document), name: "Range"), "ab")
    }

    func testCopiedAndUnclosedBookmarksDoNotWriteInvalidRanges() throws {
        var doc = try fixture("<w:p><w:bookmarkStart w:id=\"7\" w:name=\"Range\"/><w:r><w:t>ab</w:t></w:r><w:bookmarkEnd w:id=\"7\"/></w:p><w:p><w:bookmarkStart w:id=\"8\" w:name=\"Unclosed\"/><w:r><w:t>cd</w:t></w:r></w:p>")
        doc.paragraphs.append(doc.paragraphs[0])
        let root = try savedBody(doc)
        let starts = root.descendants("w:bookmarkStart"), ends = root.descendants("w:bookmarkEnd")
        XCTAssertEqual(starts.map { $0["w:name"] }, ["Range", "Unclosed"])
        XCTAssertEqual(Set(starts.compactMap { $0["w:id"] }), Set(ends.compactMap { $0["w:id"] }))
        XCTAssertEqual(ends.count, 2)
    }

    func testInternalLinksAndExistingURLFragmentsRemainStable() throws {
        let doc = try fixture("<w:p><w:hyperlink w:anchor=\"Here\"><w:r><w:t>Internal</w:t></w:r></w:hyperlink><w:hyperlink r:id=\"rIdTestLink\"><w:r><w:t>External</w:t></w:r></w:hyperlink></w:p>",
            relationship: "<Relationship Id=\"rIdTestLink\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"https://example.com/?a=1&amp;b=2#section\" TargetMode=\"External\"/>")
        let back = try DocxFormat.read(DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].runs.map(\.style.link), ["#Here", "https://example.com/?a=1&b=2#section"])
    }

    func testBookmarkInsideACommentKeepsTheWholeCommentRange() throws {
        var doc = try fixture("<w:p><w:r><w:t>a</w:t></w:r><w:bookmarkStart w:id=\"7\" w:name=\"Range\"/><w:r><w:t>bc</w:t></w:r><w:bookmarkEnd w:id=\"7\"/><w:r><w:t>d</w:t></w:r></w:p>")
        doc.paragraphs[0].applyStyle(0 ..< 4) { $0.comments = ["1"] }
        doc.keptParts["word/comments.xml"] = Data("<w:comments xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:comment w:id=\"1\" w:author=\"Reviewer\"><w:p><w:r><w:t>Review this</w:t></w:r></w:p></w:comment></w:comments>".utf8)
        let back = try DocxFormat.read(DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].text, "abcd")
        XCTAssertTrue(back.paragraphs[0].runs.allSatisfy { $0.style.comments == ["1"] })
        XCTAssertEqual(bookmarkText(try savedBody(back), name: "Range"), "bc")
    }

    func testSimpleMetadataFieldStaysLiveWithoutBecomingAPageField() throws {
        let doc = try fixture("<w:p><w:fldSimple w:instr=\"DOCPROPERTY Title\" w:fldLock=\"1\" w:dirty=\"0\"><w:r><w:t>Report title</w:t></w:r></w:fldSimple></w:p>")
        XCTAssertNil(doc.paragraphs[0].runs[0].style.field)
        XCTAssertEqual(doc.paragraphs[0].runs[0].style.preservedField, "DOCPROPERTY Title")
        XCTAssertEqual(try savedBody(doc).descendants("w:instrText").map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }, ["DOCPROPERTY Title"])
        let begin = try XCTUnwrap(savedBody(doc).descendants("w:fldChar").first)
        XCTAssertEqual(begin["w:fldLock"], "1")
        XCTAssertEqual(begin["w:dirty"], "0")
    }

    func testOrdinaryFieldInstructionsAndFormattedResultsSurviveSave() throws {
        for instruction in ["AUTHOR", "DATE \\@ \"yyyy-MM-dd\"", "DOCPROPERTY Title"] {
            let escaped = instruction.replacingOccurrences(of: "\"", with: "&quot;")
            let doc = try fixture("<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText>\(escaped)</w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>First</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>Second</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>")
            let root = try savedBody(doc)
            XCTAssertEqual(root.descendants("w:instrText").map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }, [instruction])
            let back = try DocxFormat.read(DocxFormat.write(doc, pageSetup: .letter)).document.paragraphs[0]
            XCTAssertEqual(back.text, "FirstSecond")
            XCTAssertTrue(back.runs(in: 5 ..< 11)[0].style.bold)
        }
    }
}
