// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// Web parity 3: Recent files in a browser tab, which has no paths. The page keeps each document opened or saved
/// (its name and a copy of its bytes); here an in-memory stand-in plays the page. Backstage Home lists the kept
/// names, a click reopens the copy, and the reopened document moves to the top.
final class BrowserRecentTests: XCTestCase {
    private final class Page {
        var rows: [(name: String, data: Data)] = []
        var asked: [String] = []
    }
    private var page = Page()
    private var saved: OfficeHost.BrowserRecent?

    override func setUp() {
        saved = OfficeHost.browserRecent
        page = Page()
        let page = self.page
        OfficeHost.browserRecent = .init(
            names: { page.rows.map(\.name) },
            remember: { name, data in
                page.rows.removeAll { $0.name == name }
                page.rows.insert((name, data), at: 0)
            },
            open: { name, done in
                page.asked.append(name)
                done(page.rows.first { $0.name == name }?.data)
            })
    }

    override func tearDown() { OfficeHost.browserRecent = saved }

    private func docx(_ text: String) throws -> Data {
        try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: text)]), pageSetup: .letter)
    }

    private func home() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, startBlank: true, startHome: true),
                                        title: "Test"),
                              size: Size(1280, 800))
        ui.pump()
        return (ui, ui.state(OfficeShellState.self)!.session)
    }

    func testHomeListsTheKeptDocuments() throws {
        page.rows = [("Minutes.docx", try docx("a")), ("Budget.docx", try docx("b"))]
        let (ui, _) = home()
        let texts = ui.texts()
        XCTAssertTrue(texts.contains("Minutes.docx"), "Recent does not list the page's documents")
        XCTAssertTrue(texts.contains("Budget.docx"))
        XCTAssertFalse(texts.contains("Documents you open or save show up here."))
    }

    func testARecentDocumentReopensFromItsCopy() throws {
        page.rows = [("Minutes.docx", try docx("Kept minutes")), ("Budget.docx", try docx("Kept budget"))]
        let (ui, session) = home()
        XCTAssertTrue(ui.tap(text: "Budget.docx"))
        ui.pump()
        XCTAssertEqual(page.asked, ["Budget.docx"])
        XCTAssertTrue(session.controller.document.paragraphs.contains { $0.text == "Kept budget" })
        XCTAssertEqual(session.path, "Budget.docx")
        XCTAssertFalse(session.dirty, "a reopened copy is as saved")
        XCTAssertEqual(page.rows.map(\.name), ["Budget.docx", "Minutes.docx"], "the reopened document moves to the top")
    }

    func testAGoneCopySaysSo() throws {
        page.rows = [("Minutes.docx", try docx("a"))]
        let (ui, session) = home()
        page.rows = []
        XCTAssertTrue(ui.tap(text: "Minutes.docx"))
        ui.pump()
        XCTAssertNil(session.path)
        XCTAssertTrue(ui.texts().contains { $0.hasPrefix("Minutes.docx is no longer kept") }, "\(ui.texts())")
    }
}
