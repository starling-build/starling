// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-FD-2: a table of contents made from the headings, brought up to date, saved and reopened; the dialog reaches it.
final class ContentsInsertTests: XCTestCase {
    private func controller() -> RichDocumentController {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: [
            RichParagraph(text: ""),
            RichParagraph(text: "Intro", style: RichParagraphStyle(heading: 1)),
            RichParagraph(text: "Body text"),
            RichParagraph(text: "Details", style: RichParagraphStyle(heading: 2)),
            RichParagraph(text: "Deep", style: RichParagraphStyle(heading: 4)),
        ]))
        return c
    }

    /// The numbers come from the layout WITH the table in place: a heading that the entries push down is listed on its new page.
    func testInsertFillsPagesFromTheLayoutWithTheTableInPlace() throws {
        let c = controller()
        // A toy layout: three paragraphs to a page, counted in the document it is given.
        let layout: (RichDocument) -> (Int) -> String? = { _ in { String($0 / 3 + 1) } }
        XCTAssertTrue(c.insertTableOfContents(ContentsOptions(), width: 400, pageOf: layout(c.document), layout: layout))
        let ps = c.document.paragraphs
        // Entries 0-1, closing 2, empty none: "Intro" now sits at paragraph 3 (page 2), "Details" at 5 (page 2).
        let intro = ps.firstIndex { $0.text == "Intro" }!, details = ps.firstIndex { $0.text == "Details" }!
        XCTAssertEqual(ps[0].text, "Intro\t\(intro / 3 + 1)")
        XCTAssertEqual(ps[1].text, "Details\t\(details / 3 + 1)")
        XCTAssertNotEqual(intro / 3 + 1, 1 / 3 + 1, "the numbers moved with the table")
        c.undo()
        XCTAssertEqual(c.document.paragraphs.count, 5, "one undo step takes it all back")
    }

    /// Entries use the built-in "toc N" styles, added to the file's styles, with no direct indent.
    func testEntriesUseTheTocStyles() throws {
        let c = controller()
        XCTAssertTrue(c.insertTableOfContents(ContentsOptions(), width: 400, pageOf: { _ in "1" }))
        let ps = c.document.paragraphs
        XCTAssertEqual(ps[0].style.named, "TOC1")
        XCTAssertEqual(ps[1].style.named, "TOC2")
        XCTAssertEqual(ps[1].style.indentLeft, 0, "the indent is the style's")
        XCTAssertEqual(c.document.styles["TOC2"]?.name, "toc 2")
        XCTAssertEqual(c.document.styles["TOC2"]?.paragraph.indentLeft, 11)
        let parts = try Zip.read(DocxFormat.write(c.document, pageSetup: .letter))
        let xml = String(decoding: try XCTUnwrap(parts.first { $0.name == "word/styles.xml" }).data, as: UTF8.self)
        XCTAssertTrue(xml.contains("w:styleId=\"TOC2\""), "styles.xml defines it")
        XCTAssertTrue(xml.contains("w:val=\"toc 2\""))
    }

    func testInsertListsHeadingsAndSavesAsAField() throws {
        let c = controller()
        XCTAssertTrue(c.insertTableOfContents(ContentsOptions(), width: 400, pageOf: { _ in "7" }))
        let ps = c.document.paragraphs
        // The empty caret paragraph became the entries (two headings within three levels) and the closing paragraph.
        XCTAssertEqual(ps[0].text, "Intro\t7")
        XCTAssertEqual(ps[1].text, "Details\t7")
        XCTAssertEqual(ps[0].style.named, "TOC1")
        XCTAssertEqual(c.document.styles["TOC2"]?.paragraph.indentLeft, 11, "the level indent is in the style")
        XCTAssertEqual(ps[0].style.tabStops.first?.leader, "dot")
        XCTAssertEqual(ps[0].style.tabStops.first?.alignment, .right)
        XCTAssertEqual(ps[0].style.contentsStart, "TOC \\o \"1-3\" \\h \\z \\u")
        XCTAssertTrue(ps[2].style.contentsEnd)
        let intro = try XCTUnwrap(ps.first { $0.text == "Intro" })
        let mark = try XCTUnwrap(intro.bookmarks.first)
        XCTAssertTrue(mark.hasPrefix("_Toc"))
        XCTAssertEqual(ps[0].runs.first?.style.link, "#" + mark)
        XCTAssertEqual(ps[0].runs.last?.style.field, "PAGEREF \(mark) \\h")
        // Saved and reopened, it is still a table of contents.
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertTrue(back.paragraphs[0].style.contentsStart?.hasPrefix("TOC ") == true)
        XCTAssertTrue(back.paragraphs.contains { $0.style.contentsEnd })
        XCTAssertEqual(back.paragraphs[0].text, "Intro\t7")
        c.undo()
        XCTAssertNil(c.document.paragraphs[0].style.contentsStart)
        XCTAssertEqual(c.document.paragraphs.count, 5)
    }

    func testNoHeadingsInsertsNothing() {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: [RichParagraph(text: "plain")]))
        XCTAssertFalse(c.insertTableOfContents(ContentsOptions(), width: 400, pageOf: { _ in "1" }))
        XCTAssertEqual(c.document.paragraphs.count, 1)
    }

    func testUpdatePagesOnlyAndEntireTable() {
        let c = controller()
        c.insertTableOfContents(ContentsOptions(), width: 400, pageOf: { _ in "1" })
        XCTAssertTrue(c.updateTableOfContents(pagesOnly: true, width: 400, pageOf: { $0 > 3 ? "5" : "2" }))
        XCTAssertEqual(c.document.paragraphs[0].text.split(separator: "\t").last, "2")
        XCTAssertEqual(c.document.paragraphs[1].text.split(separator: "\t").last, "5")
        // A new heading shows up only in the entire-table update.
        let at = c.document.paragraphs.count
        c.moveTo(RichPosition(paragraph: at - 1, offset: c.document.paragraphs[at - 1].length), extend: false)
        c.insertParagraphBreak(); c.insertText("Added"); c.setHeading(1)
        XCTAssertTrue(c.updateTableOfContents(pagesOnly: true, width: 400, pageOf: { _ in "9" }))
        XCTAssertFalse(c.document.paragraphs.contains { $0.text.hasPrefix("Added\t") })
        XCTAssertTrue(c.updateTableOfContents(pagesOnly: false, width: 400, pageOf: { _ in "9" }))
        XCTAssertTrue(c.document.paragraphs.contains { $0.text == "Added\t9" })
        XCTAssertEqual(c.document.paragraphs.filter { $0.style.contentsStart != nil }.count, 1)
    }

    func testUpdateWithNoTableSaysSo() {
        let c = controller()
        XCTAssertFalse(c.updateTableOfContents(pagesOnly: false, width: 400, pageOf: { _ in "1" }))
    }

    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        let c = session.controller
        c.insertText("Chapter"); c.setHeading(1)
        return (ui, session)
    }

    func testDialogEnterInsertsAndEscapeDoesNot() {
        let (ui, session) = shell()
        session.onContentsDialog?(); ui.pump()
        XCTAssertTrue(ui.has(id: "toc-levels"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "toc-levels"))
        XCTAssertNil(session.controller.document.paragraphs[0].style.contentsStart)
        session.onContentsDialog?(); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "toc-levels"))
        XCTAssertTrue(session.controller.document.paragraphs.contains { $0.style.contentsStart != nil })
        session.controller.undo()
        XCTAssertFalse(session.controller.document.paragraphs.contains { $0.style.contentsStart != nil })
    }

    /// Writes the file for the Word check (only when TOC_CHECK_OUT names a path).
    func testWriteWordCheckFile() throws {
        guard let out = ProcessInfo.processInfo.environment["TOC_CHECK_OUT"] else { throw XCTSkip("no TOC_CHECK_OUT") }
        var paragraphs = [RichParagraph(text: "")]
        for (i, title) in ["Introduction", "Background", "Method", "Results", "Discussion"].enumerated() {
            paragraphs.append(RichParagraph(text: title, style: RichParagraphStyle(heading: 1)))
            paragraphs.append(RichParagraph(text: "Body of " + title))
            paragraphs.append(RichParagraph(text: title + " detail", style: RichParagraphStyle(heading: 2)))
            if i < 4 { var b = RichParagraph(text: "More text"); b.style.pageBreakBefore = true; paragraphs.append(b) }
        }
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: paragraphs))
        let layout: (RichDocument) -> (Int) -> String? = { PdfExport.pageLabels($0, pageSetup: .letter, theme: RichTextTheme()) }
        XCTAssertTrue(c.insertTableOfContents(ContentsOptions(), width: 451, pageOf: layout(c.document), layout: layout))
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
    }

    /// W-FD-3: Insert Table of Figures lists the captions of one label, in Word's "table of figures" style, as a
    /// `TOC \c` field that saves, reopens and updates (a new caption joins the list).
    func testTableOfFiguresListsTheCaptionsOfOneLabel() throws {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: [
            RichParagraph(text: ""),
            RichParagraph(text: "Intro", style: RichParagraphStyle(heading: 1)),
            RichParagraph(text: "A picture"),
            RichParagraph(text: "A table"),
            RichParagraph(text: "Another picture"),
        ]))
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.insertCaption(label: "Figure", title: ": A cat", place: .below, excludeLabel: false)
        c.moveTo(RichPosition(paragraph: 4, offset: 0), extend: false)
        c.insertCaption(label: "Table", title: ": Sizes", place: .below, excludeLabel: false)
        c.moveTo(RichPosition(paragraph: 6, offset: 0), extend: false)
        c.insertCaption(label: "Figure", title: ": A dog", place: .below, excludeLabel: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        var options = ContentsOptions()
        options.caption = "Figure"
        XCTAssertTrue(c.insertTableOfContents(options, width: 400, pageOf: { _ in "3" }))
        var ps = c.document.paragraphs
        XCTAssertEqual(ps[0].text, "Figure 1: A cat\t3")
        XCTAssertEqual(ps[1].text, "Figure 2: A dog\t3", "the Table caption is not listed")
        XCTAssertTrue(ps[2].style.contentsEnd)
        XCTAssertEqual(ps[0].style.contentsStart, "TOC \\h \\z \\c \"Figure\"")
        XCTAssertEqual(ps[0].style.named, "TableofFigures")
        XCTAssertEqual(c.document.styles["TableofFigures"]?.name, "table of figures")
        XCTAssertEqual(ContentsOptions(instruction: "TOC \\h \\z \\c \"Figure\"").caption, "Figure")
        // Saved and reopened, the field still names the label.
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].style.contentsStart, "TOC \\h \\z \\c \"Figure\"")
        // A new figure caption, then Update Entire Table: it joins the list.
        let last = c.document.paragraphs.count - 1
        c.moveTo(RichPosition(paragraph: last, offset: 0), extend: false)
        c.insertCaption(label: "Figure", title: ": A bird", place: .below, excludeLabel: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertTrue(c.updateTableOfContents(pagesOnly: false, width: 400, pageOf: { _ in "4" }))
        ps = c.document.paragraphs
        XCTAssertEqual(ps[0].text, "Figure 1: A cat\t4")
        XCTAssertEqual(ps[2].text, "Figure 3: A bird\t4")
        XCTAssertTrue(ps[3].style.contentsEnd)
    }
}
