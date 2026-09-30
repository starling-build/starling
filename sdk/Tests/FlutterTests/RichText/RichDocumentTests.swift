// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// Tests for the rich-text document model and controller: run arithmetic,
/// grapheme motion, word boundaries, and — the one that matters — that every
/// edit's undo restores the exact document, styles included.

import XCTest
@testable import Flutter
import FlutterSwiftBridge

final class RichParagraphTests: XCTestCase {
    func testPlainParagraphHasOneRun() {
        let p = RichParagraph(text: "hello")
        XCTAssertTrue(p.isValid)
        XCTAssertEqual(p.runs.count, 1)
        XCTAssertEqual(p.runs[0].length, 5)
    }

    func testEmptyParagraphKeepsAStyleRun() {
        var p = RichParagraph(text: "a", charStyle: CharStyle(bold: true))
        p.delete(0 ..< 1)
        XCTAssertTrue(p.isValid)
        XCTAssertEqual(p.runs.count, 1)
        XCTAssertEqual(p.runs[0].length, 0)
        XCTAssertTrue(p.runs[0].style.bold)
        XCTAssertTrue(p.style(at: 0).bold)
    }

    func testInsertContinuesStyleBeforeOffset() {
        var p = RichParagraph(text: "ab")
        p.applyStyle(0 ..< 1) { $0.bold = true }
        XCTAssertEqual(p.runs.count, 2)
        p.insert("X", at: 1)          // after the bold "a"
        XCTAssertEqual(p.text, "aXb")
        XCTAssertEqual(p.runs.map(\.length), [2, 1])
        XCTAssertTrue(p.runs[0].style.bold)
        XCTAssertTrue(p.isValid)
    }

    func testApplyStyleSplitsAndMerges() {
        var p = RichParagraph(text: "hello world")
        p.applyStyle(2 ..< 7) { $0.italic = true }
        XCTAssertEqual(p.runs.map(\.length), [2, 5, 4])
        p.applyStyle(2 ..< 7) { $0.italic = false }
        XCTAssertEqual(p.runs.count, 1)
        XCTAssertTrue(p.isValid)
    }

    func testDeleteReturnsRemovedRuns() {
        var p = RichParagraph(text: "abcdef")
        p.applyStyle(2 ..< 4) { $0.underline = true }
        let removed = p.delete(1 ..< 5)
        XCTAssertEqual(removed.text, "bcde")
        XCTAssertEqual(removed.runs.map(\.length), [1, 2, 1])
        XCTAssertEqual(p.text, "af")
        XCTAssertEqual(p.runs.count, 1)
        XCTAssertTrue(p.isValid)
    }

    func testSplitAndAppendRoundTrip() {
        var p = RichParagraph(text: "one two")
        p.applyStyle(4 ..< 7) { $0.bold = true }
        let original = p
        let tail = p.split(at: 3)
        XCTAssertEqual(p.text, "one")
        XCTAssertEqual(tail.text, " two")
        XCTAssertEqual(tail.runs.map(\.length), [1, 3])
        p.append(tail)
        XCTAssertEqual(p, original)
    }

    func testGraphemeMotionSkipsEmoji() {
        let p = RichParagraph(text: "a👍b")   // 👍 is two UTF-16 units
        XCTAssertEqual(p.length, 4)
        XCTAssertEqual(p.graphemeAfter(1), 3)
        XCTAssertEqual(p.graphemeBefore(3), 1)
        XCTAssertEqual(p.alignedOffset(2), 1)
    }

    func testWordBoundaries() {
        let p = RichParagraph(text: "foo bar, baz")
        XCTAssertEqual(p.wordStart(before: 7), 4)     // inside "bar" → its start
        XCTAssertEqual(p.wordStart(before: 4), 0)     // at "bar" start → "foo"
        XCTAssertEqual(p.wordEnd(after: 0), 3)
        XCTAssertEqual(p.wordEnd(after: 3), 7)        // skips the space, eats "bar"
        XCTAssertEqual(p.wordRange(at: 10), 9 ..< 12)
    }
}

final class RichDocumentControllerTests: XCTestCase {
    private func controller(_ lines: String...) -> RichDocumentController {
        RichDocumentController(plainText: lines.joined(separator: "\n"))
    }

    func testTypingCoalescesIntoOneUndo() {
        let c = controller("")
        for ch in "hello" { c.insertText(String(ch)) }
        XCTAssertEqual(c.document.plainText(), "hello")
        c.undo()
        XCTAssertEqual(c.document.plainText(), "")
        XCTAssertFalse(c.canUndo)
        c.redo()
        XCTAssertEqual(c.document.plainText(), "hello")
        XCTAssertEqual(c.caret, RichPosition(paragraph: 0, offset: 5))
    }

    func testCaretMoveBreaksCoalescing() {
        let c = controller("")
        c.insertText("ab")
        c.moveLeft(extend: false)
        c.insertText("X")
        XCTAssertEqual(c.document.plainText(), "aXb")
        c.undo()
        XCTAssertEqual(c.document.plainText(), "ab")
        c.undo()
        XCTAssertEqual(c.document.plainText(), "")
    }

