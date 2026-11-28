// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Web parity 3 and 4 for Slides and Sheets, as Writer has them: in a browser tab, Open is the browser's picker and
/// keeps the file's handle, Save writes back through it, Save As asks the browser for a place (where it can), and
/// what is opened or saved goes into the page's Recent, which reopens it. In-memory stand-ins play the page.
final class BrowserDeckWorkbookFilesTests: XCTestCase {
    private final class Page {
        var place: (handle: Int, name: String)? = (7, "Mine")
        var opened: OfficeHost.BrowserFiles.Picked?
        var picks: [(suggested: String, extensions: [String])] = []
        var writes: [(handle: Int, data: Data)] = []
        var downloads: [(name: String, data: Data)] = []
        var recent: [(name: String, data: Data, handle: Int?)] = []
    }
    private var page = Page()
    private var savedFiles: OfficeHost.BrowserFiles?
    private var savedRecent: OfficeHost.BrowserRecent?
    private var testers: [WidgetTester] = []

    override func setUp() {
        savedFiles = OfficeHost.browserFiles; savedRecent = OfficeHost.browserRecent
        page = Page()
        let page = self.page
        OfficeHost.browserFiles = .init(
            canPickPlace: true,
            open: { _, done in if let picked = page.opened { done(picked) } },
            pickPlace: { suggested, extensions, done in
                page.picks.append((suggested, extensions))
                done(page.place.map { ($0.handle, $0.name + "." + extensions[0]) })
            },
            write: { handle, data, done in page.writes.append((handle, data)); done(true) },
            download: { name, data in page.downloads.append((name, data)) })
        OfficeHost.browserRecent = .init(
            names: { page.recent.map(\.name) },
            remember: { name, data, handle in
                page.recent.removeAll { $0.name == name }
                page.recent.insert((name, data, handle), at: 0)
            },
            open: { name, done in done(page.recent.first { $0.name == name }.map { ($0.name, $0.data, $0.handle) }) })
    }

    override func tearDown() {
        for ui in testers { ui.dispose() }
        testers = []
        OfficeHost.browserFiles = savedFiles; OfficeHost.browserRecent = savedRecent
    }

