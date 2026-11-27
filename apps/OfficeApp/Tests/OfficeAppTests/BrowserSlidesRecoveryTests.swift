// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Web parity 2 for Slides: a deck edited in a browser tab keeps its recovery copy in the page (IndexedDB), as
/// Writer's document does (BrowserRecoveryTests). An in-memory stand-in plays the page.
final class BrowserSlidesRecoveryTests: XCTestCase {
    private final class Page {
        var mine: (kind: String, name: String, data: Data)?
        var orphans: [(kind: String, name: String, data: Data)] = []
        var keeps = 0
    }
    private var page = Page()
    private var saved: OfficeHost.BrowserRecovery?

    override func setUp() {
        saved = OfficeHost.browserRecovery
        page = Page()
        let page = self.page
        OfficeHost.browserRecovery = .init(
            keep: { kind, name, data in page.mine = (kind, name, data); page.keeps += 1 },
            discard: { page.mine = nil },
            take: { kind in
                guard let i = page.orphans.firstIndex(where: { $0.kind == kind }) else { return nil }
                let row = page.orphans.remove(at: i)
                page.mine = row
                return (row.name, row.data)
            })
    }

    override func tearDown() { OfficeHost.browserRecovery = saved }

    private func shell(blank: Bool) -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: blank, onSwitch: { _, _ in }),
                                        title: "Test"),
                              size: Size(1280, 800))
        return (ui, ui.state(SlidesShellState.self)!.session)
    }

    private func waitForCopy(_ ui: WidgetTester) {
        let deadline = Date().addingTimeInterval(4)
        while page.mine == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); ui.pump()
        }
    }

    func testAnEditIsCopiedAfterThePause() throws {
        let (ui, session) = shell(blank: true)
        let deck = try XCTUnwrap(session.deck)
        let before = deck.slides.count
        _ = deck.addSlide()
        ui.pump()
        waitForCopy(ui)
        guard let row = page.mine else { return XCTFail("no recovery copy reached the page") }
        XCTAssertEqual(row.kind, "pptx")
        XCTAssertTrue(row.name.hasSuffix(".pptx"), row.name)
        let (state, _, _) = try Pptx.read(row.data)
        XCTAssertEqual(state.slides.count, before + 1)
    }

    func testACopyLeftByAClosedTabIsRestored() throws {
        let source = DeckController()
        _ = source.addSlide(); _ = source.addSlide()
        let bytes = try Pptx.write(source)
        page.orphans = [("docx", "Report.docx", Data("not a document".utf8)), ("pptx", "Talk.pptx", bytes)]
        let (ui, session) = shell(blank: false)
        ui.pump()
        XCTAssertEqual(session.deck?.slides.count, source.slides.count)
        XCTAssertEqual(session.path, "Talk.pptx")
        XCTAssertTrue(session.dirty, "a restored deck is unsaved")
        XCTAssertEqual(page.orphans.count, 1, "Slides took only the Slides copy")
        XCTAssertEqual(page.mine?.name, "Talk.pptx", "the restored copy is now this tab's")
    }

    /// A tab always starts in Writer: with only a deck's copy waiting, Writer hands it to Slides, which opens it
    /// unsaved under its name.
    func testWriterHandsADecksCopyToSlides() throws {
        let source = DeckController()
        _ = source.addSlide(); _ = source.addSlide()
        let bytes = try Pptx.write(source)
        page.orphans = [("pptx", "Talk.pptx", bytes)]
        var switched: (DocumentKind, String?)?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, onSwitch: { switched = ($0, $1) }),
                                        title: "Test"),
                              size: Size(1280, 800))
        ui.pump(); ui.pump()
        XCTAssertEqual(switched?.0, .presentation)
        XCTAssertEqual(switched?.1, "Talk.pptx")
        XCTAssertTrue(page.orphans.isEmpty)
        // What OfficeRoot builds next for that switch.
        let next = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                          home: SlidesShell(initialPath: "Talk.pptx", startBlank: false, onSwitch: { _, _ in }),
                                          title: "Test"),
                                size: Size(1280, 800))
        next.pump()
        let session = next.state(SlidesShellState.self)!.session
        XCTAssertEqual(session.deck?.slides.count, source.slides.count)
        XCTAssertEqual(session.path, "Talk.pptx")
        XCTAssertTrue(session.dirty, "a restored deck is unsaved")
    }

    func testAnUnchangedDeckIsNotCopiedAgain() throws {
        let (ui, session) = shell(blank: true)
        _ = try XCTUnwrap(session.deck).addSlide()
        ui.pump()
        waitForCopy(ui)
        XCTAssertEqual(page.keeps, 1)
        // The page hiding asks every window to flush: nothing changed since the copy.
        OfficeScene.flushAll()
        XCTAssertEqual(page.keeps, 1, "an unchanged deck was copied again")
    }

    func testSavingDropsTheCopy() throws {
        let (ui, session) = shell(blank: true)
        _ = try XCTUnwrap(session.deck).addSlide()
        ui.pump()
        page.mine = ("pptx", "Presentation.pptx", Data())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("browser-slides-recovery-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        session.path = dir.appendingPathComponent("Saved.pptx").path
        session.onSave?(); ui.pump()
        XCTAssertFalse(session.dirty)
        XCTAssertNil(page.mine, "the saved deck's recovery copy is still kept")
    }
}
