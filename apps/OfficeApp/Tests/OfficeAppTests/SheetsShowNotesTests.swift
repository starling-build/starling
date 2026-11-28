// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Review > Notes > Show/Hide Note and Show All Notes (X-NT-1), kept in the file as Excel keeps them: a shown note's VML
// shape carries <x:Visible/> and visibility:visible; Show All Notes is the workbook view's showComments.

import XCTest
@testable import OfficeApp

final class SheetsShowNotesTests: XCTestCase {
    private func part(_ entries: [ZipEntry], _ name: String) throws -> String {
        String(decoding: try XCTUnwrap(entries.first { $0.name == name }, name).data, as: UTF8.self)
    }

    func testShowHideNoteOnAFilesNoteSavesAndReopens() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try SheetsNoteTests.withNotes()))
        let e4 = CellAddress("E4")!
        XCTAssertEqual(c.note(at: e4)?.shown, false)
        c.toggleNoteShown(at: e4)
        XCTAssertEqual(c.note(at: e4)?.shown, true)
        XCTAssertGreaterThan(c.edits, 0, "a view change still marks the file changed")
        let out = try Zip.read(try Xlsx.write(c.book))
        let vml = try part(out, "xl/drawings/vmlDrawing1.vml")
        XCTAssertEqual(vml.components(separatedBy: "<x:Visible/>").count - 1, 1, "only E4's shape is shown")
        let back = WorkbookController()
        back.load(try Xlsx.read(try Zip.write(out)))
        XCTAssertEqual(back.note(at: e4)?.shown, true)
        XCTAssertEqual(back.note(at: CellAddress("F6")!)?.shown, false)
        // Hidden again: the mark goes.
        back.toggleNoteShown(at: e4)
        let again = try part(try Zip.read(try Xlsx.write(back.book)), "xl/drawings/vmlDrawing1.vml")
        XCTAssertFalse(again.containsSubstring("<x:Visible"))
        XCTAssertEqual(try Xlsx.read(try Xlsx.write(back.book)).sheets.flatMap(\.notes).filter(\.shown).count, 0)
    }

    func testANewShownNoteOnANewWorkbook() throws {
        let c = WorkbookController()
        let b2 = CellAddress("B2")!
        c.setNote("Check the source", at: b2)
        c.select(b2)
        c.toggleNoteShown()
        XCTAssertEqual(c.note(at: b2)?.shown, true, "the active cell's note")
        let out = try Zip.read(try Xlsx.write(c.book))
        let vml = try XCTUnwrap(out.first { $0.name.hasSuffix(".vml") }).data
        let text = String(decoding: vml, as: UTF8.self)
        XCTAssertTrue(text.containsSubstring("<x:Visible/>"))
        XCTAssertTrue(text.containsSubstring("visibility:visible"))
        XCTAssertEqual(try Xlsx.read(try Zip.write(out)).sheets[0].notes.first?.shown, true)
    }

    func testShowHideNoteWithNoNoteSaysSo() {
        let c = WorkbookController()
        var said: String?
        c.onCommand = { if case .status(let s) = $0 { said = s } }
        c.toggleNoteShown()
        XCTAssertEqual(said, "This cell has no note")
    }

    /// Show All Notes sets every note's own flag, as Excel does, so Show/Hide Note then hides just one, and Show All is
    /// lit only while every note is shown (#3344 on the Mac: B2 stayed shown).
    func testShowAllNotesSetsEachNoteAndShowHideThenHidesOne() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try SheetsNoteTests.withNotes()))
        let e4 = CellAddress("E4")!, f6 = CellAddress("F6")!
        XCTAssertFalse(c.showAllNotes)
        c.toggleShowAllNotes()
        XCTAssertTrue(c.showAllNotes)
        XCTAssertEqual(c.note(at: e4)?.shown, true)
        XCTAssertEqual(c.note(at: f6)?.shown, true)
        c.toggleNoteShown(at: e4)
        XCTAssertEqual(c.note(at: e4)?.shown, false, "Show/Hide hides that note")
        XCTAssertEqual(c.note(at: f6)?.shown, true, "and leaves the other shown")
        XCTAssertFalse(c.showAllNotes, "Show All is no longer lit")
        let back = WorkbookController()
        back.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(back.note(at: e4)?.shown, false)
        XCTAssertEqual(back.note(at: f6)?.shown, true)
        // Show All again shows both; once more hides both.
        back.toggleShowAllNotes()
        XCTAssertTrue(back.showAllNotes)
        back.toggleShowAllNotes()
        XCTAssertEqual(back.sheet.notes.filter(\.shown).count, 0)
    }

    /// A file whose workbook view shows comments and indicators opens with Show All lit; the first change here moves that
    /// onto the notes' own flags and drops the attribute.
    func testAFilesShowCommentsBecomesTheNotesFlags() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try SheetsNoteTests.withNotes()))
        c.book.showComments = "commIndAndComment"
        let opened = WorkbookController()
        opened.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertTrue(opened.showAllNotes)
        opened.toggleNoteShown(at: CellAddress("E4")!)
        XCTAssertNil(opened.book.showComments)
        XCTAssertEqual(opened.note(at: CellAddress("E4")!)?.shown, false)
        XCTAssertEqual(opened.note(at: CellAddress("F6")!)?.shown, true)
        XCTAssertFalse(try part(try Zip.read(try Xlsx.write(opened.book)), "xl/workbook.xml").containsSubstring("showComments"))
    }
}