    private func mount(_ home: Widget) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"),
                              size: Size(1280, 800))
        testers.append(ui)
        ui.pump()
        return ui
    }

    // MARK: Slides

    private func slides(_ path: String? = nil) -> (WidgetTester, OfficeSession) {
        let ui = mount(SlidesShell(initialPath: path, startBlank: path == nil, onSwitch: { _, _ in }))
        return (ui, ui.state(SlidesShellState.self)!.session)
    }

    private func slideCount(_ data: Data) -> Int { (try? Pptx.read(data))?.0.slides.count ?? -1 }

    /// A deck of `slides` slides added to a new deck's first one.
    private func deckBytes(slides: Int) throws -> Data {
        let source = DeckController()
        for _ in 0 ..< slides { _ = source.addSlide() }
        return try Pptx.write(source)
    }

    func testSlidesSaveAsAsksForAPlaceAndSaveWritesThere() throws {
        let (ui, session) = slides()
        let deck = try XCTUnwrap(session.deck)
        _ = deck.addSlide(); ui.pump()
        session.onSaveAs?(); ui.pump()
        XCTAssertEqual(page.picks.map(\.extensions), [["pptx"]], "Save As did not ask the browser for a place")
        XCTAssertEqual(page.writes.map(\.handle), [7])
        XCTAssertEqual(slideCount(page.writes[0].data), deck.slides.count)
        XCTAssertEqual(session.path, "Mine.pptx")
        XCTAssertFalse(session.dirty)
        XCTAssertEqual(page.recent.first?.name, "Mine.pptx", "a saved deck is not in Recent")

        _ = deck.addSlide(); ui.pump()
        session.onSave?(); ui.pump()
        XCTAssertEqual(page.picks.count, 1, "Save asked again for a place it already has")
        XCTAssertEqual(page.writes.map(\.handle), [7, 7])
        XCTAssertEqual(slideCount(page.writes[1].data), deck.slides.count)
        XCTAssertTrue(page.downloads.isEmpty, "a picked place is written, not downloaded")
    }

    func testSlidesAPickedDeckSavesBackToItself() throws {
        page.opened = ("Talk.pptx", try deckBytes(slides: 2), 9)
        let (ui, session) = slides()
        session.onOpen?(); ui.pump()
        XCTAssertEqual(session.path, "Talk.pptx")
        XCTAssertEqual(page.recent.map(\.name), ["Talk.pptx"], "an opened deck is not in Recent")
        _ = session.deck?.addSlide(); ui.pump()
        session.onSave?(); ui.pump()
        XCTAssertTrue(page.picks.isEmpty, "Save asked for a place for a file it can write back to")
        XCTAssertEqual(page.writes.map(\.handle), [9])
        XCTAssertEqual(slideCount(page.writes[0].data), 4, "the saved deck is not the picked one plus a slide")
    }

    /// A deck picked in Writer arrives in Slides with its handle, and saves back to itself there.
    func testSlidesADeckHandedOnByWriterKeepsItsHandle() throws {
        PickedFile.hand("Talk.pptx", try deckBytes(slides: 1), handle: 4)
        let (ui, session) = slides("Talk.pptx")
        _ = session.deck?.addSlide(); ui.pump()
        session.onSave?(); ui.pump()
        XCTAssertTrue(page.picks.isEmpty)
        XCTAssertEqual(page.writes.map(\.handle), [4])
    }

    func testSlidesWithoutPickersSaveDownloadsAndSaveAsAsksForAName() throws {
        OfficeHost.browserFiles?.canPickPlace = false
        let (ui, session) = slides()
        _ = session.deck?.addSlide(); ui.pump()
        session.onSaveAs?(); ui.pump()
        XCTAssertTrue(page.downloads.isEmpty, "Save As downloaded before asking for a name")
        XCTAssertTrue(page.picks.isEmpty)
        session.onSave?(); ui.pump()
        XCTAssertEqual(page.downloads.count, 1)
        XCTAssertTrue(page.downloads.first?.name.hasSuffix(".pptx") ?? false, "\(page.downloads.map(\.name))")
        XCTAssertFalse(session.dirty)
    }

    func testSlidesRecentReopensAKeptDeck() throws {
        page.recent = [("Old.pptx", try deckBytes(slides: 3), nil)]
        let (ui, session) = slides()
        session.onBackstage?(true); ui.pump()
        XCTAssertTrue(ui.tap(text: "Old.pptx"), "Backstage does not list the page's decks: \(ui.texts())")
        ui.pump()
        XCTAssertEqual(session.path, "Old.pptx")
        XCTAssertEqual(session.deck?.slides.count, 4)
        XCTAssertFalse(session.dirty, "a reopened copy is as saved")
    }

    /// Recent keeps the file's handle: a deck opened through the picker, reopened from Recent in a later tab,
    /// saves back to the same file without asking for a place.
    func testSlidesRecentKeepsTheHandleSoSaveWritesBack() throws {
        page.opened = ("Talk.pptx", try deckBytes(slides: 2), 9)
        let (ui, session) = slides()
        session.onOpen?(); ui.pump()
        XCTAssertEqual(page.recent.first?.handle, 9, "Recent did not keep the picked deck's handle")

        let (ui2, session2) = slides()
        session2.onBackstage?(true); ui2.pump()
        XCTAssertTrue(ui2.tap(text: "Talk.pptx"), "\(ui2.texts())")
        ui2.pump()
        _ = session2.deck?.addSlide(); ui2.pump()
        session2.onSave?(); ui2.pump()
        XCTAssertTrue(page.picks.isEmpty, "Save from Recent asked for a place")
        XCTAssertEqual(page.writes.map(\.handle), [9])
        XCTAssertEqual(slideCount(page.writes[0].data), 4)
        XCTAssertTrue(page.downloads.isEmpty)
        _ = ui
    }

    /// A deck saved through Save As goes on Recent with the place it was written to.
    func testSlidesSaveAsKeepsThePlaceOnRecent() throws {
        let (ui, session) = slides()
        session.onSaveAs?(); ui.pump()
        XCTAssertEqual(page.recent.first?.name, "Mine.pptx")
        XCTAssertEqual(page.recent.first?.handle, 7)
    }

    // MARK: Sheets

    private func sheets(_ path: String? = nil) -> (WidgetTester, SheetsShellState) {
        let ui = mount(SheetsShell(initialPath: path, onSwitch: { _, _ in }))
        return (ui, ui.state(SheetsShellState.self)!)
    }

    private func a1(_ data: Data, _ name: String = "x.xlsx") -> CellValue? {
        try? Workbook.open(data, name: name).sheets[0].value(CellAddress(row: 0, col: 0))
    }

    private func bookBytes(_ text: String) throws -> Data {
        let wb = WorkbookController()
        wb.setInputs([(CellAddress(row: 0, col: 0), text)])
        return try Xlsx.write(wb.book)
    }

    func testSheetsSaveAsAsksForAPlaceAndSaveWritesThere() throws {
        let (ui, state) = sheets()
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "first")]); ui.pump()
        state.session.onSaveAs?(); ui.pump()
        XCTAssertEqual(page.picks.first?.extensions, ["xlsx", "csv", "tsv"], "the workbook's own format comes first")
        XCTAssertEqual(page.writes.map(\.handle), [7])
        XCTAssertEqual(a1(page.writes[0].data), .text("first"))
        XCTAssertEqual(state.session.path, "Mine.xlsx")
        XCTAssertFalse(state.session.dirty)
        XCTAssertEqual(page.recent.first?.name, "Mine.xlsx")

        state.wb.setInputs([(CellAddress(row: 0, col: 0), "second")]); ui.pump()
        XCTAssertTrue(state.session.dirty)
        state.session.onSave?(); ui.pump()
        XCTAssertEqual(page.picks.count, 1, "Save asked again for a place it already has")
        XCTAssertEqual(page.writes.map(\.handle), [7, 7])
        XCTAssertEqual(a1(page.writes[1].data), .text("second"))
        XCTAssertFalse(state.session.dirty)
        XCTAssertTrue(page.downloads.isEmpty)
    }

    func testSheetsAPickedCsvSavesBackAsCsv() throws {
        page.opened = ("Data.csv", Data("one,two\n".utf8), 5)
        let (ui, state) = sheets()
        state.session.onOpen?(); ui.pump()
        XCTAssertEqual(state.session.path, "Data.csv")
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "changed")]); ui.pump()
        state.session.onSave?(); ui.pump()
        XCTAssertTrue(page.picks.isEmpty)
        XCTAssertEqual(page.writes.map(\.handle), [5])
        XCTAssertTrue(String(decoding: page.writes.first?.data ?? Data(), as: UTF8.self).hasPrefix("changed,two"),
                      "the picked csv was not written back as csv")
    }

    func testSheetsWithoutPickersSaveDownloads() throws {
        OfficeHost.browserFiles?.canPickPlace = false
        let (ui, state) = sheets()
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "down")]); ui.pump()
        state.session.onSaveAs?(); ui.pump()
        XCTAssertTrue(page.downloads.isEmpty, "Save As downloaded before asking for a name")
        state.session.onSave?(); ui.pump()
        XCTAssertEqual(page.downloads.count, 1)
        XCTAssertEqual(page.downloads.first.flatMap { a1($0.data) }, .text("down"))
        XCTAssertFalse(state.session.dirty)
    }

    /// Recent keeps the file's handle: a workbook reopened from Recent saves back without asking for a place;
    /// a workbook kept without one (a download) asks.
    func testSheetsRecentKeepsTheHandleSoSaveWritesBack() throws {
        page.recent = [("Budget.xlsx", try bookBytes("kept"), 6), ("Down.xlsx", try bookBytes("down"), nil)]
        let (ui, state) = sheets()
        state.session.onBackstage?(true); ui.pump()
        XCTAssertTrue(ui.tap(text: "Budget.xlsx"), "\(ui.texts())")
        ui.pump()
        state.wb.setInputs([(CellAddress(row: 0, col: 0), "changed")]); ui.pump()
        state.session.onSave?(); ui.pump()
        XCTAssertTrue(page.picks.isEmpty, "Save from Recent asked for a place")
        XCTAssertEqual(page.writes.map(\.handle), [6])
        XCTAssertEqual(a1(page.writes[0].data), .text("changed"))
        XCTAssertEqual(page.recent.first?.handle, 6, "the save dropped the handle from Recent")

        let (ui2, state2) = sheets()
        state2.session.onBackstage?(true); ui2.pump()
        XCTAssertTrue(ui2.tap(text: "Down.xlsx"))
        ui2.pump()
        state2.wb.setInputs([(CellAddress(row: 0, col: 0), "again")]); ui2.pump()
        state2.session.onSave?(); ui2.pump()
        XCTAssertEqual(page.picks.count, 1, "a Recent row without a handle must ask for a place")
    }

    func testSheetsRecentReopensAKeptWorkbook() throws {
        page.recent = [("Budget.xlsx", try bookBytes("kept"), nil)]
        let (ui, state) = sheets()
        state.session.onBackstage?(true); ui.pump()
        XCTAssertTrue(ui.tap(text: "Budget.xlsx"), "Backstage does not list the page's workbooks: \(ui.texts())")
        ui.pump()
        XCTAssertEqual(state.session.path, "Budget.xlsx")
        XCTAssertEqual(state.wb.sheet.value(CellAddress(row: 0, col: 0)), .text("kept"))
    }
}
