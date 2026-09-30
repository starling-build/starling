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
