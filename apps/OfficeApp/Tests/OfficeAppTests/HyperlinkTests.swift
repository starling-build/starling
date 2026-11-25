// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// U-LINK-1: the shared Insert Hyperlink dialog and the Writer model behind it.
final class HyperlinkTests: XCTestCase {
    private func controller() -> RichDocumentController {
        var h = RichParagraph(text: "Intro"); h.style.heading = 1
        let body = RichParagraph(text: "see here please")
        return RichDocumentController(document: RichDocument(paragraphs: [h, body]))
    }

    private func select(_ c: RichDocumentController, _ a: Int, _ b: Int, para: Int = 1) {
        c.selection = RichSelection(anchor: RichPosition(paragraph: para, offset: a), focus: RichPosition(paragraph: para, offset: b))
    }

    func testOneUndoRemovesTheWholeLink() {
        let c = controller(); select(c, 4, 8)
        XCTAssertTrue(c.applyHyperlink(address: "https://a.example", text: "there", tip: "Tip"))
        XCTAssertEqual(c.document.paragraphs[1].text, "see there please")
        XCTAssertEqual(c.document.paragraphs[1].runs.first { $0.style.link != nil }?.style.linkTip, "Tip")
        c.undo()
        XCTAssertEqual(c.document.paragraphs[1].text, "see here please")
        XCTAssertNil(c.document.paragraphs[1].runs.first { $0.style.link != nil })
    }

    func testHeadingTargetMakesABookmarkAndLinksToIt() {
        let c = controller(); select(c, 0, 3)
        let t = c.linkTargets().first { $0.kind == .heading }!
        XCTAssertTrue(c.applyHyperlink(address: "", target: t))
        XCTAssertEqual(c.document.paragraphs[0].bookmarks, ["_Heading0"])
        XCTAssertEqual(c.document.paragraphs[1].runs.first { $0.style.link != nil }?.style.link, "#_Heading0")
        c.undo()
        XCTAssertTrue(c.document.paragraphs[0].bookmarks.isEmpty)
    }

    func testCaretInsertsTheText() {
        let c = controller(); select(c, 3, 3)
        XCTAssertTrue(c.applyHyperlink(address: "https://a.example", text: "LINK"))
        XCTAssertTrue(c.document.paragraphs[1].text.containsSubstring("LINK"))
    }

    func testNothingToLinkToIsRefused() {
        XCTAssertFalse(controller().applyHyperlink(address: ""))
    }

    func testDocxKeepsTheScreenTipAndTheAnchor() throws {
        let c = controller(); select(c, 0, 3)
        c.applyHyperlink(address: "https://a.example", tip: "Tip here")
        select(c, 4, 8)
        let t = c.linkTargets().first { $0.kind == .heading }!
        c.applyHyperlink(address: "", target: t)
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        let back = try DocxFormat.read(data).document
        let links = back.paragraphs[1].runs.compactMap { $0.style.link }
        XCTAssertTrue(links.contains("https://a.example"))
        XCTAssertTrue(links.contains("#_Heading0"))
        XCTAssertEqual(back.paragraphs[1].runs.first { $0.style.link == "https://a.example" }?.style.linkTip, "Tip here")
    }

    func testAddressesAreNormalised() {
        XCTAssertEqual(HyperlinkAddress.normalize("example.com"), "https://example.com")
        XCTAssertEqual(HyperlinkAddress.normalize("a@b.com"), "mailto:a@b.com")
        XCTAssertEqual(HyperlinkAddress.normalize("#mark"), "#mark")
    }

    private var applied: [(String, String?, String, String)] = []
    private var removed = 0, closed = 0
    private func dialog(canRemove: Bool = false) -> WidgetTester {
        applied = []; removed = 0; closed = 0
        var hooks = HyperlinkHooks(apply: { [unowned self] a, p, t, tip in
            applied.append((a, p, t, tip)); return "" })
        hooks.places = [HyperlinkPlace(id: "h1", title: "Intro", kind: "Heading")]
        hooks.canRemove = canRemove
        hooks.remove = { [unowned self] in removed += 1 }
        return WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: HyperlinkDialog(
            hooks: hooks, onClose: { [unowned self] in closed += 1 }), title: "T"), size: Size(1280, 800))
    }

    func testOKWithNothingShowsAMessageAndStaysOpen() {
        let ui = dialog()
        ui.press(.enter); ui.pump()
        XCTAssertTrue(applied.isEmpty); XCTAssertEqual(closed, 0)
        XCTAssertTrue(ui.has(text: "Type an address or pick a place"))
    }

    func testTypedAddressIsNormalisedAndApplied() {
        let ui = dialog()
        ui.tap(id: "link-address"); ui.type("example.com")
        ui.tap(id: "link-tip"); ui.type("Go")
        ui.press(.enter); ui.pump()
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.0, "https://example.com")
        XCTAssertEqual(applied.first?.3, "Go")
        XCTAssertEqual(closed, 1)
    }

    func testPickingAPlaceAppliesIt() {
        let ui = dialog()
        ui.tap(id: "link-place-h1")
        ui.press(.enter); ui.pump()
        XCTAssertEqual(applied.first?.0, "")
        XCTAssertEqual(applied.first?.1, "h1")
    }

    func testRemoveLinkCallsTheHook() {
        let ui = dialog(canRemove: true)
        ui.tap(text: "Remove Link")
        XCTAssertEqual(removed, 1)
    }

    func testEscapeClosesWithoutApplying() {
        let ui = dialog()
        ui.press(.escape); ui.pump()
        XCTAssertTrue(applied.isEmpty); XCTAssertEqual(closed, 1)
    }
}
