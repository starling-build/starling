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

    func testHeadingBookmarkWrapsTheHeadingText() throws {
        let c = controller(); select(c, 0, 3)
        let t = c.linkTargets().first { $0.kind == .heading }!
        c.applyHyperlink(address: "", target: t)
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        let back = try DocxFormat.read(data).document
        let marks = back.paragraphs[0].bookmarkMarkers
        XCTAssertEqual(marks.count, 2, "a start and an end, not an empty point")
        XCTAssertEqual(marks.first?.name, "_Heading0")
        XCTAssertEqual(marks.first?.offset, 0)
        XCTAssertEqual(marks.last?.offset, back.paragraphs[0].length)
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

    /// W-LK-1: Word's E-mail Address pane (address and subject) and editing a link to a place in the document.
    func testEmailWithSubjectSavesAsWordWritesIt() throws {
        let c = controller(); select(c, 4, 8)
        // (Word writes ü and ß as typed and a space as %20; "&" is %26, as Word's own raw "&" cuts its subject short.)
        let mail = HyperlinkAddress.mail("a@b.com", subject: "Grüße & more 100%", word: true)
        XCTAssertEqual(mail, "mailto:a@b.com?subject=Grüße%20%26%20more%20100%25")
        XCTAssertTrue(c.applyHyperlink(address: mail))
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        let rels = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "word/_rels/document.xml.rels" }).data, as: UTF8.self)
        XCTAssertTrue(rels.containsSubstring("Target=\"mailto:a@b.com?subject=Grüße%20%26%20more%20100%25\" TargetMode=\"External\""), rels)
        let back = try DocxFormat.read(data).document
        let link = try XCTUnwrap(back.paragraphs[1].runs.compactMap { $0.style.link }.first)
        XCTAssertEqual(link, mail)
        let split = try XCTUnwrap(HyperlinkAddress.splitMail(link))
        XCTAssertEqual(split.address, "a@b.com"); XCTAssertEqual(split.subject, "Grüße & more 100%")
    }

    func testEditingALinkToAHeadingFindsTheHeading() {
        let c = controller(); select(c, 4, 8)
        let t = c.linkTargets().first { $0.kind == .heading }!
        c.applyHyperlink(address: "", target: t)
        let link = try! XCTUnwrap(c.currentLink)
        let targets = c.linkTargets()
        let i = RichDocumentController.linkTargetIndex(of: link, in: targets)
        XCTAssertEqual(i.map { targets[$0].paragraph }, 0)
        XCTAssertNil(RichDocumentController.linkTargetIndex(of: "https://a.example", in: targets))
        XCTAssertNil(RichDocumentController.linkTargetIndex(of: "#missing", in: targets))
    }

    /// The Word lab (LKMAIL_OUT=<folder>): an e-mail link with a subject and a link to a heading, saved by us.
    func testWriteLabFile() throws {
        guard let out = ProcessInfo.processInfo.environment["LKMAIL_OUT"] else { return }
        let c = controller(); select(c, 0, 3)
        c.applyHyperlink(address: HyperlinkAddress.mail("a@b.com", subject: "Grüße & more", word: true), tip: "Mail tip")
        select(c, 4, 8)
        c.applyHyperlink(address: "", target: c.linkTargets().first { $0.kind == .heading }!)
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out + "/lkmail.docx"))
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
