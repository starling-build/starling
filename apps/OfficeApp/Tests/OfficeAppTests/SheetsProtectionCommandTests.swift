import XCTest
@testable import OfficeApp

/// X-DA-6: protecting a sheet and the workbook, passwords, and locked cells.
final class SheetsProtectionCommandTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "keep"), (CellAddress("A2")!, "free"), (CellAddress("B1")!, "3")])
        c.select(CellAddress("A2")!)
        c.setCellProtection(locked: false, formulaHidden: nil)
        c.select(CellAddress("A1")!)
        return c
    }
    private func reread(_ c: WorkbookController) throws -> WorkbookController {
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        return again
    }

    func testPasswordHashesMatchExcelsMethods() {
        XCTAssertEqual(ProtectionPassword.legacy("password"), "83AF")
        XCTAssertEqual(ProtectionPassword.legacy(""), "CE4B")
        XCTAssertEqual(ProtectionPassword.sha512("pässword", salt: Array(0 ..< 16), spin: 5),
                       "lkFePZh2Tt8LrbAbfKDs7h0b3eOaDV1aifP2g0fFGrD+MbG7/msAvoZowNn2cwWQbVdsizA4FsJAMLJNCrYnrg==")
        let sha = ["algorithmName": "SHA-512", "saltValue": "AAECAwQFBgcICQoLDA0ODw==", "spinCount": "5",
                   "hashValue": "lkFePZh2Tt8LrbAbfKDs7h0b3eOaDV1aifP2g0fFGrD+MbG7/msAvoZowNn2cwWQbVdsizA4FsJAMLJNCrYnrg=="]
        XCTAssertEqual(ProtectionPassword.accepts(sha, prefix: "", "pässword"), true)
        XCTAssertEqual(ProtectionPassword.accepts(sha, prefix: "", "password"), false)
        XCTAssertNil(ProtectionPassword.accepts(["algorithmName": "MD5", "saltValue": "AA==", "hashValue": "x"], prefix: "", "a"))
    }

    func testProtectedSheetRefusesLockedCellsButNotUnlockedOnes() throws {
        let c = book()
        XCTAssertNil(c.sheetProtectionOptions())
        c.protectSheet(SheetProtectionOptions(sort: true), password: "")
        XCTAssertEqual(c.sheetProtectionOptions(), SheetProtectionOptions(sort: true))
        XCTAssertTrue(c.refusesEdit([CellAddress("A1")!]))
        XCTAssertFalse(c.refusesEdit([CellAddress("A2")!]), "an unlocked cell still takes edits")
        XCTAssertFalse(c.refuses("sort")); XCTAssertTrue(c.refuses("formatCells"))
        let again = try reread(c)
        XCTAssertEqual(again.sheetProtectionOptions(), SheetProtectionOptions(sort: true))
        XCTAssertFalse(again.isLocked(CellAddress("A2")!)); XCTAssertTrue(again.isLocked(CellAddress("A1")!))
        c.undo()
        XCTAssertNil(c.sheetProtectionOptions())
    }

    func testAPasswordIsNeededToUnprotectAndItSurvivesASave() throws {
        let c = book()
        c.protectSheet(SheetProtectionOptions(), password: "password")
        XCTAssertTrue(c.sheetHasPassword)
        let again = try reread(c)
        XCTAssertEqual(again.unprotectSheet(password: "nope"), .wrongPassword)
        XCTAssertNotNil(again.protection())
        XCTAssertNil(again.unprotectSheet(password: "password"))
        XCTAssertNil(again.protection())
        XCTAssertEqual(again.unprotectSheet(password: ""), .notProtected)
    }

    func testLockingCellsIsOneUndoStepAndSurvivesASave() throws {
        let c = book()
        c.select(CellAddress("B1")!)
        c.setCellProtection(locked: nil, formulaHidden: true)
        XCTAssertTrue(c.book.style(c.sheet.cells[CellAddress("B1")!]!.style).formulaHidden)
        XCTAssertTrue(try reread(c).book.style(try reread(c).sheet.cells[CellAddress("B1")!]!.style).formulaHidden)
        c.undo()
        XCTAssertFalse(c.book.style(c.sheet.cells[CellAddress("B1")!]?.style ?? 0).formulaHidden)
        c.protectSheet(SheetProtectionOptions(), password: "")
        c.setCellProtection(locked: false, formulaHidden: nil)
        XCTAssertTrue(c.isLocked(CellAddress("B1")!), "a protected sheet takes no format change")
    }

    func testWorkbookStructureProtectionRefusesAndRoundTrips() throws {
        let c = book()
        c.protectWorkbook(password: "pw")
        XCTAssertTrue(c.book.structureLocked)
        XCTAssertTrue(c.workbookHasPassword)
        let n = c.book.sheets.count
        c.addSheet()
        XCTAssertEqual(c.book.sheets.count, n)
        let again = try reread(c)
        XCTAssertTrue(again.book.structureLocked)
        XCTAssertEqual(again.unprotectWorkbook(password: "x"), .wrongPassword)
        XCTAssertNil(again.unprotectWorkbook(password: "pw"))
        XCTAssertFalse(again.book.structureLocked)
        XCTAssertNil(again.book.workbookProtection)
        c.undo()
        XCTAssertFalse(c.book.structureLocked)
    }
}
