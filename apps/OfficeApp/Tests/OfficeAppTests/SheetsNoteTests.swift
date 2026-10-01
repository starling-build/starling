// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsNoteTests: XCTestCase {
    /// The fixture with notes on 'Single double'!E4 and F6 (F6 threaded).
    static func withNotes() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        var entries = try Zip.read(try Data(contentsOf: url))
        let comments = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<comments xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><authors><author>Ada</author><author>tc={1}</author></authors><commentList>"
            + "<comment ref=\"E4\" authorId=\"0\"><text><r><rPr><b/></rPr><t>Ada:</t></r><r><t xml:space=\"preserve\">\nmeasured twice</t></r></text></comment>"
            + "<comment ref=\"F6\" authorId=\"1\"><text><t>[Threaded comment]\nComment:\n    check this</t></text></comment></commentList></comments>"
        func shape(_ row: Int, _ col: Int) -> String {
            "<v:shape id=\"_x0000_s\(1025 + col)\" type=\"#_x0000_t202\"><x:ClientData ObjectType=\"Note\"><x:MoveWithCells/><x:Anchor>\(col + 1), 15, \(row), 2, \(col + 3), 15, \(row + 4), 16</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>\(row)</x:Row><x:Column>\(col)</x:Column></x:ClientData></v:shape>"
        }
        let vml = "<xml xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:x=\"urn:schemas-microsoft-com:office:excel\">" + shape(3, 4) + shape(5, 5) + "</xml>"
        let threaded = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<ThreadedComments xmlns=\"http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments\"><threadedComment ref=\"F6\" dT=\"2026-01-01T00:00:00.00\" personId=\"{0}\" id=\"{1}\"><text>check this</text></threadedComment></ThreadedComments>"
        entries.append(ZipEntry(name: "xl/comments1.xml", data: Data(comments.utf8)))
        entries.append(ZipEntry(name: "xl/drawings/vmlDrawing1.vml", data: Data(vml.utf8)))
        entries.append(ZipEntry(name: "xl/threadedComments/threadedComment1.xml", data: Data(threaded.utf8)))
        for i in entries.indices where entries[i].name == "xl/worksheets/_rels/sheet1.xml.rels" {
            var s = String(decoding: entries[i].data, as: UTF8.self)
            let end = try XCTUnwrap(s.findRange(of: "</Relationships>"))
            s.replaceSubrange(end, with: "<Relationship Id=\"rIdC\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments\" Target=\"../comments1.xml\"/><Relationship Id=\"rIdV\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing\" Target=\"../drawings/vmlDrawing1.vml\"/><Relationship Id=\"rIdT\" Type=\"http://schemas.microsoft.com/office/2017/10/relationships/threadedComment\" Target=\"../threadedComments/threadedComment1.xml\"/></Relationships>")
            entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
        }
        return try Zip.write(entries)
    }

    func testNotesAreReadAndFollowTheirCells() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try Self.withNotes()))
        XCTAssertEqual(c.sheet.notes.map(\.origin), [CellAddress("E4")!, CellAddress("F6")!])
        XCTAssertEqual(c.sheet.notes[0].author, "Ada")
        XCTAssertEqual(c.sheet.notes[0].text, "Ada:\nmeasured twice")
        c.insert(.rows, at: 0, count: 2)       // both move down two
        c.delete(.rows, at: 7)                 // F8, the threaded one, goes
        XCTAssertEqual(c.sheet.notes.map(\.at), [CellAddress("E6")!, nil])
        let out = try Zip.read(try Xlsx.write(c.book))
        func part(_ n: String) throws -> String { String(decoding: try XCTUnwrap(out.first { $0.name == n }).data, as: UTF8.self) }
        let comments = try part("xl/comments1.xml")
        XCTAssertTrue(comments.containsSubstring("<comment ref=\"E6\" authorId=\"0\">"))
        XCTAssertFalse(comments.containsSubstring("F6") || comments.containsSubstring("F8"))
        XCTAssertNotNil(XNode.parse(Data(comments.utf8)))
        let vml = try part("xl/drawings/vmlDrawing1.vml")
        XCTAssertTrue(vml.containsSubstring("<x:Row>5</x:Row><x:Column>4</x:Column>"))
        XCTAssertEqual(vml.components(separatedBy: "<v:shape ").count - 1, 1)
        XCTAssertFalse(try part("xl/threadedComments/threadedComment1.xml").containsSubstring("<threadedComment "))
    }

    func testUntouchedNotesAreNotRewritten() throws {
        let data = try Self.withNotes()
        let out = try Zip.read(try Xlsx.write(try Xlsx.read(data)))
        let o = try Zip.read(data)
        for n in ["xl/comments1.xml", "xl/drawings/vmlDrawing1.vml", "xl/threadedComments/threadedComment1.xml"] {
            XCTAssertEqual(out.first { $0.name == n }?.data, o.first { $0.name == n }?.data, n)
        }
    }
}
