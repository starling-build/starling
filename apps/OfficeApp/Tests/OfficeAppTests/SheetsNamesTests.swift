// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// X-CE-3: define, edit and delete defined names, each one undo step, and what a save keeps.
final class SheetsNamesTests: XCTestCase {
    private func controller() -> WorkbookController {
        let book = Workbook(sheets: [Worksheet(name: "Data"), Worksheet(name: "Other")])
        book.fileNames = [
            DefinedName(name: "_xlnm.Print_Area", localSheet: 0, attrs: [:], text: "Data!$A$1:$D$20"),
            DefinedName(name: "Rates", localSheet: nil, attrs: ["comment": "kept"], text: "Data!$B$2:$B$9"),
            DefinedName(name: "Local", localSheet: 1, attrs: [:], text: "Other!$A$1"),
        ]
        book.names["RATES"] = "Data!$B$2:$B$9"
        book.nameSpellings["RATES"] = "Rates"
        let c = WorkbookController()
        c.load(book)
        c.setInputs([(CellAddress("B2")!, "5"), (CellAddress("B3")!, "7"), (CellAddress("D1")!, "=SUM(Rates)")], sheet: 0)
        return c
    }

    private func workbookXML(_ c: WorkbookController) throws -> String {
        String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == "xl/workbook.xml" }).data, as: UTF8.self)
    }

    func testTheNameRules() {
        XCTAssertNil(WorkbookController.checkName("Total_2024"))
        XCTAssertNil(WorkbookController.checkName("_x.y"))
        XCTAssertEqual(WorkbookController.checkName(""), .empty)
        XCTAssertEqual(WorkbookController.checkName("1abc"), .badStart)
        XCTAssertEqual(WorkbookController.checkName("a b"), .badCharacter)
        XCTAssertEqual(WorkbookController.checkName("A1"), .looksLikeReference)
        XCTAssertEqual(WorkbookController.checkName("xfd1048576"), .looksLikeReference)
        XCTAssertEqual(WorkbookController.checkName("R2C3"), .looksLikeReference)
        XCTAssertEqual(WorkbookController.checkName("c"), .looksLikeReference)
        XCTAssertNil(WorkbookController.checkName("Rate"))
        XCTAssertNil(WorkbookController.checkName("Cost"))
    }

    func testDefineEditDeleteAndUndo() throws {
        let c = controller()
        XCTAssertNil(c.defineName("Tax", refersTo: "=Data!$B$3"))
        XCTAssertEqual(c.defineName("tax", refersTo: "1"), .exists, "names ignore case")
        XCTAssertEqual(c.defineName("Bad", refersTo: "SUM("), .badFormula)
        XCTAssertEqual(c.definedNameEntries().map(\.name), ["Rates", "Local", "Tax"])
        XCTAssertEqual(c.definedNameEntries().last?.refersTo, "Data!$B$3")
        c.undo()
        XCTAssertEqual(c.definedNameEntries().map(\.name), ["Rates", "Local"], "one undo takes the whole definition back")
        c.redo()
        XCTAssertEqual(c.definedNameEntries().count, 3)

        // Rename: formulas follow the new spelling.
        XCTAssertNil(c.editName("Rates", to: "Prices", refersTo: "Data!$B$2:$B$3"))
        XCTAssertEqual(c.sheet.cells[CellAddress("D1")!]?.input, "=SUM(Prices)")
        XCTAssertEqual(c.sheet.cells[CellAddress("D1")!]?.value.number, 12)
        c.undo()
        XCTAssertEqual(c.sheet.cells[CellAddress("D1")!]?.input, "=SUM(Rates)")
        XCTAssertEqual(c.editName("Local", to: "Place", refersTo: "1"), .notFound, "no workbook-wide name of that spelling")
        // A sheet-local name is edited through its sheet, and undoes in one step.
        XCTAssertNil(c.editName("Local", to: "Place", refersTo: "Other!$B$2", scope: 1))
        XCTAssertEqual(c.definedNameEntries().first { $0.scopeSheet == 1 }?.name, "Place")
        XCTAssertEqual(c.definedNameEntries().first { $0.scopeSheet == 1 }?.refersTo, "Other!$B$2")
        XCTAssertEqual(c.editName("Place", to: "Bad name", refersTo: "1", scope: 1), .badCharacter)
        c.undo()
        XCTAssertEqual(c.definedNameEntries().first { $0.scopeSheet == 1 }?.name, "Local")
        XCTAssertNil(c.deleteName("Local", scope: 1))
        XCTAssertNil(c.definedNameEntries().first { $0.scopeSheet == 1 })
        XCTAssertEqual(c.deleteName("Local", scope: 1), .notFound)
        c.undo()
        XCTAssertNil(c.deleteName("Tax"))
        XCTAssertEqual(c.deleteName("Tax"), .notFound)
    }

    func testRenameKeepsTheNameAttributes() throws {
        let c = controller()
        XCTAssertNil(c.editName("Rates", to: "Prices", refersTo: "Data!$B$2:$B$4"))
        let xml = try workbookXML(c)
        XCTAssertTrue(xml.containsSubstring("<definedName name=\"Prices\" comment=\"kept\">Data!$B$2:$B$4</definedName>"), xml)
        XCTAssertFalse(xml.containsSubstring("\"Rates\""), xml)
    }

    func testRoundTripKeepsTheNamesAndTheirNeighbours() throws {
        let c = controller()
        XCTAssertNil(c.defineName("Tax", refersTo: "Data!$B$3"))
        XCTAssertNil(c.editName("Rates", to: "Rates", refersTo: "Data!$B$2:$B$4"))
        XCTAssertNil(c.editName("Tax", to: "Levy", refersTo: "Data!$B$3"))
        XCTAssertTrue(try workbookXML(c).containsSubstring("<definedName name=\"Levy\">"), "a rename keeps the entry")
        XCTAssertNil(c.editName("Levy", to: "Tax", refersTo: "Data!$B$3"))
        let xml = try workbookXML(c)
        XCTAssertTrue(xml.containsSubstring("<definedName name=\"Tax\">Data!$B$3</definedName>"), xml)
        XCTAssertTrue(xml.containsSubstring("<definedName name=\"Rates\" comment=\"kept\">Data!$B$2:$B$4</definedName>"), xml)
        XCTAssertTrue(xml.containsSubstring("Print_Area\" localSheetId=\"0\">Data!$A$1:$D$20"), "built-in names stay")
        XCTAssertTrue(xml.containsSubstring("<definedName name=\"Local\" localSheetId=\"1\">Other!$A$1</definedName>"), "sheet-local names stay")
        let again = try Xlsx.read(try Xlsx.write(c.book))
        let c2 = WorkbookController()
        c2.load(again)
        XCTAssertEqual(c2.definedNameEntries().map(\.name).sorted(), ["Local", "Rates", "Tax"])
        XCTAssertEqual(c2.definedNameEntries().first { $0.name == "Rates" }?.refersTo, "Data!$B$2:$B$4")
        XCTAssertNil(c2.deleteName("Tax"))
        let gone = try workbookXML(c2)
        XCTAssertFalse(gone.containsSubstring("name=\"Tax\""))
        XCTAssertTrue(gone.containsSubstring("name=\"Rates\" comment=\"kept\""))
    }

    func testNameBoxJumpsToANameAndNamesTheSelection() throws {
        let c = controller()
        let t = try XCTUnwrap(c.nameTarget("rates"))
        XCTAssertEqual(t.sheet, 0)
        XCTAssertEqual(t.range.a1, "B2:B9")
        XCTAssertNil(c.nameTarget("Nothing"))
        c.select(range: CellRange(CellAddress("C3")!, CellAddress("D4")!), active: CellAddress("C3")!)
        XCTAssertNil(c.defineNameForSelection("Block"))
        XCTAssertEqual(c.nameTarget("Block")?.range.a1, "C3:D4")
        XCTAssertEqual(c.defineNameForSelection("Block"), .exists)
        c.undo()
        XCTAssertNil(c.nameTarget("Block"))
        c.select(CellAddress("E5")!)
        XCTAssertNil(c.defineNameForSelection("One"))
        XCTAssertTrue(try workbookXML(c).containsSubstring("<definedName name=\"One\">Data!$E$5</definedName>"))
    }
}
