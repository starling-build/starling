import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// Table > Split Table, and Split Cells' "Merge cells before split".
final class SplitTableTests: XCTestCase {
    private func table(rows: Int = 4, columns: Int = 2) -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: rows, columns: columns)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        for (k, i) in idx.enumerated() { c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false); c.insertText("t\(k)") }
        return c
    }
    private func goTo(_ c: RichDocumentController, row: Int, column: Int) {
        let i = c.document.paragraphs.firstIndex { $0.cell?.row == row && $0.cell?.column == column }!
        c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
    }

    func testSplitMakesTwoTablesWithAParagraphBetween() {
        let c = table()
        c.setRowHeight(30)                       // row 0
        goTo(c, row: 2, column: 1)
        XCTAssertTrue(c.splitTable())
        let ps = c.document.paragraphs
        let ids = Set(ps.compactMap { $0.cell?.table })
        XCTAssertEqual(ids.count, 2)
        let firstEnd = ps.lastIndex { $0.cell?.row == 1 && $0.cell?.column == 1 && $0.text == "t3" }!
        XCTAssertNil(ps[firstEnd + 1].cell)
        XCTAssertEqual(ps[firstEnd + 1].text, "")
        let second = ps.filter { $0.cell != nil && $0.cell!.table != ps.first { $0.cell != nil }!.cell!.table }
        XCTAssertEqual(second.map(\.text), ["t4", "t5", "t6", "t7"])
        XCTAssertEqual(second.first?.cell?.row, 0)
        XCTAssertEqual(c.currentCell?.row, 0)
        XCTAssertEqual(c.currentTableStyle?.rowHeights, [1: 30])   // the caret was in row 3 when it was set
        c.undo()
        XCTAssertEqual(Set(c.document.paragraphs.compactMap { $0.cell?.table }).count, 1)
    }

    func testSplitInTheFirstRowOnlyAddsAParagraphAbove() {
        let c = table()
        goTo(c, row: 0, column: 0)
        XCTAssertTrue(c.splitTable())
        XCTAssertEqual(Set(c.document.paragraphs.compactMap { $0.cell?.table }).count, 1)
        XCTAssertNil(c.document.paragraphs[0].cell)
        XCTAssertEqual(c.currentCell?.row, 0)
    }

    func testNoSplitAcrossAVerticallyMergedCell() {
        let c = table()
        goTo(c, row: 1, column: 0)
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell?.row == 2 && $0.cell?.column == 0 }!, offset: 0), extend: true)
        c.mergeCells()
        goTo(c, row: 2, column: 1)
        XCTAssertFalse(c.canSplitTable)
        XCTAssertFalse(c.splitTable())
    }

    func testSplitTableSurvivesASave() throws {
        let c = table()
        goTo(c, row: 2, column: 0)
        c.splitTable()
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(Set(back.paragraphs.compactMap { $0.cell?.table }).count, 2)
        XCTAssertEqual(back.paragraphs.filter { $0.cell != nil }.count, 8)
    }

    func testNineAlignButtonsSetBothDirectionsInOneStep() {
        let c = table(rows: 2, columns: 2)
        goTo(c, row: 0, column: 1)
        c.setCellAlignment(vertical: "bottom", horizontal: .right)
        let cell = c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 1 }!
        XCTAssertEqual(cell.cell?.verticalAlign, "bottom")
        XCTAssertEqual(cell.style.alignment, .right)
        let other = c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 0 }!
        XCTAssertNil(other.cell?.verticalAlign)
        c.setCellAlignment(vertical: "top", horizontal: .center)
        XCTAssertNil(c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 1 }!.cell?.verticalAlign)
        c.undo()
        XCTAssertEqual(c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 1 }!.cell?.verticalAlign, "bottom")
    }

    func testSplitCellsAfterMergingASelection() {
        let c = table(rows: 2, columns: 2)
        goTo(c, row: 0, column: 0)
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell?.row == 0 && $0.cell?.column == 1 }!, offset: 0), extend: true)
        c.mergeCells()
        XCTAssertEqual(c.currentCell?.span, 2)
        XCTAssertTrue(c.splitCell(columns: 3, rows: 1))
        XCTAssertEqual(Set(c.document.paragraphs.filter { $0.cell?.row == 0 }.compactMap { $0.cell?.column }).count, 3)
    }

    func testEraserMergesNeighboursAcrossAnInnerEdgeOnly() {
        let c = table(rows: 2, columns: 2)
        let t = c.document.paragraphs.first { $0.cell != nil }!.cell!.table
        XCTAssertFalse(c.eraseCellEdge(table: t, row: 0, column: 0, side: .left))   // outer border
        XCTAssertTrue(c.eraseCellEdge(table: t, row: 0, column: 0, side: .right))
        XCTAssertEqual(c.currentCell?.span, 2)
        XCTAssertFalse(c.eraseCellEdge(table: t, row: 0, column: 0, side: .bottom))  // cell below is narrower
        c.undo()
        XCTAssertEqual(c.document.paragraphs.first { $0.cell?.row == 0 && $0.cell?.column == 0 }?.cell?.span, 1)
    }

    func testDrawTableSplitsACellAtTheStroke() {
        let c = table(rows: 1, columns: 1)
        let t = c.document.paragraphs.first { $0.cell != nil }!.cell!.table
        XCTAssertFalse(c.drawTable(in: DrawCell(table: t, row: 0, column: 0), dx: 2, dy: 3))
        // A stroke a quarter of the way down a 40 pt cell: rows of 10 and 30.
        XCTAssertTrue(c.drawTable(in: DrawCell(table: t, row: 0, column: 0, fy: 0.25, heightPoints: 40), dx: 80, dy: 4))
        XCTAssertEqual(Set(c.document.paragraphs.compactMap { $0.cell?.row }).count, 2)
        let h = c.document.tableStyles[t]!.rowHeights
        XCTAssertEqual(h[0]!, 10, accuracy: 0.01)
        XCTAssertEqual(h[1]!, 30, accuracy: 0.01)
        // A vertical stroke 25% across the first row: the left column is a third of the right.
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.firstIndex { $0.cell?.row == 0 }!, offset: 0), extend: false)
        XCTAssertTrue(c.drawTable(in: DrawCell(table: t, row: 0, column: 0, fx: 0.25), dx: 3, dy: 60))
        let w = c.document.tableColumns[t]!
        XCTAssertEqual(w[0] / (w[0] + w[1]), 0.25, accuracy: 0.01)
        c.undo()
        XCTAssertEqual(c.document.tableColumns[t]?.count ?? 1, 1)
    }
}

