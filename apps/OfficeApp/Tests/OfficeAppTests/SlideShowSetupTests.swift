// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlideShowSetupTests: XCTestCase {
    private func _deck() -> DeckController {
        let deck = SlidesSample.make()
        return deck
    }

    func testSettingsAndCustomShowsRoundTrip() throws {
        let deck = _deck()
        XCTAssertGreaterThanOrEqual(deck.slides.count, 3)
        let ids = deck.slides.map(\.id)
        deck.setCustomShows([CustomShow(id: 7, name: "Short <&> cut", slides: [ids[2], ids[0], ids[2]])])
        deck.setShow(ShowSettings(kind: .window, loop: true, range: .custom(7), useTimings: false, narration: true))
        let (state, theme, package) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(state.show.kind, .window)
        XCTAssertTrue(state.show.loop)
        XCTAssertFalse(state.show.useTimings)
        XCTAssertEqual(state.show.range, .custom(7))
        XCTAssertEqual(state.customShows.map(\.name), ["Short <&> cut"])
        let want = [state.slides[2].id, state.slides[0].id, state.slides[2].id]
        XCTAssertEqual(state.customShows[0].slides, want)

        // Written through the file it came from, with the first slide deleted:
        // the show keeps the slides that are left, in order.
        var next = state
        next.slides.remove(at: 0)
        let (again, _, _) = try Pptx.read(try PptxWriter.write(next, theme: theme, package: package))
        XCTAssertEqual(again.customShows[0].slides, [again.slides[1].id, again.slides[1].id])
        XCTAssertEqual(again.show.range, .custom(7))
    }

    /// A save keeps the file's show settings as it wrote them, PowerPoint's
    /// spelled-out defaults (showNarration="1") included, until they are changed here.
    func testPlainSaveKeepsTheShowSettingsAsWritten() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(_deck())))
        let pr = "<p:showPr showNarration=\"1\"><p:present/><p:sldAll/><p:penClr><a:prstClr val=\"red\"/></p:penClr></p:showPr>"
        var props = String(decoding: package.parts["ppt/presProps.xml"]!, as: UTF8.self)
        guard let r = props.range(of: "/>", options: .backwards) else { return XCTFail(props) }
        props.replaceSubrange(r, with: ">" + pr + "</p:presentationPr>")
        package.parts["ppt/presProps.xml"] = Data(props.utf8)
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        func saved(_ s: DeckState) throws -> String {
            let out = PptxPackage(try Zip.read(try PptxWriter.write(s, theme: theme, package: pkg)))
            return String(decoding: out.parts["ppt/presProps.xml"]!, as: UTF8.self)
        }
        let plain = try saved(state)
        XCTAssertTrue(plain.contains(pr), "kept as written: " + plain)
        var looped = state
        looped.show.loop = true
        let again = try saved(looped)
        XCTAssertTrue(again.contains("<p:showPr loop=\"1\"><p:present/><p:sldAll/><p:penClr>"), "changed, written fresh: " + again)
    }

    func testRangeKioskAndDefaults() throws {
        let deck = _deck()
        let plain = try Pptx.read(Pptx.write(deck)).0
        XCTAssertEqual(plain.show, ShowSettings())
        XCTAssertTrue(plain.customShows.isEmpty)
        deck.setShow(ShowSettings(kind: .kiosk, loop: true, range: .slides(from: 2, to: 3)))
        let state = try Pptx.read(Pptx.write(deck)).0
        XCTAssertEqual(state.show.kind, .kiosk)
        XCTAssertEqual(state.show.range, .slides(from: 2, to: 3))
        XCTAssertEqual(deck.showOrder(), [1, 2])
    }

    func testShowOrderSkipsHiddenAndFollowsCustomShow() {
        let deck = _deck()
        deck.toggleHidden(1)
        XCTAssertFalse(deck.showOrder().contains(1))
        XCTAssertEqual(deck.showOrder(), deck.slides.indices.filter { !deck.slides[$0].hidden })
        let ids = deck.slides.map(\.id)
        deck.setCustomShows([CustomShow(id: 1, name: "A", slides: [ids[2], ids[1]])])
        deck.setShow(ShowSettings(range: .custom(1)))
        XCTAssertEqual(deck.showOrder(), [2])  // PowerPoint skips a hidden slide inside a custom show too
        deck.toggleHidden(1)
        XCTAssertEqual(deck.showOrder(), [2, 1])
        deck.toggleHidden(1)
        deck.setCustomShows([CustomShow(id: 1, name: "A", slides: [ids[2], ids[1]])])
        deck.setCustomShows([])
        XCTAssertEqual(deck.show.range, .all)
    }

    private func _show(_ deck: DeckController, rehearse: Bool = false, ended: @escaping () -> Void = {}) throws -> (WidgetTester, SlideShowState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlideShowView(deck: deck, images: SlideTextCache(), start: deck.showOrder().first ?? 0,
                                                            rehearse: rehearse, onEnd: ended), title: "Test"),
                              size: Size(1600, 900))
        return (ui, try XCTUnwrap(ui.state(SlideShowState.self)))
    }

    func testLoopWrapsAndKioskIgnoresClicks() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        deck.setShow(ShowSettings(loop: true))
        var ended = false
        let (ui, state) = try _show(deck) { ended = true }
        XCTAssertEqual(state._at, 0)
        state._pressNext(); state._pressNext()
        XCTAssertEqual(state._at, 0, "past the last slide comes back to the first")
        XCTAssertFalse(ended)
        _ = ui
        deck.setShow(ShowSettings(kind: .kiosk))
        let (_, kiosk) = try _show(deck)
        kiosk._pressNext(click: true)
        XCTAssertEqual(kiosk._at, 0, "a kiosk does not advance on a click")
    }

    func testRehearseKeepsTimesOnYes() throws {
        let deck = DeckController()
        _ = deck.addSlide()
        var ended = false
        let (ui, state) = try _show(deck, rehearse: true) { ended = true }
        XCTAssertTrue(ui.has(text: "Pause"))
        ui.tap(text: "Next"); ui.pump()
        XCTAssertEqual(state._at, 1)
        ui.tap(text: "Next"); ui.pump()
        ui.tap(text: "Next"); ui.pump()
        XCTAssertTrue(ui.has(text: "Do you want to keep the new slide timings?"))
        XCTAssertEqual(Set(state._rehearsed.keys), [0, 1])
        ui.tap(text: "Yes"); ui.pump()
        XCTAssertTrue(ended)
        XCTAssertNotNil(deck.slides[0].transition.advanceAfter)
        XCTAssertNotNil(deck.slides[1].transition.advanceAfter)
        XCTAssertTrue(deck.show.useTimings)
    }

    func testRehearseNoLeavesTimingsAlone() throws {
        let deck = DeckController()
        let (ui, state) = try _show(deck, rehearse: true)
        state._pressNext(); state._pressNext()
        ui.tap(text: "No"); ui.pump()
        XCTAssertNil(deck.slides[0].transition.advanceAfter)
    }

    func testApplyRehearsalRoundTripsAsAdvanceTime() throws {
        let deck = _deck()
        deck.applyRehearsal([0: 2.46, 1: 0.01, 2: 7])
        let state = try Pptx.read(Pptx.write(deck)).0
        XCTAssertEqual(state.slides[0].transition.advanceAfter, 2.5)
        XCTAssertEqual(state.slides[1].transition.advanceAfter, 0.1)
        XCTAssertEqual(state.slides[2].transition.advanceAfter, 7)
        deck.undo()
        XCTAssertNil(deck.slides[0].transition.advanceAfter)
    }

    func testCustomShowsDialogMakesAShowInChosenOrder() throws {
        var got: [CustomShow]? = nil
        let dialog = CustomShowsDialog(shows: [], slides: [(id: 10, title: "Alpha"), (id: 20, title: "Beta")],
                                       onClose: { got = $0 }, onPlay: { _, _ in })
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: dialog, title: "Test"), size: Size(1200, 800))
        ui.tap(text: "New..."); ui.pump()
        XCTAssertTrue(ui.has(text: "Define Custom Show"))
        ui.tap(text: "2. Beta"); ui.tap(text: "1. Alpha"); ui.pump()
        ui.tap(text: "Move Up"); ui.pump()
        ui.tap(text: "OK"); ui.pump()
        ui.tap(text: "Close"); ui.pump()
        XCTAssertEqual(got?.count, 1)
        XCTAssertEqual(got?.first?.slides.sorted(), [10, 20])
    }

    func testSetUpDialogReportsChoices() throws {
        var got: ShowSettings? = nil
        let dialog = SetUpShowDialog(initial: ShowSettings(), slideCount: 5,
                                     shows: [CustomShow(id: 3, name: "Board", slides: [1])],
                                     onOK: { got = $0 }, onCancel: {})
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: dialog, title: "Test"), size: Size(1200, 900))
        ui.tap(text: "Browsed at a kiosk (full screen)"); ui.pump()
        ui.tap(text: "Board"); ui.pump()
        ui.tap(text: "Manually"); ui.pump()
        ui.tap(text: "OK"); ui.pump()
        XCTAssertEqual(got?.kind, .kiosk)
        XCTAssertEqual(got?.range, .custom(3))
        XCTAssertEqual(got?.useTimings, false)
        XCTAssertEqual(got?.loop, true)
    }

    /// For the PowerPoint check: STARLING_SHOW_OUT gets the settings deck, with ".rehearsed.pptx" beside it.
    func testSaveShowDecks() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_SHOW_OUT"] else { throw XCTSkip("no output path") }
        let path = "/data/corpus-cache/test/corpus/pptx/decks/layouts.pptx"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw XCTSkip("no corpus cache") }
        let (state, theme, pkg) = try Pptx.read(data)
        let deck = DeckController()
        deck.load(state, theme: theme, package: pkg)
        let ids = deck.slides.map(\.id)
        deck.setCustomShows([CustomShow(id: 5, name: "Board", slides: [ids[3], ids[1], ids[2]]),
                             CustomShow(id: 6, name: "Short", slides: [ids[0], ids[4]])])
        deck.setShow(ShowSettings(kind: .kiosk, loop: true, range: .custom(5), useTimings: false, narration: true))
        deck.toggleHidden(2)
        try Pptx.write(deck).write(to: URL(fileURLWithPath: out))
        try """
        Set Up Slide Show should show: type = Browsed at a kiosk, loop until Esc ticked (greyed), advance = Manually, show slides = Custom show "Board".
        Slide Show > Custom Slide Show should list: Board, Short.
        Board = slide 4, slide 2, slide 3 (in that order). Short = slide 1, slide 5.
        Slide 3 is hidden (Hide Slide is on) .
        """.write(toFile: out + ".txt", atomically: true, encoding: .utf8)

        let d2 = DeckController()
        d2.load(state, theme: theme, package: pkg)
        d2.applyRehearsal([0: 4.2, 1: 10, 2: 0.04])
        let r = out.replacingAll(".pptx", with: ".rehearsed.pptx")
        try Pptx.write(d2).write(to: URL(fileURLWithPath: r))
        try """
        Transitions tab: "After" ticked with 00:04.20 on slide 1, 00:10.00 on slide 2, 00:00.10 on slide 3.
        Set Up Slide Show: advance = Using timings, if present.
        """.write(toFile: r + ".txt", atomically: true, encoding: .utf8)
    }
}