    func testParagraphBreakAndBackspaceJoin() {
        let c = controller("hello world")
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertParagraphBreak()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["hello", " world"])
        XCTAssertEqual(c.caret, RichPosition(paragraph: 1, offset: 0))
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["hello world"])
        XCTAssertEqual(c.caret, RichPosition(paragraph: 0, offset: 5))
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["hello", " world"])
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["hello world"])
    }

    func testMultiParagraphDeleteAndUndoRestoresStyles() {
        let c = controller("first line", "second", "third line")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleBold()
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.setHeading(2)
        let before = c.document
        XCTAssertTrue(before.isValid)

        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: false)
        c.moveTo(RichPosition(paragraph: 2, offset: 6), extend: true)
        c.deleteSelection()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["firline"])
        XCTAssertTrue(c.document.isValid)
        XCTAssertEqual(c.caret, RichPosition(paragraph: 0, offset: 3))

        c.undo()
        XCTAssertEqual(c.document, before)
        c.redo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["firline"])
        c.undo()
        XCTAssertEqual(c.document, before)
    }

    func testToggleBoldOverSelectionAndPendingStyle() {
        let c = controller("bold me")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 4), extend: true)
        XCTAssertFalse(c.selectionAll { $0.bold })
        c.toggleBold()
        XCTAssertTrue(c.selectionAll { $0.bold })
        XCTAssertEqual(c.document.paragraphs[0].runs.map(\.length), [4, 3])

        // Pending style at a collapsed caret applies to the next keystroke.
        c.moveTo(RichPosition(paragraph: 0, offset: 7), extend: false)
        c.toggleItalic()
        XCTAssertNotNil(c.typingStyle)
        c.insertText("!")
        XCTAssertTrue(c.document.paragraphs[0].runs.last!.style.italic)
        XCTAssertEqual(c.document.plainText(), "bold me!")
        // A caret move drops the pending style.
        c.moveLeft(extend: false)
        XCTAssertNil(c.typingStyle)
    }

    func testCopyPasteKeepsFormattingInProcess() {
        let c = controller("alpha", "beta")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleUnderline()
        c.moveTo(RichPosition(paragraph: 0, offset: 2), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 2), extend: true)
        let text = c.copySelection()
        XCTAssertEqual(text, "pha\nbe")
        c.moveTo(c.document.endPosition, extend: false)
        c.paste(text: text!)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["alpha", "betapha", "be"])
        XCTAssertTrue(c.document.paragraphs[1].runs.last!.style.underline)
        XCTAssertTrue(c.document.isValid)
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["alpha", "beta"])
    }

    func testChangeLogTracksParagraphs() {
        let c = controller("a", "b", "c")
        _ = c.drainChanges()
        c.moveTo(RichPosition(paragraph: 1, offset: 1), extend: false)
        c.insertParagraphBreak()
        let changes = c.drainChanges()
        XCTAssertEqual(changes, [.changed(1), .inserted(at: 2, count: 1)])
        c.deleteBackward()
        XCTAssertEqual(c.drainChanges(), [.changed(1), .removed(at: 2, count: 1)])
    }

    func testWordCount() {
        let c = controller("one two  three", "", "four")
        XCTAssertEqual(c.document.wordCount, 4)
    }

    func testNamedStylesApplyAndEnterMovesToNext() {
        let c = controller("My title", "A quote")
        c.setNamedStyle("Title")
        var p = c.document.paragraphs[0].style
        XCTAssertEqual(p.named, "Title")
        XCTAssertNil(p.heading)
        XCTAssertEqual(p.spaceAfter, 4)
        XCTAssertEqual(c.currentNamedStyleId, "Title")
        // Enter at the end of a Title starts a Normal paragraph.
        c.moveToDocumentStart(extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 8), extend: false)
        c.insertParagraphBreak()
        XCTAssertEqual(c.currentNamedStyleId, "Normal")
        XCTAssertNil(c.document.paragraphs[1].style.named)
        // A heading is the sheet's entry too, and Normal clears both.
        c.setHeading(2)
        p = c.document.paragraphs[1].style
        XCTAssertEqual(p.heading, 2)
        XCTAssertEqual(p.spaceBefore, 8)
        XCTAssertEqual(c.currentNamedStyleId, "Heading2")
        c.setNamedStyle("Normal")
        XCTAssertEqual(c.document.paragraphs[1].style, .body)
        // Quote has no next: Enter keeps it, and the list flag survives apply.
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.toggleList(.bullet)
        c.setNamedStyle("Quote")
        p = c.document.paragraphs[2].style
        XCTAssertEqual(p.named, "Quote")
        XCTAssertEqual(p.list, .bullet)
        XCTAssertEqual(p.alignment, .center)
        c.moveToDocumentEnd(extend: false)
        c.insertParagraphBreak()
        XCTAssertEqual(c.document.paragraphs[3].style.named, "Quote")
        c.undo()
        XCTAssertEqual(c.document.paragraphs.count, 3)
        // The layout resolves the sheet's look under direct formatting.
        let theme = RichTextTheme()
        let quote = c.document.styles.resolve(c.document.paragraphs[2].style)
        let ts = theme.textStyle(for: CharStyle(), in: c.document.paragraphs[2].style, named: quote, scale: 1)
        XCTAssertEqual(ts.fontStyle, .italic)
        let bold = theme.textStyle(for: CharStyle(bold: true, italic: false), in: c.document.paragraphs[2].style, named: quote, scale: 1)
        XCTAssertEqual(bold.fontWeight, .bold)
    }

    func testListNumberingFollowsIdsAndFormats() {
        var doc = RichDocument(plainText: "a\nb\nbody\nc\nd\ne\nf\nx\ny")
        func item(_ i: Int, _ level: Int, id: String?) {
            doc.paragraphs[i].style.list = .numbered
            doc.paragraphs[i].style.listLevel = level
            doc.paragraphs[i].style.listId = id
        }
        // List "L" numbers on across the body paragraph; level 2 restarts
        // under a new level-1 item and shows both counters.
        item(0, 0, id: "L"); item(1, 1, id: "L"); item(3, 1, id: "L"); item(4, 0, id: "L"); item(5, 1, id: "L")
        doc.listFormats["L"] = [1: ListLevelFormat(text: "%1.%2", format: .lowerLetter)]
        // Anonymous runs restart after an interruption.
        item(6, 0, id: nil); item(8, 0, id: nil)
        XCTAssertEqual(RichListNumbering.labels(doc),
                       ["1.", "1.a", nil, "1.b", "2.", "2.a", "1.", nil, "1."])
        XCTAssertEqual(ListNumberFormat.lowerRoman.string(14), "xiv")
        XCTAssertEqual(ListNumberFormat.upperLetter.string(28), "BB")
    }

    func testListEnterAndBackspaceRules() {
        let c = controller("item", "")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.toggleList(.bullet)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.toggleList(.bullet)
        // Enter on the empty item ends the list instead of adding a bullet.
        c.insertParagraphBreak()
        XCTAssertEqual(c.document.paragraphs.count, 2)
        XCTAssertNil(c.document.paragraphs[1].style.list)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[1].style.list, .bullet)
        // Backspace at the start of an item takes the bullet first, then joins.
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.count, 2)
        XCTAssertNil(c.document.paragraphs[1].style.list)
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["item"])
    }

    func testParagraphMotionAndDeleteToLineStart() {
        let c = controller("first para", "second para")
        c.moveTo(RichPosition(paragraph: 1, offset: 6), extend: false)
        c.moveToParagraphStart(extend: false)
        XCTAssertEqual(c.caret, RichPosition(paragraph: 1, offset: 0))
        c.moveToParagraphStart(extend: false)
        XCTAssertEqual(c.caret, RichPosition(paragraph: 0, offset: 0))
        c.moveToParagraphEnd(extend: false)
        XCTAssertEqual(c.caret, RichPosition(paragraph: 0, offset: 10))
        c.moveToParagraphEnd(extend: true)
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: 1, offset: 11))
        XCTAssertEqual(c.selection.anchor, RichPosition(paragraph: 0, offset: 10))
        c.moveTo(RichPosition(paragraph: 1, offset: 6), extend: false)
        c.deleteBackward(toOffset: 0)
        XCTAssertEqual(c.document.paragraphs[1].text, " para")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[1].text, "second para")
    }

    func testPictureSelectionAndResize() {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==")!
        let c = controller("before", "after")
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.insertImage(ImageAttachment(data: png, width: 120, height: 80, naturalWidth: 300, naturalHeight: 200))
        // The picture, then an empty paragraph so typing can go on below it.
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["before", "", "", "after"])
        XCTAssertNil(c.selectedImageIndex)
        c.selectImage(at: 1)
        XCTAssertEqual(c.selectedImageIndex, 1)
        c.setImageSize(at: 1, width: 60, height: 40)
        XCTAssertEqual(c.document.paragraphs[1].image?.width, 60)
        XCTAssertEqual(c.document.paragraphs[1].image?.naturalWidth, 300)
        XCTAssertEqual(c.drainChanges().last, .changed(1))
        c.undo()
        XCTAssertEqual(c.document.paragraphs[1].image?.width, 120)
        c.redo()
        XCTAssertEqual(c.document.paragraphs[1].image?.height, 40)
        // Delete removes the selected picture.
        c.deleteForward()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["before", "", "after"])
    }

    func testLinks() {
        let c = controller("see the site here")
        c.moveTo(RichPosition(paragraph: 0, offset: 8), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 12), extend: true)
        c.setLink("https://a.dev")
        XCTAssertEqual(c.document.paragraphs[0].runs(in: 8 ..< 12)[0].style.link, "https://a.dev")
        XCTAssertNil(c.document.paragraphs[0].runs(in: 0 ..< 4)[0].style.link)
        // The caret inside the link reports it; nil removes the whole run.
        c.moveTo(RichPosition(paragraph: 0, offset: 10), extend: false)
        XCTAssertEqual(c.currentLink, "https://a.dev")
        c.setLink(nil)
        XCTAssertNil(c.document.paragraphs[0].runs(in: 8 ..< 12)[0].style.link)
        XCTAssertEqual(c.document.paragraphs[0].text, "see the site here")
        // Nothing selected: the address becomes the text.
        c.moveToDocumentEnd(extend: false)
        c.insertText(" ")
        c.setLink("https://b.dev")
        XCTAssertEqual(c.document.paragraphs[0].text, "see the site here https://b.dev")
        XCTAssertEqual(c.document.paragraphs[0].runs.last?.style.link, "https://b.dev")
        XCTAssertTrue(c.selection.isCollapsed)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "see the site here ")
    }

    func testTableColumns() {
        let c = controller("")
        c.insertTable(rows: 2, columns: 2)
        c.insertText("a")
        c.moveToAdjacentCell(forward: true); c.insertText("b")
        c.moveToAdjacentCell(forward: true); c.insertText("c")
        c.moveToAdjacentCell(forward: true); c.insertText("d")
        let id = c.currentCell!.table
        c.setTableColumnWidths(id, [200, 300])
        // Insert right of column 0 (caret in "d", column 1 → left of it instead).
        c.moveTo(RichPosition(paragraph: 0, offset: 1), extend: false)
        c.insertColumn(after: true)
        XCTAssertEqual(cells(c), ["0,0:a", "0,1:", "0,2:b", "1,0:c", "1,1:", "1,2:d", "-"])
        XCTAssertEqual(c.document.tableColumns[id] ?? [], [100, 100, 300])
        XCTAssertEqual(c.caret, RichPosition(paragraph: 1, offset: 0))
        // Cells and widths are one undo step.
        c.undo()
        XCTAssertEqual(cells(c), ["0,0:a", "0,1:b", "1,0:c", "1,1:d", "-"])
        XCTAssertEqual(c.document.tableColumns[id] ?? [], [200, 300])
        // Delete column 1: its width goes to the neighbour.
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.deleteColumn()
        XCTAssertEqual(cells(c), ["0,0:a", "1,0:c", "-"])
        XCTAssertEqual(c.document.tableColumns[id] ?? [], [500])
        c.distributeColumns()
        XCTAssertNil(c.document.tableColumns[id])
        // The last column goes with the table.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.deleteColumn()
        XCTAssertEqual(cells(c), ["-"])
        XCTAssertTrue(c.document.isValid)
    }

    func testChangeCaseKeepsRuns() {
        let c = controller("hello WORLD. fine day")
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 11), extend: true)
        c.toggleBold()
        c.selectAll()
        c.changeCase(.sentence)
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello world. Fine day")
        XCTAssertTrue(c.document.paragraphs[0].runs(in: 6 ..< 11)[0].style.bold)
        c.changeCase(.capitalizeWords)
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello World. Fine Day")
        c.changeCase(.toggle)
        XCTAssertEqual(c.document.paragraphs[0].text, "hELLO wORLD. fINE dAY")
        c.undo(); c.undo(); c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "hello WORLD. fine day")
        // With no selection, the word at the caret.
        c.moveTo(RichPosition(paragraph: 0, offset: 2), extend: false)
        c.changeCase(.upper)
        XCTAssertEqual(c.document.paragraphs[0].text, "HELLO WORLD. fine day")
        XCTAssertTrue(c.document.isValid)
    }

    func testUpdateStyleToMatchSelection() {
        let c = controller("A heading", "body")
        c.setHeading(1)
        c.selectAll()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.setFontSize(30)   // the caret's typing style, not a run: use a selection
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 9), extend: true)
        c.setFontSize(30)
        c.setAlignment(.center)
        c.updateStyleToMatchSelection("Heading1")
        XCTAssertEqual(c.document.styles["Heading1"]?.char.fontSize, 30)
        XCTAssertEqual(c.document.styles["Heading1"]?.paragraph.alignment, .center)
        XCTAssertEqual(c.document.styles["Heading1"]?.paragraph.heading, 1)
        XCTAssertEqual(c.drainChanges().last, .all)
        c.undo()
        XCTAssertEqual(c.document.styles["Heading1"]?.char.fontSize, 20)
    }

    func testMergeAndSplitCells() {
        let c = controller("")
        c.insertTable(rows: 2, columns: 3)
        c.insertText("a"); c.moveToAdjacentCell(forward: true); c.insertText("b")
        c.moveToAdjacentCell(forward: true); c.insertText("c")
        // Select a..b (two cells of row 0) and merge.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 1), extend: true)
        XCTAssertEqual(c.selectedCellsInRow.map(\.column), [0, 1])
        c.mergeCells()
        XCTAssertEqual(cells(c), ["0,0:a", "0,0:b", "0,2:c", "1,0:", "1,1:", "1,2:", "-"])
        XCTAssertEqual(c.document.paragraphs[0].cell?.span, 2)
        XCTAssertEqual(c.document.columnCount(of: c.currentCell!.table), 3)
        // Tab from the merged cell goes to c.
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.moveToAdjacentCell(forward: true)
        XCTAssertEqual(c.caret.paragraph, 2)
        // Insert a column inside the span widens it; delete narrows it.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.insertColumn(after: true)
        XCTAssertEqual(c.document.paragraphs[0].cell?.span, 3)
        XCTAssertEqual(cells(c).count, 8)
        c.undo()
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.splitCell()
        XCTAssertEqual(cells(c), ["0,0:a", "0,0:b", "0,1:", "0,2:c", "1,0:", "1,1:", "1,2:", "-"])
        XCTAssertEqual(c.document.paragraphs[0].cell?.span, 1)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].cell?.span, 2)
        XCTAssertTrue(c.document.isValid)
    }

    func testVerticalMergeAndSplit() {
        let c = controller("")
        c.insertTable(rows: 3, columns: 2)
        c.insertText("a"); c.moveToAdjacentCell(forward: true); c.insertText("b")
        c.moveToAdjacentCell(forward: true); c.insertText("c")
        c.moveToAdjacentCell(forward: true); c.insertText("d")
        // Select a (0,0) down to c (1,0) and merge: a's cell spans two rows.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 2, offset: 1), extend: true)
        XCTAssertEqual(c.selectedCellsInColumn.map(\.row), [0, 1])
        c.mergeCells()
        XCTAssertEqual(cells(c), ["0,0:a", "0,0:c", "0,1:b", "1,1:d", "2,0:", "2,1:", "-"])
        XCTAssertEqual(c.document.paragraphs[0].cell?.rowSpan, 2)
        XCTAssertEqual(c.document.paragraphs[1].cell?.rowSpan, 2)
        // A row inserted inside the span widens it and gets no cell under it.
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)   // b, row 0
        c.insertRow(below: true)
        XCTAssertEqual(c.document.paragraphs[0].cell?.rowSpan, 3)
        XCTAssertEqual(cells(c).filter { $0.hasPrefix("1,") }, ["1,1:"])
        c.undo()
        // Split restores an empty cell in the covered row.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.splitCell()
        XCTAssertEqual(cells(c), ["0,0:a", "0,0:c", "0,1:b", "1,0:", "1,1:d", "2,0:", "2,1:", "-"])
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].cell?.rowSpan, 2)
        // Deleting the span's first row keeps its content, one row shorter.
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.deleteRow()
        XCTAssertEqual(cells(c), ["0,0:a", "0,0:c", "0,1:d", "1,0:", "1,1:", "-"])
        XCTAssertEqual(c.document.paragraphs[0].cell?.rowSpan, 1)
        XCTAssertTrue(c.document.isValid)
    }

    func testReviewFixes() {
        // Split Cell of a merged cell that ends its row but not the table.
        let c = controller("")
        c.insertTable(rows: 2, columns: 2)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: true)
        c.mergeCells()
        // Both cells' paragraphs survive the merge, in order.
        XCTAssertEqual(cells(c), ["0,0:", "0,0:", "1,0:", "1,1:", "-"])
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.splitCell()
        XCTAssertEqual(cells(c), ["0,0:", "0,0:", "0,1:", "1,0:", "1,1:", "-"])
        // A soft line break stays inside the paragraph.
        let d = controller("ab")
        d.moveTo(RichPosition(paragraph: 0, offset: 1), extend: false)
        d.insertLineBreak()
        XCTAssertEqual(d.document.paragraphs.map(\.text), ["a\nb"])
        XCTAssertEqual(d.caret, RichPosition(paragraph: 0, offset: 2))
        // Applying a style keeps the paragraph in its list.
        var style = RichParagraphStyle(list: .numbered, listId: "L7")
        RichStyleSheet.word.apply("Heading1", to: &style)
        XCTAssertEqual(style.listId, "L7")
        XCTAssertEqual(style.heading, 1)
    }

    func testAutocorrectWhileTyping() {
        let c = controller("")
        for ch in "\"Hello,\" she said--then left... (c) 2026 it's" { c.insertTyped(String(ch)) }
        c.insertTyped(" ")
        XCTAssertEqual(c.document.paragraphs[0].text, "\u{201C}Hello,\u{201D} she said\u{2014}then left\u{2026} \u{00A9} 2026 it\u{2019}s ")
        // Pasted text is left alone, and so is typing with autocorrect off.
        c.insertText(" \"raw\"")
        XCTAssertTrue(c.document.paragraphs[0].text.hasSuffix(" \"raw\""))
        c.autocorrect = false
        c.insertTyped("\"")
        XCTAssertTrue(c.document.paragraphs[0].text.hasSuffix("\""))
        // Undo takes the whole typing run back as usual.
        while c.canUndo { c.undo() }
        XCTAssertEqual(c.document.paragraphs[0].text, "")
    }

    func testListLibraryAssignsIdsAndFormats() {
        let c = controller("a", "b", "c", "x", "d")
        // An anonymous numbered run of three, then a body line, then one more.
        for i in [0, 1, 2, 4] {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.toggleList(.numbered)
        }
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.setListFormat(ListLevelFormat(text: "%1)", format: .lowerLetter))
        // The whole run got one id and the format; the separate item did not.
        let ids = c.document.paragraphs.map(\.style.listId)
        XCTAssertNotNil(ids[0]); XCTAssertEqual(ids[0], ids[1]); XCTAssertEqual(ids[1], ids[2])
        XCTAssertNil(ids[3]); XCTAssertNil(ids[4])
        XCTAssertEqual(RichListNumbering.labels(c.document), ["a)", "b)", "c)", nil, "1."])
        XCTAssertEqual(c.currentListFormat?.sample(2), "b)")
        // One undo step takes it all back.
        c.undo()
        XCTAssertEqual(RichListNumbering.labels(c.document), ["1.", "2.", "3.", nil, "1."])
        XCTAssertNil(c.document.paragraphs[0].style.listId)
        // A bullet from the library turns the item into a bullet with that glyph.
        c.moveTo(RichPosition(paragraph: 4, offset: 0), extend: false)
        c.setListFormat(ListLevelFormat(text: "\u{2713}", format: .bullet))
        XCTAssertEqual(c.document.paragraphs[4].style.list, .bullet)
        XCTAssertEqual(RichListNumbering.labels(c.document)[4], "\u{2713}")
        XCTAssertEqual(ListLevelFormat.numberingLibrary[4].sample(4), "iv.")
    }

    func testCellBlockClosesOverMergedCellsAndRangesNeverCrossWalls() {
        let c = controller("")
        c.insertTable(rows: 3, columns: 3)
        for (i, t) in ["a", "b", "c", "d", "e", "f", "g", "h", "i"].enumerated() {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText(t)
        }
        // Merge b down into e: (0,1) spans two rows.
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 4, offset: 0), extend: true)
        c.mergeCells()
        XCTAssertEqual(c.document.paragraphs[1].cell?.rowSpan, 2)
        // Selecting across row 1 (d → f) must take the tall cell whole:
        // the block grows to rows 0...1.
        let d = c.document.paragraphs.firstIndex { $0.text == "d" }!
        let f = c.document.paragraphs.firstIndex { $0.text == "f" }!
        c.moveTo(RichPosition(paragraph: d, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: f, offset: 1), extend: true)
        XCTAssertEqual(c.selection.block?.rows, 0 ... 1)
        XCTAssertEqual(c.selection.block?.columns, 0 ... 2)
        c.mergeCells()
        XCTAssertTrue(c.document.isValid)
        XCTAssertEqual(c.document.paragraphs[0].cell?.span, 3)
        XCTAssertEqual(c.document.paragraphs[0].cell?.rowSpan, 2)
        c.undo(); c.undo()
        // A word drag from one cell into the next is a block too.
        let origin = c.unitSpan(at: RichPosition(paragraph: 0, offset: 0), paragraph: false)
        c.extendSelection(to: RichPosition(paragraph: 1, offset: 0), byParagraph: false, from: origin)
        XCTAssertNotNil(c.selection.block)
        // A plain range leaving the table clears, and never merges a cell
        // into the text after it.
        let last = c.document.paragraphs.count - 1
        c.moveTo(RichPosition(paragraph: last, offset: 0), extend: false)
        c.insertText("after")
        c.selection = RichSelection(anchor: RichPosition(paragraph: 8, offset: 0), focus: RichPosition(paragraph: last, offset: 2))
        XCTAssertNil(c.selection.block)
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.count, last + 1)
        XCTAssertEqual(c.document.paragraphs[8].text, "")
        XCTAssertEqual(c.document.paragraphs[last].text, "ter")
        XCTAssertTrue(c.document.isValid)
    }

    func testSmartPadTakesDestinationStyleAndDropSelectsText() {
        let c = controller("one two")
        // A linked word pasted between words: the added spaces are not linked.
        var link = RichParagraph(text: "web")
        link.applyStyle(0 ..< 3) { $0.link = "https://x" }
        c.moveTo(RichPosition(paragraph: 0, offset: 3), extend: false)   // "one| two"
        c.insertFragment([link], smart: true)
        XCTAssertEqual(c.document.paragraphs[0].text, "one web two")
        XCTAssertNil(c.document.paragraphs[0].style(at: 3).link)
        XCTAssertEqual(c.document.paragraphs[0].style(at: 5).link, "https://x")
        XCTAssertNil(c.document.paragraphs[0].style(at: 8).link)
        // A fragment that starts with a space and gets a trailing pad still
        // selects exactly itself after a drop.
        let d = controller("ab cd")
        d.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 2), focus: RichPosition(paragraph: 0, offset: 5))   // " cd"
        d.moveSelection(to: RichPosition(paragraph: 0, offset: 0), copy: false)
        XCTAssertEqual(d.document.paragraphs[0].text, " cd ab")
        XCTAssertEqual(d.document.text(in: d.selection), " cd")
        // Library entries are written for level 1; deeper levels count their own.
        let f = ListLevelFormat(text: "%1)", format: .lowerLetter)
        XCTAssertEqual(f.forLevel(2).text, "%3)")
        XCTAssertEqual(f.forLevel(2).asLibraryEntry(atLevel: 2), f)
        XCTAssertEqual(ListLevelFormat.plain(1).asLibraryEntry(atLevel: 1), .plain(0))
    }

    func testSmartCutKeepsSpaceBeforeOpeners() {
        let c = controller("foo bar (baz)")
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 4), focus: RichPosition(paragraph: 0, offset: 8))
        _ = c.cutSelectionData()
        XCTAssertEqual(c.document.paragraphs[0].text, "foo (baz)")
    }

    func testNumberingOnBulletItemDoesNotRestyleNeighbours() {
        let c = controller("b1", "b2", "n1", "n2")
        for i in 0 ... 1 { c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false); c.toggleList(.bullet) }
        for i in 2 ... 3 { c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false); c.toggleList(.numbered) }
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.setListFormat(ListLevelFormat(text: "%1)", format: .lowerLetter))
        XCTAssertEqual(RichListNumbering.labels(c.document), ["\u{2022}", "a)", "1.", "2."])
        XCTAssertNil(c.document.paragraphs[2].style.listId)
    }

    func testPasteOntoPictureGoesBelow() {
        let c = controller("text")
        c.moveTo(RichPosition(paragraph: 0, offset: 4), extend: false)
        c.insertImage(ImageAttachment(data: Data(), width: 10, height: 10, name: "p"))
        let img = c.document.paragraphs.firstIndex { $0.isImage }!
        c.moveTo(RichPosition(paragraph: img, offset: 0), extend: false)
        c.insertFragment([RichParagraph(text: "pasted")])
        XCTAssertTrue(c.document.paragraphs[img].isImage)
        XCTAssertEqual(c.document.paragraphs[img].text, "")
        XCTAssertEqual(c.document.paragraphs[img + 1].text, "pasted")
    }

    func testDragByWordsAndParagraphs() {
        let c = controller("one two three", "four five")
        // A double click on "two", then a drag to "three": whole words.
        let origin = c.unitSpan(at: RichPosition(paragraph: 0, offset: 5), paragraph: false)
        XCTAssertEqual(c.document.text(in: origin), "two")
        c.extendSelection(to: RichPosition(paragraph: 0, offset: 10), byParagraph: false, from: origin)
        XCTAssertEqual(c.document.text(in: c.selection), "two three")
        // Back before the origin: from the word under the pointer to the origin's end.
        c.extendSelection(to: RichPosition(paragraph: 0, offset: 1), byParagraph: false, from: origin)
        XCTAssertEqual(c.document.text(in: c.selection), "one two")
        XCTAssertEqual(c.selection.focus.offset, 0)
        // Triple click then drag down: whole paragraphs.
        let para = c.unitSpan(at: RichPosition(paragraph: 0, offset: 3), paragraph: true)
        c.extendSelection(to: RichPosition(paragraph: 1, offset: 2), byParagraph: true, from: para)
        XCTAssertEqual(c.document.text(in: c.selection), "one two three\nfour five")
    }

    func testSmartCutAndPaste() {
        let c = controller("the cat sat.")
        // Cut a word: the two spaces it leaves become one.
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 4), focus: RichPosition(paragraph: 0, offset: 7))
        let cut = c.cutSelectionData()
        XCTAssertEqual(cut?.text, "cat")
        XCTAssertEqual(c.document.paragraphs[0].text, "the sat.")
        // Paste it between words: it gets the space it needs on both sides.
        c.moveTo(RichPosition(paragraph: 0, offset: 7), extend: false)   // "the sat|."
        c.paste(data: cut!)
        XCTAssertEqual(c.document.paragraphs[0].text, "the sat cat.")
        // Cut the last word before the full stop: no space is left before it.
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 8), focus: RichPosition(paragraph: 0, offset: 11))
        _ = c.cutSelectionData()
        XCTAssertEqual(c.document.paragraphs[0].text, "the sat.")
        // Cut at the start: no leading space stays.
        c.selection = RichSelection(anchor: .start, focus: RichPosition(paragraph: 0, offset: 3))
        _ = c.cutSelectionData()
        XCTAssertEqual(c.document.paragraphs[0].text, "sat.")
        // Plain-text paste into a word boundary pads too; Backspace does not tidy.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.paste(data: ClipboardData(text: "the"))
        XCTAssertEqual(c.document.paragraphs[0].text, "the sat.")
        // Off, nothing is touched.
        c.smartSpacing = false
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 4), focus: RichPosition(paragraph: 0, offset: 7))
        _ = c.cutSelectionData()
        XCTAssertEqual(c.document.paragraphs[0].text, "the .")
    }

    func testDragAndDropMovesSelection() {
        let c = controller("one two three")
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0),
                                    focus: RichPosition(paragraph: 0, offset: 4))
        // Forward drop past the selection: the text lands where the pointer
        // was, and stays selected there.
        c.moveSelection(to: RichPosition(paragraph: 0, offset: 8), copy: false)
        XCTAssertEqual(c.document.paragraphs[0].text, "two one three")
        XCTAssertEqual(c.document.text(in: c.selection), "one ")
        XCTAssertEqual(c.selection.start.offset, 4)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "one two three")
        // A bare word dropped after another gets its space (smart cut and
        // paste), the leading space it left behind goes, and the word
        // itself is what stays selected.
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0),
                                    focus: RichPosition(paragraph: 0, offset: 3))
        c.moveSelection(to: RichPosition(paragraph: 0, offset: 7), copy: false)
        XCTAssertEqual(c.document.paragraphs[0].text, "two one three")
        XCTAssertEqual(c.document.text(in: c.selection), "one")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].text, "one two three")
        // ⌥-drag copies.
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0),
                                    focus: RichPosition(paragraph: 0, offset: 4))
        c.moveSelection(to: RichPosition(paragraph: 0, offset: 13), copy: true)
        XCTAssertEqual(c.document.paragraphs[0].text, "one two three one ")
        c.undo()
        // A drop inside the selection is a no-op; across paragraphs the
        // paragraph index shifts with the removal.
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 0),
                                    focus: RichPosition(paragraph: 0, offset: 4))
        c.moveSelection(to: RichPosition(paragraph: 0, offset: 2), copy: false)
        XCTAssertEqual(c.document.paragraphs[0].text, "one two three")
        c.moveTo(RichPosition(paragraph: 0, offset: 13), extend: false)
        c.insertParagraphBreak()
        c.insertText("four")
        c.selection = RichSelection(anchor: RichPosition(paragraph: 0, offset: 4),
                                    focus: RichPosition(paragraph: 1, offset: 0))
        c.moveSelection(to: RichPosition(paragraph: 1, offset: 4), copy: false)
        // The fragment ends with a paragraph break, so the break lands too.
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["one fourtwo three", ""])
        XCTAssertEqual(c.document.text(in: c.selection), "two three\n")
        XCTAssertTrue(c.document.isValid)
    }

    func testCellBlockSelection() {
        let c = controller("")
        c.insertTable(rows: 3, columns: 3)
        for (i, t) in ["a", "b", "c", "d", "e", "f", "g", "h", "i"].enumerated() {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertText(t)
        }
        // Drag from a (0,0) to e (1,1): a 2×2 block, not the reading-order run.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 4, offset: 1), extend: true)
        let block = c.selection.block
        XCTAssertEqual(block?.rows, 0 ... 1)
        XCTAssertEqual(block?.columns, 0 ... 1)
        XCTAssertEqual(c.document.paragraphIndices(in: c.selection), [0, 1, 3, 4])
        XCTAssertEqual(c.document.fragment(c.selection).map(\.text), ["a", "b", "d", "e"])
        // Formatting applies to the block's cells only.
        c.toggleBold()
        XCTAssertTrue(c.document.paragraphs[3].runs[0].style.bold)
        XCTAssertFalse(c.document.paragraphs[2].runs[0].style.bold)
        // Delete clears the cells and keeps them.
        c.deleteSelection()
        XCTAssertEqual(cells(c), ["0,0:", "0,1:", "0,2:c", "1,0:", "1,1:", "1,2:f", "2,0:g", "2,1:h", "2,2:i", "-"])
        c.undo()
        // Merge a block into its top-left cell.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 4, offset: 1), extend: true)
        c.mergeCells()
        XCTAssertEqual(cells(c), ["0,0:a", "0,0:b", "0,0:d", "0,0:e", "0,2:c", "1,2:f", "2,0:g", "2,1:h", "2,2:i", "-"])
        XCTAssertEqual(c.document.paragraphs[0].cell?.span, 2)
        XCTAssertEqual(c.document.paragraphs[0].cell?.rowSpan, 2)
        // Extending within one cell, or out of the table, is a plain selection.
        c.moveTo(RichPosition(paragraph: 6, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 6, offset: 1), extend: true)
        XCTAssertNil(c.selection.block)
        c.moveTo(RichPosition(paragraph: 9, offset: 0), extend: true)
        XCTAssertNil(c.selection.block)
        XCTAssertTrue(c.document.isValid)
    }

    private func cells(_ c: RichDocumentController) -> [String] {
        c.document.paragraphs.map { p in
            guard let cell = p.cell else { return "-" }
            return "\(cell.row),\(cell.column):\(p.text)"
        }
    }

    func testInsertTableAndTabBetweenCells() {
        let c = controller("intro")
        c.moveToDocumentEnd(extend: false)
        c.insertTable(rows: 2, columns: 2)
        XCTAssertEqual(cells(c), ["-", "0,0:", "0,1:", "1,0:", "1,1:", "-"])
        XCTAssertEqual(c.caret, RichPosition(paragraph: 1, offset: 0))
        XCTAssertTrue(c.isInCell)
        c.insertText("a")
        c.moveToAdjacentCell(forward: true)
        c.insertText("b")
        c.moveToAdjacentCell(forward: true)
        c.moveToAdjacentCell(forward: true)
        c.insertText("d")
        XCTAssertEqual(cells(c), ["-", "0,0:a", "0,1:b", "1,0:", "1,1:d", "-"])
        // Past the last cell: the paragraph after the table.
        c.moveToAdjacentCell(forward: true)
        XCTAssertEqual(c.caret, RichPosition(paragraph: 5, offset: 0))
        XCTAssertFalse(c.isInCell)
        // Backspace at a cell wall never joins.
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.count, 6)
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.deleteBackward()
        XCTAssertEqual(cells(c), ["-", "0,0:a", "0,1:b", "1,0:", "1,1:d", "-"])
        // Undo removes the whole table in one step.
        c.undo(); c.undo(); c.undo()
        XCTAssertEqual(cells(c), ["-", "0,0:", "0,1:", "1,0:", "1,1:", "-"])
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["intro"])
    }

    func testTableRowsAndDelete() {
        let c = controller("")
        c.insertTable(rows: 2, columns: 2)
        c.insertText("a")
        c.moveToAdjacentCell(forward: true); c.moveToAdjacentCell(forward: true)
        c.insertText("c")
        c.moveTo(RichPosition(paragraph: 0, offset: 1), extend: false)
        c.insertRow(below: true)
        XCTAssertEqual(cells(c), ["0,0:a", "0,1:", "1,0:", "1,1:", "2,0:c", "2,1:", "-"])
        XCTAssertEqual(c.caret, RichPosition(paragraph: 2, offset: 0))
        c.insertRow(below: false)
        XCTAssertEqual(cells(c), ["0,0:a", "0,1:", "1,0:", "1,1:", "2,0:", "2,1:", "3,0:c", "3,1:", "-"])
        c.undo()
        XCTAssertEqual(cells(c), ["0,0:a", "0,1:", "1,0:", "1,1:", "2,0:c", "2,1:", "-"])
        c.moveTo(RichPosition(paragraph: 4, offset: 0), extend: false)
        c.deleteRow()
        XCTAssertEqual(cells(c), ["0,0:a", "0,1:", "1,0:", "1,1:", "-"])
        c.deleteTable()
        XCTAssertEqual(cells(c), ["-"])
        XCTAssertEqual(c.caret, RichPosition(paragraph: 0, offset: 0))
        c.undo()
        XCTAssertEqual(cells(c), ["0,0:a", "0,1:", "1,0:", "1,1:", "-"])
        XCTAssertTrue(c.document.isValid)
    }
}