/// Writes the Word lab for Split Table / alignment when SPLIT_LAB_OUT names a file (skipped otherwise).
final class SplitTableLabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["SPLIT_LAB_OUT"] else { throw XCTSkip("no SPLIT_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 4, columns: 2)
        var idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        for (k, i) in idx.enumerated() { c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false); c.insertText("S\(k)") }
        c.moveTo(RichPosition(paragraph: idx[4], offset: 0), extend: false)
        XCTAssertTrue(c.splitTable())
        c.moveTo(RichPosition(paragraph: c.document.paragraphs.count - 1, offset: 0), extend: false)
        c.insertParagraphBreak()
        c.insertTable(rows: 3, columns: 3)
        idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }.suffix(9).map { $0 }
        let v = ["top", "center", "bottom"], h: [ParagraphAlignment] = [.left, .center, .right]
        for (k, i) in idx.enumerated() {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText("\(v[k / 3])-\(k % 3)")
            if k % 3 == 0 { c.setRowHeight(48) }
            c.setCellAlignment(vertical: v[k / 3], horizontal: h[k % 3])
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}

/// Writes the Text Direction lab when TEXTDIR_LAB_OUT names a file (skipped otherwise).
final class TextDirectionLabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["TEXTDIR_LAB_OUT"] else { throw XCTSkip("no TEXTDIR_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 3)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        let dirs: [CellRef.CellTextDirection] = [.horizontal, .down, .up]
        for (k, i) in idx.enumerated() {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText(k < 3 ? "Dir \(k) text" : "Dir \(k - 3) tall")
            if k == 0 { c.setRowHeight(110) }
            c.setCellTextDirection(dirs[k % 3])
            if k >= 3 { c.setCellAlignment(vertical: "bottom", horizontal: .right) }
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}

/// Lab for the column pitch of turned cells (several sizes and faces); TEXTPITCH_LAB_OUT names the file.
final class TextPitchLabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["TEXTPITCH_LAB_OUT"] else { throw XCTSkip("no TEXTPITCH_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 2, columns: 6)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        let faces = ["Calibri", "Calibri", "Calibri", "Calibri", "Arial", "Times New Roman"]
        let sizes: [Double] = [8, 11, 14, 20, 11, 11]
        for (k, i) in idx.enumerated() {
            let col = k % 6
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText("Aaaa Bbbb Cccc Dddd")
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.moveTo(RichPosition(paragraph: i, offset: 19), extend: true)
            c.setFontFamily(faces[col]); c.setFontSize(sizes[col])
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            if k == 0 { c.setRowHeight(60) }
            if k == 6 { c.setRowHeight(120) }
            c.setCellTextDirection(k < 6 ? .down : .up)
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}

/// Lab 2 for the turned-cell line pitch: eight faces by three sizes, every cell
/// "Aaaa Bbbb" in a 100 pt row, Rotate Down, so each prints two lines whose
/// step is the face's turned pitch.
final class TextPitch2LabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["TEXTPITCH2_LAB_OUT"] else { throw XCTSkip("no TEXTPITCH2_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 8)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        let faces = ["Calibri", "Cambria", "Consolas", "Verdana", "Tahoma", "Georgia", "Segoe UI", "Courier New"]
        let sizes: [Double] = [9, 11, 13]
        for (k, i) in idx.enumerated() {
            let col = k % 8, row = k / 8
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText("Aaaa Bbbb Cccc")
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.moveTo(RichPosition(paragraph: i, offset: 14), extend: true)
            c.setFontFamily(faces[col]); c.setFontSize(sizes[row])
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            if col == 0 { c.setRowHeight(40, exact: true) }
            c.setCellTextDirection(.down)
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}

/// Lab textpitch4: how a turned cell's line pitch follows non-single line spacing. Six faces by six rows:
/// rows 1-3 at 11 pt and rows 4-6 at 13 pt, spacing 1.5 / 2.0 / exactly 20 pt, "Aaaa Bbbb Cccc" turned down in 40 pt exact rows.
final class TextPitch4LabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["TEXTPITCH4_LAB_OUT"] else { throw XCTSkip("no TEXTPITCH4_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 6, columns: 6)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        let faces = ["Calibri", "Cambria", "Consolas", "Verdana", "Tahoma", "Courier New"]
        for (k, i) in idx.enumerated() {
            let col = k % 6, row = k / 6
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText("Aaaa Bbbb Cccc")
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.moveTo(RichPosition(paragraph: i, offset: 14), extend: true)
            c.setFontFamily(faces[col]); c.setFontSize(row < 3 ? 11 : 13)
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            switch row % 3 {
            case 0: c.setLineSpacing(1.5)
            case 1: c.setLineSpacing(2)
            default: c.setParagraphFormat(RichDocumentController.ParagraphFormat(lineRule: .exactly(20)))
            }
            if col == 0 { c.setRowHeight(40, exact: true) }
            c.setCellTextDirection(.down)
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}

/// Lab textpitch5: how a turned cell's lines of NON-Latin text step and where they stop. Rows 1-3: six CJK faces
/// (MS Mincho, Yu Gothic, Meiryo, SimSun, Microsoft YaHei, Malgun Gothic) at 9, 12 and 16 pt; row 4: Mongolian Baiti and
/// Nirmala UI at 9, 12 and 16 pt. Single spacing, Rotate Down, 70 pt exact rows, 78 pt cells, 14 or more characters so
/// that the lines run past the cell.
final class TextPitch5LabWriter: XCTestCase {
    func testWriteLab() throws {
        guard let out = ProcessInfo.processInfo.environment["TEXTPITCH5_LAB_OUT"] else { throw XCTSkip("no TEXTPITCH5_LAB_OUT") }
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 4, columns: 6)
        let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].cell != nil }
        let faces = ["MS Mincho", "Yu Gothic", "Meiryo", "SimSun", "Microsoft YaHei", "Malgun Gothic"]
        let texts = ["日本語の文章を縦に並べて行の間隔を測ります", "日本語の文章を縦に並べて行の間隔を測ります", "日本語の文章を縦に並べて行の間隔を測ります",
                     "中文文本竖排以测量行距和截断位置", "中文文本竖排以测量行距和截断位置", "한국어 문장을 세로로 배열하여 줄 간격을 측정합니다"]
        let mongolian = "ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ ᠦᠰᠦᠭ ᠲᠡᠺᠰᠲ ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ ᠦᠰᠦᠭ"
        let hindi = "हिंदी पाठ को घुमाकर पंक्ति अंतर मापना है"
        let sizes: [Double] = [9, 12, 16]
        var facesByParagraph: [Int: String] = [:]
        for (k, i) in idx.enumerated() {
            let col = k % 6, row = k / 6
            let (face, text): (String, String) = row < 3 ? (faces[col], texts[col]) : (col < 3 ? "Mongolian Baiti" : "Nirmala UI", col < 3 ? mongolian : hindi)
            let size = sizes[row < 3 ? row : col % 3]
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText(text)
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.moveTo(RichPosition(paragraph: i, offset: text.utf16.count), extend: true)
            c.setFontFamily(face); c.setFontSize(size)
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            if col == 0 { c.setRowHeight(70, exact: true) }
            c.setCellTextDirection(.down)
            facesByParagraph[i] = face
        }
        // East Asian and complex-script text takes its own face slot: name the face there too.
        var doc = c.document
        for (i, face) in facesByParagraph {
            for r in doc.paragraphs[i].runs.indices {
                doc.paragraphs[i].runs[r].style.eastAsiaFontFamily = face
                doc.paragraphs[i].runs[r].style.complexFontFamily = face
            }
        }
        try DocxFormat.write(doc, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }
}

/// A turned cell's lines of Latin text step by 1.026 of the face's single line
/// (Word for Windows, lab textpitch3), the same for Rotate Down and Up.
final class TurnedCellPitchTests: XCTestCase {
    private func linesHeight(_ direction: CellRef.CellTextDirection, spacing: Double = 1, text: String = "Aaaa Bbbb Cccc", upright: Bool = false) -> Double {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans, fontSize: 20)
        theme.wordRules = true
        var a = RichParagraph(text: text)
        a.cell = CellRef(table: "t", row: 0, column: 0)
        a.cell?.textDirection = direction
        a.cell?.uprightIdeographs = upright
        a.style.lineSpacing = spacing
        var style = CharStyle()
        style.fontFamily = OfficeFonts.sans; style.fontSize = 20
        a.runs = [Run(length: text.utf16.count, style: style)]
        var doc = RichDocument(paragraphs: [a])
        doc.tableColumns["t"] = [120]
        var ts = TableStyle()
        ts.rowHeights[0] = 70
        ts.rowsExactHeight.insert(0)
        doc.tableStyles["t"] = ts
        let l = RichLayout(theme: theme, paragraphCount: 1)
        l.width = 400
        l.ensureLaidOut(doc)
        return l._heights[0]
    }

    func testTurnedLinesAreOnePointZeroTwoSixOfTheSingleLine() {
        let saved = RichTextTheme.wordWindowsPages
        defer { RichTextTheme.wordWindowsPages = saved }
        RichTextTheme.wordWindowsPages = false
        let plain = linesHeight(.down)
        RichTextTheme.wordWindowsPages = true
        let down = linesHeight(.down), up = linesHeight(.up)
        XCTAssertEqual(down, up, accuracy: 0.01)
        // Lines of Calibri 20: 25.03 apiece in Word's print, 24.41 before.
        XCTAssertEqual(down / plain, 1.026, accuracy: 0.01)
        XCTAssertGreaterThan(down, plain)
    }

    /// Lab textpitch4: at 1.5 and double spacing a turned line steps by 1.5 and 2.0 times the same 1.026 step.
    func testNonSingleSpacingScalesTheTurnedStep() {
        let saved = RichTextTheme.wordWindowsPages
        defer { RichTextTheme.wordWindowsPages = saved }
        for spacing in [1.5, 2.0] {
            RichTextTheme.wordWindowsPages = false
            let plain = linesHeight(.down, spacing: spacing)
            RichTextTheme.wordWindowsPages = true
            XCTAssertEqual(linesHeight(.down, spacing: spacing) / plain, 1.026, accuracy: 0.01, "spacing \(spacing)")
        }
    }

    /// Lab textpitch5: an upright (Rotate Down) column of ideographs steps by the same 1.026 of its face's single line, in 6 faces at 9 and 12 pt.
    func testUprightIdeographColumnsStepByOnePointZeroTwoSix() {
        let saved = RichTextTheme.wordWindowsPages
        defer { RichTextTheme.wordWindowsPages = saved }
        let kanji = "日本語の文章を縦に並べて行の間隔を測ります日本語の文章を縦に並べて"
        RichTextTheme.wordWindowsPages = false
        let plain = linesHeight(.down, text: kanji, upright: true)
        RichTextTheme.wordWindowsPages = true
        let word = linesHeight(.down, text: kanji, upright: true)
        XCTAssertEqual(word / plain, 1.026, accuracy: 0.01)
    }

    /// Word's print of a 78 pt cell of Calibri 20 turned down has three lines of "Aaaa Bbbb Cccc Dddd": the fourth's top falls
    /// past the cell and is not drawn (lab textpitch).
    func testALineBeyondTheTurnedCellIsNotDrawn() {
        // Calibri 20 (ascent 15): baselines 24.8 ... 99.8 give tops 9.8, 34.8, 59.8, 84.8: the fourth goes.
        XCTAssertEqual(RichLayout.turnedLinesKept(tops: [9.8, 34.8, 59.8, 84.8], room: 78), 3)
        XCTAssertEqual(RichLayout.turnedLinesKept(tops: [9.8, 34.8], room: 78), 2)
        // Calibri 13 at double spacing (lab textpitch4, ascent 12): baselines 17.9, 50.3, 82.9 (4.9 past the edge) are all drawn.
        XCTAssertEqual(RichLayout.turnedLinesKept(tops: [5.9, 38.3, 70.9], room: 78), 3)
    }
}
