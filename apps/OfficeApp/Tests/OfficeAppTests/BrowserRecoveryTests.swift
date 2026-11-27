// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// Web parity 2: AutoSave's recovery copy in a browser tab, which has no files. The page keeps one row per tab
/// (IndexedDB); here an in-memory stand-in plays the page. An edit is copied after the AutoSave pause, a copy left
/// by a closed tab is restored on start, and a save or "Don't Save" drops it.
final class BrowserRecoveryTests: XCTestCase {
    /// The stand-in page: this tab's row, and rows other (closed) tabs left behind.
    private final class Page {
        var mine: (kind: String, name: String, data: Data)?
        var orphans: [(kind: String, name: String, data: Data)] = []
        var discards = 0
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
            discard: { page.mine = nil; page.discards += 1 },
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
                                        home: OfficeShell(initialPath: nil, startBlank: blank), title: "Test"),
                              size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!.session)
    }

    private func text(_ data: Data) -> String {
        guard let opened = try? OfficeFormats.read(data, named: "x.docx") else { return "" }
        return opened.document.paragraphs.map(\.text).joined(separator: "\n")
    }

    func testAnEditIsCopiedAfterThePause() {
        let (ui, _) = shell(blank: true)
        ui.type("Kept by the tab")
        ui.pump()
        let deadline = Date().addingTimeInterval(4)
        while page.mine == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05)); ui.pump()
        }
        guard let row = page.mine else { return XCTFail("no recovery copy reached the page") }
        XCTAssertEqual(row.kind, "docx")
        XCTAssertTrue(row.name.hasSuffix(".docx"), row.name)
        XCTAssertTrue(text(row.data).contains("Kept by the tab"), text(row.data))
    }

    /// The tab going out of sight (or closing) writes the copy at once, before the pause is over, and a second
    /// hide with no edit since does not write it again (a tab switch must not rewrite the copy each time).
    func testHidingThePageCopiesAtOnceAndOnlyOnce() {
        let (ui, _) = shell(blank: true)
        ui.type("Kept on close")
        ui.pump()
        XCTAssertNil(page.mine, "the copy was written before the pause")
        OfficeScene.flushAll()
        guard let row = page.mine else { return XCTFail("hiding the page wrote no copy") }
        XCTAssertTrue(text(row.data).contains("Kept on close"), text(row.data))
        XCTAssertEqual(page.keeps, 1)
        OfficeScene.flushAll()
        XCTAssertEqual(page.keeps, 1, "a hide with no edit since wrote the copy again")
        RunLoop.main.run(until: Date().addingTimeInterval(2.5)); ui.pump()
        XCTAssertEqual(page.keeps, 1, "the pause wrote a copy the page already had")
        ui.type("!")
        ui.pump()
        OfficeScene.flushAll()
        XCTAssertEqual(page.keeps, 2, "an edit after the copy was not written on the next hide")
    }

    func testACopyLeftByAClosedTabIsRestored() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "Left behind")])
        let bytes = try DocxFormat.write(doc, pageSetup: .letter)
        page.orphans = [("pptx", "Deck.pptx", Data("not a deck".utf8)), ("docx", "Report.docx", bytes)]
        let (ui, session) = shell(blank: false)
        ui.pump()
        let state = ui.state(OfficeShellState.self)!
        XCTAssertTrue(state.session.controller.document.paragraphs.contains { $0.text == "Left behind" })
        XCTAssertEqual(session.path, "Report.docx")
        XCTAssertTrue(session.dirty, "a restored document is unsaved")
        XCTAssertEqual(page.orphans.count, 1, "Word took only the Word copy")
        XCTAssertEqual(page.mine?.name, "Report.docx", "the restored copy is now this tab's")
    }

    func testSavingDropsTheCopy() throws {
        let (ui, session) = shell(blank: true)
        ui.type("Saved for real")
        ui.pump()
        page.mine = ("docx", "Document.docx", Data())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("browser-recovery-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        session.path = dir.appendingPathComponent("Saved.docx").path
        session.onSave?(); ui.pump()
        XCTAssertFalse(session.dirty)
        XCTAssertNil(page.mine, "the saved document's recovery copy is still kept")
    }

    func testDontSaveDropsTheCopy() {
        let (_, session) = shell(blank: true)
        page.mine = ("docx", "Document.docx", Data())
        session.discardRecoveryCopy()
        XCTAssertNil(page.mine)
    }
}
