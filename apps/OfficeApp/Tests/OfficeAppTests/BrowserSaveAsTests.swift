// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// Web parity 4: Save and Save As in a browser tab. Where the browser has file pickers (Chrome, Edge) Save As asks
/// it for a place and keeps the file's handle, and Save writes back through it, also to a file opened through the
/// picker. Elsewhere Save downloads, and Save As is our own name-and-format box, then a download. An in-memory
/// stand-in plays the page.
final class BrowserSaveAsTests: XCTestCase {
    private final class Page {
        var canPick = true
        var place: (handle: Int, name: String)? = (7, "Mine.docx")
        var opened: OfficeHost.BrowserFiles.Picked?
        var writeOK = true
        var picks: [(suggested: String, extensions: [String])] = []
        var writes: [(handle: Int, data: Data)] = []
        var downloads: [(name: String, data: Data)] = []
    }
    private var page = Page()
    private var saved: OfficeHost.BrowserFiles?

    override func setUp() {
        saved = OfficeHost.browserFiles
        page = Page()
        let page = self.page
        OfficeHost.browserFiles = .init(
            canPickPlace: true,
            open: { _, done in if let picked = page.opened { done(picked) } },
            pickPlace: { suggested, extensions, done in
                page.picks.append((suggested, extensions)); done(page.place)
            },
            write: { handle, data, done in
                if page.writeOK { page.writes.append((handle, data)) }
                done(page.writeOK)
            },
            download: { name, data in page.downloads.append((name, data)) })
    }

    override func tearDown() { OfficeHost.browserFiles = saved }

    private func shell(canPick: Bool = true) -> (WidgetTester, OfficeSession) {
        OfficeHost.browserFiles?.canPickPlace = canPick
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"),
                              size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!.session)
    }

    private func text(_ data: Data, _ name: String = "x.docx") -> String {
        guard let opened = try? OfficeFormats.read(data, named: name) else { return "" }
        return opened.document.paragraphs.map(\.text).joined(separator: "\n")
    }

    func testSaveAsAsksTheBrowserForAPlaceAndSaveWritesThere() {
        let (ui, session) = shell()
        ui.type("First draft")
        ui.pump()
        session.onSaveAs?(); ui.pump()
        XCTAssertEqual(page.picks.count, 1, "Save As did not ask the browser for a place")
        XCTAssertEqual(page.picks.first?.extensions.first, "docx", "the document's own format comes first")
        XCTAssertEqual(page.writes.map(\.handle), [7])
        XCTAssertTrue(text(page.writes[0].data).contains("First draft"))
        XCTAssertEqual(session.path, "Mine.docx")
        XCTAssertFalse(session.dirty)
        XCTAssertTrue(page.downloads.isEmpty, "a picked place is written, not downloaded")

        ui.type(" and more")
        ui.pump()
        session.onSave?(); ui.pump()
        XCTAssertEqual(page.picks.count, 1, "Save asked again for a place it already has")
        XCTAssertEqual(page.writes.map(\.handle), [7, 7])
        XCTAssertTrue(text(page.writes[1].data).contains("and more"))
        XCTAssertFalse(session.dirty)
    }

    func testAFileOpenedThroughThePickerSavesBackToItself() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "From disk")])
        page.opened = ("Opened.docx", try DocxFormat.write(doc, pageSetup: .letter), 5)
        let (ui, session) = shell()
        session.onOpen?(); ui.pump()
        XCTAssertEqual(session.path, "Opened.docx")
        ui.type("Edited ")
        ui.pump()
        XCTAssertTrue(session.dirty)
        session.onSave?(); ui.pump()
        XCTAssertTrue(page.picks.isEmpty, "Save asked for a place for a file that has one")
        XCTAssertEqual(page.writes.map(\.handle), [5])
        XCTAssertTrue(text(page.writes[0].data).contains("From disk"))
        XCTAssertFalse(session.dirty)
    }

    func testAFailedWriteLeavesTheDocumentUnsaved() {
        page.writeOK = false
        let (ui, session) = shell()
        ui.type("Not yet")
        ui.pump()
        session.onSaveAs?(); ui.pump()
        XCTAssertTrue(session.dirty, "a write the browser refused counts as saved")
        XCTAssertNil(session.path)
    }

    func testACancelledPickerSavesNothing() {
        page.place = nil
        let (ui, session) = shell()
        ui.type("Kept open")
        ui.pump()
        session.onSave?(); ui.pump()
        XCTAssertEqual(page.picks.count, 1)
        XCTAssertTrue(page.writes.isEmpty && page.downloads.isEmpty)
        XCTAssertTrue(session.dirty)
    }

    func testWithoutPickersSaveDownloads() {
        let (ui, session) = shell(canPick: false)
        ui.type("Downloaded")
        ui.pump()
        session.onSave?(); ui.pump()
        XCTAssertTrue(page.picks.isEmpty)
        XCTAssertEqual(page.downloads.count, 1)
        XCTAssertTrue(page.downloads.first?.name.hasSuffix(".docx") ?? false, page.downloads.first?.name ?? "")
        XCTAssertTrue(text(page.downloads[0].data).contains("Downloaded"))
        XCTAssertFalse(session.dirty)
    }

    /// A save through the browser, by its picker or by a download, puts the document on the tab's Recent list
    /// (web-parity item 3), as the download-only save did before Save As.
    func testABrowserSaveGoesOnRecent() {
        let kept = OfficeHost.browserRecent
        defer { OfficeHost.browserRecent = kept }
        var remembered: [String] = []
        OfficeHost.browserRecent = .init(names: { remembered }, remember: { name, _ in remembered.insert(name, at: 0) },
                                         open: { _, done in done(nil) })
        let (ui, session) = shell()
        ui.type("Remembered")
        ui.pump()
        session.onSave?(); ui.pump()
        XCTAssertEqual(remembered.first, "Mine.docx", "a save through the picker is not on Recent")
        let (ui2, session2) = shell(canPick: false)
        ui2.type("Downloaded")
        ui2.pump()
        session2.onSave?(); ui2.pump()
        XCTAssertEqual(remembered.count, 2, "a download save is not on Recent: \(remembered)")
    }

    func testWithoutPickersSaveAsIsANameAndFormatBox() {
        let (ui, session) = shell(canPick: false)
        ui.type("Plain words")
        ui.pump()
        session.onSaveAs?(); ui.pump()
        XCTAssertTrue(ui.has(text: "Download"), "no name-and-format box: \(ui.texts().prefix(40))")
        XCTAssertTrue(ui.tap(text: "Plain Text (.txt)")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Download")); ui.pump()
        XCTAssertEqual(page.downloads.count, 1)
        XCTAssertEqual(page.downloads.first?.name.pathExtension, "txt")
        XCTAssertEqual(String(decoding: page.downloads.first?.data ?? Data(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines), "Plain words")
        XCTAssertFalse(session.dirty)
    }
}
