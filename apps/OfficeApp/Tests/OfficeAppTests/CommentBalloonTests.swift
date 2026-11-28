// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-RV-1: comments stand in balloons right of the page, as Word's markup area; a click on one opens its card, where
/// the comment is edited in place, answered, resolved or deleted; Show Comments hides them.
final class CommentBalloonTests: XCTestCase {
    private var savedReviewer: (() -> (author: String, date: String))!
    override func setUp() {
        savedReviewer = RichDocumentController.reviewer
        RichDocumentController.reviewer = { ("Ada Lovelace", "2026-11-28T10:00:00Z") }
    }
    override func tearDown() { RichDocumentController.reviewer = savedReviewer }

    private func shell() -> (WidgetTester, OfficeShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "t"),
                              size: Size(1440, 932))
        let state = ui.state(OfficeShellState.self)!
        let c = state.session.controller
        c.insertText("Hello brave new world"); ui.pump()
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 11), extend: true)
        c.addComment("Why brave?")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        ui.pump(); ui.pump()
        return (ui, state)
    }

    private func balloons(_ ui: WidgetTester) -> [(id: String, rect: Rect)] {
        ui.state(RichEditableState.self)?.commentBalloonsForTesting ?? []
    }

    func testABalloonStandsRightOfThePageLevelWithItsText() {
        let (ui, _) = shell()
        let b = balloons(ui)
        XCTAssertEqual(b.map(\.id), ["0"])
        guard let r = b.first?.rect else { return }
        // Right of the centre of the window: the page has moved left to make room.
        XCTAssertGreaterThan(r.left, 720)
        XCTAssertLessThan(r.right, 1440)
    }

    func testTheCardEditsTheTextRepliesAndResolves() {
        let (ui, state) = shell()
        let c = state.session.controller
        guard let r = balloons(ui).first?.rect else { return XCTFail("no balloon") }
        ui.tap(at: Offset(r.left + r.width / 2, r.top + 6)); ui.pump(); ui.pump()
        XCTAssertEqual(state._cardOpen, "0")
        // The comment's text box has the keys: typing goes on the comment, never the page.
        ui.type(" Really?")
        XCTAssertTrue(ui.tap(id: "comment-reply")); ui.pump()
        ui.type("Because.")
        XCTAssertTrue(ui.tap(id: "comment-post")); ui.pump()
        XCTAssertNil(state._cardOpen)
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello brave new world")
        let t = c.commentThread("0")
        XCTAssertEqual(t?.comment.text, "Why brave? Really?")
        XCTAssertEqual(t?.replies.map(\.text), ["Because."])
        // Resolve from the card; Reopen undoes it.
        ui.pump()
        guard let r2 = balloons(ui).first?.rect else { return XCTFail("no balloon") }
        ui.tap(at: Offset(r2.left + r2.width / 2, r2.top + 6)); ui.pump(); ui.pump()
        XCTAssertTrue(ui.tap(id: "comment-resolve")); ui.pump()
        XCTAssertEqual(c.commentThread("0")?.comment.done, true)
        // Escape keeps what was typed and closes the card.
        guard let r3 = balloons(ui).first?.rect else { return XCTFail("no balloon") }
        ui.tap(at: Offset(r3.left + r3.width / 2, r3.top + 6)); ui.pump(); ui.pump()
        ui.type("!")
        ui.press(.escape); ui.pump()
        XCTAssertNil(state._cardOpen)
        XCTAssertEqual(c.commentThread("0")?.comment.text, "Why brave? Really?!")
    }

    func testDeleteFromTheCardTakesTheThread() {
        let (ui, state) = shell()
        guard let r = balloons(ui).first?.rect else { return XCTFail("no balloon") }
        ui.tap(at: Offset(r.left + r.width / 2, r.top + 6)); ui.pump(); ui.pump()
        XCTAssertTrue(ui.tap(id: "comment-delete")); ui.pump(); ui.pump()
        XCTAssertEqual(state.session.controller.comments(), [])
        XCTAssertEqual(balloons(ui).count, 0)
        XCTAssertEqual(state._status, "Comment deleted")      // (never the deleted comment's text: job 71)
    }

    /// The card is white paper in every app theme, so its labels and text boxes take a light theme: in the dark app theme
    /// they were pale lavender (about 1.1:1) and the boxes dark grey (job 71).
    func testTheCardReadsDarkOnWhiteInTheDarkAppTheme() {
        let white = Color(0xFFFFFFFF)
        for app in [OfficeAppearance.theme(.dark), OfficeAppearance.theme(.light)] {
            let card = OfficeShellState.commentCardTheme(app)
            XCTAssertEqual(card.brightness, .light)
            XCTAssertGreaterThanOrEqual(ContrastAuditTests.ratio(card.resources.textFillColorPrimary, white), 4.5)
            let box = Color.alphaBlend(foreground: card.resources.controlFillColorDefault, background: white)
            XCTAssertGreaterThan(box.computeLuminance(), 0.8, "the text box fill is light on the white card")
            XCTAssertGreaterThanOrEqual(ContrastAuditTests.ratio(card.resources.textFillColorPrimary, box), 4.5)
        }
    }

    func testShowCommentsHidesTheBalloonsAndOnlyAllMarkupShowsThem() {
        let (ui, state) = shell()
        XCTAssertEqual(balloons(ui).count, 1)
        state.session.onShowComments?(); ui.pump(); ui.pump()
        XCTAssertEqual(balloons(ui).count, 0)
        state.session.onShowComments?(); ui.pump(); ui.pump()
        XCTAssertEqual(balloons(ui).count, 1)
        state.session.onMarkup?(.simple); ui.pump(); ui.pump()
        XCTAssertEqual(balloons(ui).count, 0)
    }
}
