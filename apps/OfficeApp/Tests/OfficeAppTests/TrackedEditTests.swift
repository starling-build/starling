// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// With track changes on (`w:trackRevisions` in the settings), the editor's own edits are recorded as Word
/// records them: typed text is a `w:ins` with the reviewer's name and the time.
final class TrackedEditTests: XCTestCase {
    private var savedReviewer: (() -> (author: String, date: String))!
    override func setUp() {
        savedReviewer = RichDocumentController.reviewer
        RichDocumentController.reviewer = { ("Tester", "2026-11-27T10:00:00Z") }
        RichDocumentController.runPropertiesXML = { DocxFormat._rPrXML($0) }
    }
    override func tearDown() { RichDocumentController.reviewer = savedReviewer }

    private func open(_ text: String, tracking: Bool) throws -> RichDocumentController { try open([text], tracking: tracking) }

    private func open(_ texts: [String], tracking: Bool) throws -> RichDocumentController {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: texts.map { RichParagraph(text: $0) }), pageSetup: .letter))
        entries.removeAll { $0.name == "word/settings.xml" }
        let settings = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + (tracking ? "<w:trackRevisions/>" : "") + "<w:defaultTabStop w:val=\"720\"/></w:settings>"
        entries.append(ZipEntry(name: "word/settings.xml", data: Data(settings.utf8)))
        return RichDocumentController(document: try DocxFormat.read(try Zip.write(entries)).document)
    }

    private func saved(_ c: RichDocumentController) throws -> (body: String, settings: String) {
        let entries = try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter))
        func part(_ n: String) -> String { String(decoding: entries.first { $0.name == n }?.data ?? Data(), as: UTF8.self) }
        return (part("word/document.xml"), part("word/settings.xml"))
    }

    private func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }

    func testTypedTextIsATrackedInsertion() throws {
        let c = try open("Hello world", tracking: true)
        XCTAssertTrue(c.document.trackRevisions)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText(" there")
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello there world")
        let marked = c.document.paragraphs[0].runs.filter { $0.style.revision?.kind == .inserted }
        XCTAssertEqual(marked.map(\.length), [6])
        let out = try saved(c)
        XCTAssertEqual(count(out.body, "<w:ins "), 1)
        XCTAssertTrue(out.body.containsSubstring("w:author=\"Tester\" w:date=\"2026-11-27T10:00:00Z\""))
        XCTAssertTrue(out.body.containsSubstring("<w:t xml:space=\"preserve\"> there</w:t></w:r></w:ins>"), out.body)
        XCTAssertTrue(out.settings.containsSubstring("<w:trackRevisions/>"))
    }

    /// The app's own reviewer: the user's name and the full UTC time of the edit, as Word writes it
    /// (2026-11-27T16:42:05Z), not the day alone (Word showed "12:00:00" for a fixed lab clock).
    func testTheAppsReviewerStampsTheTimeOfDay() throws {
        setenv("OFFICE_NOW", "2026-11-27T16:42:05", 1); setenv("OFFICE_USER", "bob", 1)
        defer { unsetenv("OFFICE_NOW"); unsetenv("OFFICE_USER") }
        WriterCharts.installHooks()
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText("!")
        let out = try saved(c)
        XCTAssertTrue(out.body.containsSubstring("w:author=\"bob\" w:date=\"2026-11-27T16:42:05Z\""), out.body)
    }

    /// Enter with tracking on: Word marks the pilcrow ending the text before the caret as inserted.
    func testANewParagraphMarkIsATrackedInsertion() throws {
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertParagraphBreak()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Hello", " world"])
        XCTAssertEqual(c.document.paragraphs[0].style.markRevision?.kind, .inserted)
        XCTAssertNil(c.document.paragraphs[1].style.markRevision)
        let out = try saved(c)
        XCTAssertEqual(count(out.body, "<w:ins "), 1)
        XCTAssertTrue(out.body.containsSubstring("<w:rPr><w:ins w:id="), out.body)
    }

    func testWithoutTrackingTypingIsPlain() throws {
        let c = try open("Hello world", tracking: false)
        XCTAssertFalse(c.document.trackRevisions)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText(" there")
        c.insertParagraphBreak()
        XCTAssertFalse(try saved(c).body.containsSubstring("<w:ins "))
    }

    // MARK: Deletions (w:del)

    /// Backspace and Delete over the file's text: it stays, marked deleted by the reviewer, and saves as
    /// `w:del` with `w:delText`; Delete steps the caret past what it marked.
    func testDeletedTextStaysMarked() throws {
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.deleteBackward()
        XCTAssertEqual(c.selection.focus.offset, 4)
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.deleteForward()
        XCTAssertEqual(c.selection.focus.offset, 7)
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello world")
        let marked = c.document.paragraphs[0].runs.filter { $0.style.revision?.kind == .deleted }
        XCTAssertEqual(marked.map(\.length), [1, 1])
        XCTAssertEqual(marked.first?.style.revision?.author, "Tester")
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:del "), 2)
        XCTAssertTrue(out.containsSubstring("<w:delText>o</w:delText>"), out)
        XCTAssertTrue(out.containsSubstring("<w:delText>w</w:delText>"), out)
        XCTAssertTrue(out.containsSubstring("<w:del w:id=\"") && out.containsSubstring("w:author=\"Tester\" w:date=\"2026-11-27T10:00:00Z\""), out)
    }

    /// Deleting what the reviewer typed takes it away, leaving no change behind.
    func testDeletingOwnInsertionRemovesIt() throws {
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText("abc")
        c.deleteBackward(); c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs[0].text, "Helloa world")
        c.insertParagraphBreak()
        c.deleteBackward()   // the mark the reviewer just made goes too
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Helloa world"])
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:ins "), 1)
        XCTAssertEqual(count(out, "<w:del "), 0)
    }

    /// Backspace at a paragraph's start marks the previous paragraph's mark deleted; the paragraphs stay.
    func testJoiningMarksTheParagraphMarkDeleted() throws {
        let c = try open(["One", "Two"], tracking: true)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["One", "Two"])
        XCTAssertEqual(c.document.paragraphs[0].style.markRevision?.kind, .deleted)
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: 0, offset: 3))
        XCTAssertTrue(try saved(c).body.containsSubstring("<w:rPr><w:del w:id="))
    }

    /// Typing over a selection that spans paragraphs: the selection is marked deleted, the marks between
    /// too, and the new text follows it as an insertion.
    func testTypingOverASelectionAcrossParagraphs() throws {
        let c = try open(["One two", "three four"], tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 4), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 5), extend: true)
        c.insertText("X")
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["One two", "threeX four"])
        XCTAssertEqual(c.document.paragraphs[0].style.markRevision?.kind, .deleted)
        XCTAssertEqual(c.document.paragraphs[1].runs.map { $0.style.revision?.kind }, [.deleted, .inserted, nil])
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:ins "), 1)
        XCTAssertEqual(count(out, "<w:del "), 3)  // "two", the mark, "three"
    }

    func testWithoutTrackingDeletingRemoves() throws {
        let c = try open(["One", "Two"], tracking: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.deleteBackward(); c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["OnTwo"])
        XCTAssertFalse(try saved(c).body.containsSubstring("<w:del "))
    }

    // MARK: Formatting (w:rPrChange, w:pPrChange)

    /// Bold on the file's text: the run keeps the properties it had before, by the reviewer; a second change
    /// keeps the first one's "before".
    func testFormattingIsATrackedFormatChange() throws {
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleBold()
        c.applyCharStyle { $0.italic = true }
        let run = c.document.paragraphs[0].runs[0]
        XCTAssertTrue(run.style.bold && run.style.italic)
        XCTAssertEqual(run.style.formatChange?.author, "Tester")
        XCTAssertEqual(run.style.formatChange?.oldRPrXML.containsSubstring("<w:b/>"), false)
        XCTAssertNil(c.document.paragraphs[0].runs.last?.style.formatChange)
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:rPrChange "), 1, out)
        XCTAssertTrue(out.containsSubstring("w:author=\"Tester\" w:date=\"2026-11-27T10:00:00Z\"><w:rPr>"), out)
    }

    /// The editor shows a tracked change: a change bar in the margin beside the changed line only, as Word does,
    /// for a formatting change as much as for typed text.
    func testATrackedChangeShowsAChangeBar() throws {
        let c = try open(["Hello world", "Untouched line"], tracking: true)
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12), paragraphCount: 2)
        layout.width = 400
        layout.pageSetup = .letter
        let all = Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6)
        layout.ensureLaidOut(c.document)
        XCTAssertEqual(layout.canvasChangeBars(c.document, visible: all), [])
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleBold()
        layout.invalidateAll()
        layout.ensureLaidOut(c.document)
        let bars = layout.canvasChangeBars(c.document, visible: all)
        XCTAssertEqual(bars.count, 1)
        let first = layout.canvasCaretRect(RichPosition(paragraph: 0, offset: 0), c.document)
        let second = layout.canvasCaretRect(RichPosition(paragraph: 1, offset: 0), c.document)
        XCTAssertLessThan(bars[0].right, first.left)
        XCTAssertLessThan(bars[0].top, second.top)
        XCTAssertGreaterThan(bars[0].bottom, first.top)
    }

    /// Formatting what the reviewer just typed records nothing more: it is an insertion either way.
    func testFormattingOwnInsertionIsNotAChange() throws {
        let c = try open("Hello", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText(" new")
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 9), extend: true)
        c.toggleBold()
        XCTAssertFalse(try saved(c).body.containsSubstring("<w:rPrChange "))
    }

    /// A paragraph's alignment: w:pPrChange with the paragraph's earlier properties.
    func testParagraphFormatIsATrackedChange() throws {
        let c = try open("Hello", tracking: true)
        c.setAlignment(.center)
        XCTAssertNotNil(c.document.paragraphs[0].style.propertyChange)
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:pPrChange "), 1, out)
        XCTAssertTrue(out.containsSubstring("<w:jc w:val=\"center\"/>"), out)
        XCTAssertFalse(out.components(separatedBy: "<w:pPrChange ")[1].containsSubstring("center"), out)
    }

    func testWithoutTrackingFormattingIsPlain() throws {
        let c = try open("Hello", tracking: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleBold(); c.setAlignment(.center)
        let out = try saved(c).body
        XCTAssertFalse(out.containsSubstring("Change "))
    }

    // MARK: The Review tab (Track Changes, Accept, Reject, Previous / Next, Show Markup)

    /// One of each kind: an insertion, a deletion, bold, centring, a new paragraph mark. Returns the controller
    /// and the original text.
    private func everyKind() throws -> RichDocumentController {
        let c = try open(["Hello world", "Second line"], tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText(" big")                                               // "Hello big world"
        c.moveTo(RichPosition(paragraph: 0, offset: 10), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 15), extend: true)
        c.deleteBackward()                                                 // "world" marked deleted
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 6), extend: true)
        c.toggleBold()                                                     // "Second" bold
        c.setAlignment(.center)                                            // paragraph 2 centred
        c.moveTo(RichPosition(paragraph: 1, offset: 11), extend: false)
        c.insertParagraphBreak()                                           // a new (inserted) mark
        return c
    }

    func testAcceptAllKeepsEveryChangeAndClearsTheMarks() throws {
        let c = try everyKind()
        XCTAssertGreaterThan(c.resolveAllChanges(accept: true), 0)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Hello big ", "Second line", ""])
        XCTAssertTrue(c.document.paragraphs[1].runs[0].style.bold)
        XCTAssertEqual(c.document.paragraphs[1].style.alignment, .center)
        XCTAssertEqual(c.trackedChanges(), [])
        let out = try saved(c).body
        for tag in ["<w:ins ", "<w:del ", "<w:rPrChange ", "<w:pPrChange "] { XCTAssertFalse(out.containsSubstring(tag), tag) }
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Hello big world", "Second line", ""])
        XCTAssertFalse(c.trackedChanges().isEmpty)
    }

    func testRejectAllPutsTheOriginalBack() throws {
        let c = try everyKind()
        XCTAssertGreaterThan(c.resolveAllChanges(accept: false), 0)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Hello world", "Second line"])
        XCTAssertFalse(c.document.paragraphs[1].runs.contains { $0.style.bold })
        XCTAssertNotEqual(c.document.paragraphs[1].style.alignment, .center)
        XCTAssertEqual(c.trackedChanges(), [])
        let out = try saved(c).body
        for tag in ["<w:ins ", "<w:del ", "<w:rPrChange ", "<w:pPrChange "] { XCTAssertFalse(out.containsSubstring(tag), tag) }
    }

    /// Next steps through the changes in order and wraps; Reject This Change with the caret inside one
    /// resolves that one alone.
    func testNextSelectsEachChangeAndRejectThisOneLeavesTheRest() throws {
        let c = try everyKind()
        let all = c.trackedChanges()
        XCTAssertGreaterThanOrEqual(all.count, 5)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        for want in all {
            XCTAssertTrue(c.selectAdjacentChange(forward: true))
            XCTAssertEqual(c.selection.start, want.start); XCTAssertEqual(c.selection.end, want.end)
        }
        XCTAssertTrue(c.selectAdjacentChange(forward: true))
        XCTAssertEqual(c.selection.start, all[0].start)                    // wrapped
        XCTAssertTrue(c.selectAdjacentChange(forward: false))
        XCTAssertEqual(c.selection.start, all.last!.start)
        // The caret in " big": rejecting removes it, the deletion after it stays.
        c.moveTo(RichPosition(paragraph: 0, offset: 7), extend: false)
        XCTAssertEqual(c.resolveChanges(accept: false), 1)
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello world")
        XCTAssertEqual(c.document.paragraphs[0].runs.last?.style.revision?.kind, .deleted)
        XCTAssertEqual(c.trackedChanges().count, all.count - 1)
    }

    /// A file's own format change: Reject puts back the look its old w:rPr / w:pPr describes.
    func testRejectingAFilesFormatChangeRestoresTheOldLook() throws {
        let body = "<w:p><w:pPr><w:jc w:val=\"center\"/><w:pPrChange w:id=\"1\" w:author=\"A\" w:date=\"2026-01-01T00:00:00Z\"><w:pPr/></w:pPrChange></w:pPr>"
            + "<w:r><w:rPr><w:b/><w:rPrChange w:id=\"2\" w:author=\"A\" w:date=\"2026-01-01T00:00:00Z\"><w:rPr><w:i/></w:rPr></w:rPrChange></w:rPr><w:t>Hi</w:t></w:r></w:p>"
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let i = entries.firstIndex { $0.name == "word/document.xml" }!
        let xml = String(decoding: entries[i].data, as: UTF8.self)
        let a = xml.rangeOfSubstring("<w:body>")!.upperBound, b = xml.rangeOfSubstring("<w:sectPr")!.lowerBound
        entries[i] = ZipEntry(name: entries[i].name, data: Data((String(xml[..<a]) + body + String(xml[b...])).utf8))
        let c = RichDocumentController(document: try DocxFormat.read(try Zip.write(entries)).document)
        XCTAssertTrue(c.document.paragraphs[0].runs[0].style.bold)
        XCTAssertEqual(c.document.paragraphs[0].style.alignment, .center)
        c.resolveAllChanges(accept: false)
        let s = c.document.paragraphs[0].runs[0].style
        XCTAssertFalse(s.bold); XCTAssertTrue(s.italic); XCTAssertNil(s.formatChange)
        XCTAssertNotEqual(c.document.paragraphs[0].style.alignment, .center)
        XCTAssertNil(c.document.paragraphs[0].style.propertyChange)
    }

    /// Enter at a line's end and typing, under tracking, is one change for Next (the new mark and the text), as in
    /// Word: the Mac run of the Review script stopped on the mark alone first.
    func testEnterAndTypingIsOneStopForNext() throws {
        let c = try open(["First line", "Other"], tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 10), extend: false)
        c.insertParagraphBreak()
        c.insertText("Typed")
        XCTAssertEqual(c.trackedChanges(), [.init(start: RichPosition(paragraph: 0, offset: 10), end: RichPosition(paragraph: 1, offset: 5))])
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertTrue(c.selectAdjacentChange(forward: true))
        XCTAssertEqual(c.selection.end, RichPosition(paragraph: 1, offset: 5))
        XCTAssertEqual(c.resolveChanges(accept: false), 2)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["First line", "Other"])
    }

    /// Show Markup > Original draws the old formatting too, as Word does: "Second" not bold, its paragraph not centred.
    /// The document itself keeps the change, and every position stays where it was.
    func testOriginalViewShowsTheOldFormatting() throws {
        let c = try everyKind()
        let shown = c.originalDocument
        XCTAssertFalse(shown.paragraphs[1].runs[0].style.bold)
        XCTAssertNotEqual(shown.paragraphs[1].style.alignment, .center)
        XCTAssertEqual(shown.paragraphs.map(\.length), c.document.paragraphs.map(\.length))
        XCTAssertTrue(c.document.paragraphs[1].runs[0].style.bold)
        XCTAssertEqual(c.document.paragraphs[1].style.alignment, .center)
        // Made again after an edit.
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 6), extend: true)
        c.resolveChanges(accept: true)
        XCTAssertTrue(c.originalDocument.paragraphs[1].runs[0].style.bold)
    }

    /// Track Changes on and off: the save writes w:trackRevisions in the settings, or takes it out.
    func testTrackChangesSwitchIsSaved() throws {
        let c = try open("Hello", tracking: false)
        c.setTrackRevisions(true)
        XCTAssertTrue(try saved(c).settings.containsSubstring("<w:trackRevisions/>"))
        c.insertText("x")
        XCTAssertEqual(c.trackedChanges().count, 1)
        c.setTrackRevisions(false)
        XCTAssertFalse(try saved(c).settings.containsSubstring("trackRevisions"))
        let fresh = DocxFormat._trackRevisionsSetting("<w:settings><w:zoom w:percent=\"100\"/><w:defaultTabStop w:val=\"720\"/><w:characterSpacingControl w:val=\"doNotCompress\"/></w:settings>", on: true)
        XCTAssertTrue(fresh.containsSubstring("<w:trackRevisions/><w:defaultTabStop"), fresh)
    }

    /// Show Markup: No Markup hides deleted text and shows no bars; Original hides the inserted text instead.
    func testMarkupModesHideTheRightText() throws {
        let c = try everyKind()
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
        let layout = RichLayout(theme: theme, paragraphCount: c.document.paragraphs.count)
        layout.width = 400
        layout.pageSetup = .letter
        let all = Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6)
        func width(_ m: RichTextTheme.Markup) -> Double {
            theme.markup = m
            layout.invalidateAll(); layout.ensureLaidOut(c.document)
            return layout.canvasCaretRect(RichPosition(paragraph: 0, offset: 15), c.document).left
                - layout.canvasCaretRect(RichPosition(paragraph: 0, offset: 0), c.document).left
        }
        let full = width(.all)
        XCTAssertFalse(layout.canvasChangeBars(c.document, visible: all).isEmpty)
        XCTAssertLessThan(width(.none), full)                              // "world" hidden
        XCTAssertEqual(layout.canvasChangeBars(c.document, visible: all), [])
        XCTAssertLessThan(width(.original), full)                          // " big" hidden
        XCTAssertFalse(width(.simple) < width(.none) - 0.01)
    }
}
