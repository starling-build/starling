import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// S-TX-4 PR2: Insert > Link in Slides (e-mail, editing a link, the jumps PowerPoint lists) and following a link in the editor.
final class SlidesLinkDialogTests: XCTestCase {
    private var applied: [(String, String?, String, String)] = []

    private func dialog(_ edit: (inout HyperlinkHooks) -> Void) -> WidgetTester {
        applied = []
        var hooks = HyperlinkHooks(apply: { [unowned self] a, p, t, tip in applied.append((a, p, t, tip)); return "" })
        hooks.places = SlideLinks.relativePlaces + [HyperlinkPlace(id: "ppt/slides/slide2.xml", title: "Slide 2", kind: "Slide")]
        hooks.hasEmail = true
        edit(&hooks)
        return WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: HyperlinkDialog(hooks: hooks, onClose: {}), title: "T"),
                            size: Size(1280, 800))
    }

    func testMailAddressAndSubjectRoundTrip() {
        XCTAssertEqual(HyperlinkAddress.mail("team@example.com", subject: "Hi there é"), "mailto:team@example.com?subject=Hi%20there%20%C3%A9")
        XCTAssertEqual(HyperlinkAddress.mail(" a@b.c ", subject: ""), "mailto:a@b.c")
        XCTAssertEqual(HyperlinkAddress.mail("", subject: "x"), "")
        let m = HyperlinkAddress.splitMail("mailto:team@example.com?cc=x&subject=Hi%20there%20%C3%A9")
        XCTAssertEqual(m?.address, "team@example.com"); XCTAssertEqual(m?.subject, "Hi there é")
        XCTAssertNil(HyperlinkAddress.splitMail("https://example.com"))
    }

    func testEmailFieldsMakeAMailtoLink() {
        let ui = dialog { _ in }
        ui.tap(id: "link-mail"); ui.type("team@example.com")
        ui.tap(id: "link-subject"); ui.type("Hi there")
        ui.press(.enter); ui.pump()
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first?.0, "mailto:team@example.com?subject=Hi%20there")
        XCTAssertNil(applied.first?.1)
    }

    func testEditingAMailLinkStartsFromItsAddressAndSubject() {
        let ui = dialog { $0.address = "mailto:a@b.c?subject=Old%20one"; $0.canRemove = true }
        XCTAssertTrue(ui.has(text: "Edit Hyperlink"))
        ui.press(.enter); ui.pump()
        XCTAssertEqual(applied.first?.0, "mailto:a@b.c?subject=Old%20one", "OK unchanged keeps the same link")
    }

    func testEditingASlideLinkStartsWithItsSlidePicked() {
        let ui = dialog { $0.place = "ppt/slides/slide2.xml"; $0.canRemove = true }
        XCTAssertTrue(ui.has(text: "● Slide 2  (Slide)"))
        ui.press(.enter); ui.pump()
        XCTAssertEqual(applied.first?.1, "ppt/slides/slide2.xml")
    }

    func testShownNameOfASlide() {
        XCTAssertEqual(SlideLinks.shownName("Slide 3: Plans"), "Plans")
        XCTAssertEqual(SlideLinks.shownName("Slide 3"), "Slide 3")
    }

    func testPlaceOfALink() {
        XCTAssertEqual(SlideLinks.place(of: "slide:ppt/slides/slide4.xml"), "ppt/slides/slide4.xml")
        XCTAssertEqual(SlideLinks.place(of: "action:ppaction://hlinkshowjump?jump=lastslide"), "action:ppaction://hlinkshowjump?jump=lastslide")
        XCTAssertNil(SlideLinks.place(of: "https://example.com"))
        XCTAssertNil(SlideLinks.place(of: "action:ppaction://hlinkshowjump?jump=endshow"), "not a place the dialog lists")
    }

    func testFollowInTheEditorGoesToTheSlideOrOpensTheAddress() {
        let deck = DeckController()
        _ = deck.addSlide(); _ = deck.addSlide(); _ = deck.addSlide()
        deck.select(1)
        let fourth = deck.slideLinkTargets()[3].key
        var opened: [String] = []
        XCTAssertTrue(SlideLinks.follow("slide:" + fourth, in: deck, openURL: { opened.append($0) }))
        XCTAssertEqual(deck.current, 3)
        XCTAssertTrue(SlideLinks.follow("action:ppaction://hlinkshowjump?jump=firstslide", in: deck, openURL: { opened.append($0) }))
        XCTAssertEqual(deck.current, 0)
        XCTAssertTrue(SlideLinks.follow("action:ppaction://hlinkshowjump?jump=previousslide", in: deck, openURL: { opened.append($0) }))
        XCTAssertEqual(deck.current, 0, "stays on the first slide")
        XCTAssertTrue(SlideLinks.follow("action:ppaction://hlinkshowjump?jump=nextslide", in: deck, openURL: { opened.append($0) }))
        XCTAssertEqual(deck.current, 1)
        XCTAssertTrue(SlideLinks.follow("mailto:a@b.c", in: deck, openURL: { opened.append($0) }))
        XCTAssertEqual(opened, ["mailto:a@b.c"])
        XCTAssertFalse(SlideLinks.follow("slide:ppt/slides/gone.xml", in: deck, openURL: { opened.append($0) }))
        XCTAssertFalse(SlideLinks.follow("file:///bin/sh", in: deck, openURL: { opened.append($0) }))
        XCTAssertEqual(opened.count, 1)
    }

    /// The Mac script's click points: SCREEN_MARKS_DIR=dir writes slides-link.pptx (three slides, a "Link me" box on the
    /// first) and slides-link-marks-1440x932.txt (the box, then Insert > Link's dialog fields) there.
    func testInsertLinkMarks() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREEN_MARKS_DIR"] else { throw XCTSkip("no SCREEN_MARKS_DIR") }
        let deck = DeckController()
        _ = deck.addSlide(); _ = deck.addSlide()
        deck.select(0)
        let b = deck.addTextBox(at: Rect.fromLTWH(120, 160, 400, 60))
        b.text!.insertText("Link me")
        let path = dir + "/slides-link.pptx"
        try Pptx.write(deck).write(to: URL(fileURLWithPath: path))
        let size = Size(1440, 932)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"), size: size)
        ui.pump()
        var out = "--- opened\n"
        let box = ui.elements().first { ($0.widget as? RichEditable)?.controller.document.paragraphs.first?.text == "Link me" }?.findRenderObject() as? RenderBox
        let at = try XCTUnwrap(box).localToGlobal(Offset(30, 20))
        out += "box\tLink me\t\(Int(at.dx)) \(Int(at.dy))\n"
        ui.tap(at: at); ui.pump()
        out += ScreenMarks.lines(root: ui.elements().first, view: size).filter { $0.hasPrefix("text\tInsert\t") }.joined(separator: "\n") + "\n"
        XCTAssertTrue(ui.tap(text: "Insert")); ui.pump()
        out += ScreenMarks.lines(root: ui.elements().first, view: size).filter { $0.hasPrefix("text\tLink\t") }.joined(separator: "\n") + "\n"
        XCTAssertTrue(ui.tap(text: "Link")); ui.pump()
        XCTAssertTrue(ui.has(text: "Insert Hyperlink"))
        out += "--- dialog\n"
        for id in ["link-address", "link-mail", "link-subject", "link-text", "link-tip"] {
            if let c = ui.centre(id: id) { out += "field\t\(id)\t\(Int(c.dx)) \(Int(c.dy))\n" }
        }
        out += ScreenMarks.lines(root: ui.elements().first, view: size)
            .filter { $0.contains("Slide") || $0.hasPrefix("text\tOK") || $0.hasPrefix("text\tCancel") || $0.contains("Remove Link") }
            .joined(separator: "\n") + "\n"
        // Slide 2 picked and OK: the text is linked, and the dialog opened again is Edit Hyperlink with Slide 2 picked.
        XCTAssertTrue(ui.tap(text: "Slide 2  (Slide)")); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(text: "Insert Hyperlink"), ScreenMarks.lines(root: ui.elements().first, view: size).filter { $0.hasPrefix("text") }.suffix(12).joined(separator: "\n"))
        let shell = try XCTUnwrap(ui.state(SlidesShellState.self))
        XCTAssertEqual(shell.session.controller.document.paragraphs[0].text, "LinSlide 2k me", "a link at the caret's link shows the slide's name")
        XCTAssertTrue(ui.tap(text: "Link")); ui.pump()
        XCTAssertTrue(ui.has(text: "Edit Hyperlink"))
        XCTAssertTrue(ui.has(text: "● Slide 2  (Slide)"))
        XCTAssertTrue(ui.has(text: "Remove Link"))
        FileManager.default.createFile(atPath: dir + "/slides-link-marks-1440x932.txt", contents: Data(out.utf8))
    }
}
