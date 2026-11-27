import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// U-shared dead-button census: a ribbon, menu or File-tab control shows only when its app carries it out.
/// Slides and Sheets build some of Writer's groups (Clipboard, Paragraph, Table Layout, Review, File > Info),
/// whose items call hooks only Writer's shell sets; those items are hidden there, and the ones the deck can
/// do are wired to it. No tab shows a "not in this build" note.
final class DeadControlTests: XCTestCase {
    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1500, 800))
    }
    private func writer() -> (WidgetTester, OfficeSession) {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true)); return (ui, ui.state(OfficeShellState.self)!.session)
    }
    private func slides() -> (WidgetTester, OfficeSession) {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        return (ui, ui.state(SlidesShellState.self)!.session)
    }
    private func sheets() -> (WidgetTester, OfficeSession) {
        let ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in })); return (ui, ui.state(SheetsShellState.self)!.session)
    }
    private static let tabs = ["Home", "Insert", "Design", "Layout", "Transitions", "Review", "View", "Data", "Formulas",
                               "Page Layout", "Draw", "References", "Animations", "Slide Show"]

    func testNoTabShowsANotInThisBuildNote() {
        var seen = 0
        for (name, ui) in [("Writer", writer().0), ("Slides", slides().0), ("Sheets", sheets().0)] {
            for tab in Self.tabs where ui.has(text: tab) {
                ui.tap(text: tab); seen += 1
                let notes = ui.texts().filter { $0.containsSubstring("not in this build") || $0 == "Coming later" }
                XCTAssertEqual(notes, [], "\(name)/\(tab)")
            }
        }
        XCTAssertGreaterThan(seen, 15)
    }

    /// The items of the menu a ribbon tip opens (the texts that appear when it opens).
    private func menu(_ ui: WidgetTester, tab: String, tip: String) -> Set<String> {
        ui.tap(text: tab)
        let before = Set(ui.texts())
        guard ui.tap(tip: tip) else { return [] }
        let items = Set(ui.texts()).subtracting(before)
        ui.tap(at: Offset(1400, 780))   // close it
        return items
    }

    func testSharedMenusOfferOnlyWhatTheAppDoes() {
        let (w, _) = writer(), (p, _) = slides()
        XCTAssertTrue(w.has(tip: "Paste Options"))
        XCTAssertFalse(p.has(tip: "Paste Options"), "Slides has no paste modes or Paste Special yet")
        XCTAssertTrue(menu(w, tab: "Home", tip: "Line Spacing").contains("Paragraph Options…"))
        let spacing = menu(p, tab: "Home", tip: "Line Spacing")
        XCTAssertTrue(spacing.contains("1.15"), "the menu opened: \(spacing)")
        XCTAssertFalse(spacing.contains("Paragraph Options…"))
        XCTAssertTrue(menu(w, tab: "Home", tip: "Borders").contains("Borders and Shading…"))
        let borders = menu(p, tab: "Home", tip: "Borders")
        XCTAssertTrue(borders.contains("All Borders"), "the menu opened: \(borders)")
        XCTAssertFalse(borders.contains("Borders and Shading…"))
    }

    /// File > Info > Properties… opens a dialog only Writer has; the other apps do not show it.
    func testPropertiesOnlyWhereThereIsADialog() {
        for (name, (ui, _), want) in [("Writer", writer(), true), ("Slides", slides(), false), ("Sheets", sheets(), false)] {
            ui.tap(text: "File")
            if ui.has(text: "Info") { ui.tap(text: "Info") }
            XCTAssertTrue(ui.has(text: "About \(name)") || ui.has(text: "Info"), "\(name): the Info page is open")
            XCTAssertEqual(ui.has(text: "Properties…"), want, name)
        }
    }

    func testSlidesSelectAllPicksEveryShapeOnTheSlide() throws {
        let (ui, session) = slides()
        let deck = try XCTUnwrap(session.deck)
        XCTAssertFalse(deck.currentSlide.shapes.isEmpty, "a blank deck's title slide has placeholders")
        ui.tap(text: "Home")
        XCTAssertTrue(ui.tap(tip: "Select All") || ui.tap(text: "Select All"))
        XCTAssertEqual(deck.selection.count, deck.currentSlide.shapes.count)
    }

    func testSlidesTableToolsUseTheDeckPen() throws {
        let (ui, session) = slides()   // keep the tester: the shell's hooks hold it weakly
        let deck = try XCTUnwrap(session.deck)
        defer { withExtendedLifetime(ui) {} }
        session.onTableTool?("draw"); XCTAssertEqual(deck.tableTool, .draw)
        session.onTableTool?("erase"); XCTAssertEqual(deck.tableTool, .erase)
        session.onTableTool?("erase"); XCTAssertEqual(deck.tableTool, .none)
        XCTAssertNil(session.onTablePropertiesDialog, "if Slides gains a table dialog, the menu shows it by itself")
    }

    func testSlidesWordCountCountsTheDeck() throws {
        let (ui, session) = slides()
        let deck = try XCTUnwrap(session.deck)
        let title = try XCTUnwrap(deck.currentSlide.shapes.first { $0.text != nil }?.text)
        title.insertText("Three little words")
        var said = ""
        session.onStatus = { said = $0 }
        ui.tap(text: "Review")
        XCTAssertTrue(ui.tap(tip: "Word Count") || ui.tap(text: "Word Count"))
        XCTAssertTrue(said.containsSubstring("3 words"), said)
    }

    /// Writer: All Borders includes the line between paragraphs (Outside Borders does not).
    func testWriterAllBordersIncludesInside() throws {
        let (ui, session) = writer()
        let c = session.controller
        c.insertText("One"); c.insertParagraphBreak(); c.insertText("Two"); c.selectAll()
        ui.tap(text: "Home")
        XCTAssertTrue(ui.tap(tip: "Borders"))
        XCTAssertTrue(ui.tap(text: "All Borders"))
        XCTAssertNotNil(c.document.paragraphs[0].style.borders?.between, "\(String(describing: c.document.paragraphs[0].style.borders))")
    }
}