final class KeyChordTests: XCTestCase {
    private func key(_ logical: Int64, _ type: KeyEventType = .down, character: String? = nil) -> KeyData {
        KeyData(timeStamp: 0, type: type, physical: 0, logical: logical,
                character: character, synthesized: false)
    }

    func testBothNumberingsName() {
        XCTAssertEqual(KeyChordTracker.named(0xFF51), .left)
        XCTAssertEqual(KeyChordTracker.named(0x1_0000_0302), .left)
        XCTAssertEqual(KeyChordTracker.named(0xFF0D), .enter)
        XCTAssertEqual(KeyChordTracker.named(0x2_0000_020D), .enter)
        XCTAssertEqual(KeyChordTracker.named(0xFFBE), .function(1))
        XCTAssertEqual(KeyChordTracker.named(0x1_0000_0803), .function(3))
    }

    func testModifierTracking() {
        let t = KeyChordTracker()
        XCTAssertTrue(t.track(key(0xFFE3)))               // Ctrl down (keysym)
        XCTAssertTrue(t.control)
        XCTAssertFalse(t.track(key(0x63, character: "\u{03}")))  // Ctrl+C control byte
        XCTAssertNil(t.typedText(key(0x63, character: "\u{03}")))
        XCTAssertTrue(t.track(key(0xFFE3, .up)))
        XCTAssertFalse(t.control)
        XCTAssertTrue(t.track(key(0x2_0000_0106)))        // Cmd down (Flutter id)
        XCTAssertTrue(t.meta)
        XCTAssertNil(t.typedText(key(0x63, character: "c")))
        t.reset()
        XCTAssertEqual(t.typedText(key(0x63, character: "c")), "c")
        XCTAssertEqual(KeyChordTracker.letter(0x43), "c")
    }
}
