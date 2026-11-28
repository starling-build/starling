import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// S-ED-1 step 3: Slides' Paste Options button (the last paste made again another way, in one undo step) and
/// Paste Special (Ctrl+Alt+V: one clipboard format pasted on its own).
final class SlidePasteOptionsTests: XCTestCase {
    private func shell() -> (WidgetTester, SlidesShellState, DeckController) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "T"),
                              size: Size(1440, 932))
        let state = ui.state(SlidesShellState.self)!
        return (ui, state, state.session.deck!)
    }

    private func drain(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)); ui.pump() }
    }

    private func clipboard() throws -> ClipboardData {
        var got: ClipboardData?
        Clipboard.getData(Clipboard.kAll) { got = $0 }
        return try XCTUnwrap(got)
    }

    private func isPicture(_ shape: SlideShape?) -> Bool {
        if case .picture = shape?.kind { return true }
        return false
    }

    private func key(_ logical: Int64, _ type: KeyEventType) {
        _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: type, physical: 0, logical: logical,
                                                          character: nil, synthesized: false))
    }

    /// A shape copy pasted back, then redone as a picture and as text only: each time the paste is replaced, and
    /// one Undo takes it all out. The picture is saved and read back as a picture.
    func testRepasteReplacesThePasteAndUndoesInOneStep() throws {
        let (ui, _, deck) = shell()
        let n = deck.currentSlide.shapes.count
        deck.addTextBox(text: "Hello")
        XCTAssertTrue(deck.copyShapes())
        let data = try clipboard()
        deck.selectShapes([]); ui.pump()
        XCTAssertTrue(deck.pasteOnSlide(data))
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2)
        XCTAssertEqual(deck.slidePasteOptions, .keepSource)
        XCTAssertTrue(deck.canRepaste(.picture))
        XCTAssertTrue(deck.canRepaste(.textOnly))

        deck.repaste(.picture)
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2, "the picture replaces the pasted shape")
        XCTAssertTrue(isPicture(deck.selection.first))
        XCTAssertEqual(deck.slidePasteOptions, .picture)
        let (saved, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(saved.slides[deck.current].shapes.filter { if case .picture = $0.kind { return true } else { return false } }.count, 1)

        deck.repaste(.textOnly)
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2)
        XCTAssertEqual(deck.selection.first?.text?.document.plainText(), "Hello")
        XCTAssertFalse(isPicture(deck.selection.first))

        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1, "one Undo takes the paste out, however often it was redone")
        XCTAssertNil(deck.slidePasteOptions)
    }

    /// Shapes come back as shapes only into the deck that copied them; a picture and text from elsewhere offer
    /// only their own ways.
    func testWaysFollowTheClipboard() {
        let (_, _, deck) = shell()
        let text = ClipboardData(text: "one\ntwo")
        XCTAssertFalse(deck.canPaste(text, way: .keepSource))
        XCTAssertFalse(deck.canPaste(text, way: .picture))
        XCTAssertTrue(deck.canPaste(text, way: .textOnly))
        XCTAssertTrue(deck.paste(text, way: .textOnly))
        XCTAssertEqual(deck.selection.first?.text?.document.paragraphs.count, 2, "one paragraph a line")
        let foreign = ClipboardData(text: "x", custom: [DeckController.shapesMime: Data("slides:other:1".utf8)])
        XCTAssertFalse(deck.canPaste(foreign, way: .keepSource))
    }

    /// The button shows by the paste; its menu redoes it, by click or by the letter. Any other edit retires it.
    func testButtonAndMenuLetters() throws {
        let (ui, _, deck) = shell()
        deck.addTextBox(text: "Hello")
        XCTAssertTrue(deck.copyShapes())
        let data = try clipboard()
        deck.selectShapes([]); ui.pump()
        XCTAssertFalse(ui.has(tip: "Paste Options"))
        deck.pasteOnSlide(data); ui.pump()
        XCTAssertTrue(ui.has(tip: "Paste Options"))
        ui.tap(tip: "Paste Options"); ui.pump()
        XCTAssertTrue(ui.has(text: "Picture (U)"))
        XCTAssertTrue(ui.has(text: "Keep Text Only (T)"))
        key(0x75, .down); key(0x75, .up); ui.pump()
        XCTAssertTrue(isPicture(deck.selection.first), "U makes it a picture")
        XCTAssertFalse(ui.has(text: "Keep Text Only (T)"), "the menu closes")
        XCTAssertTrue(ui.has(tip: "Paste Options"), "the button stays, now on the new way")
        deck.deleteSelection(); ui.pump()
        XCTAssertFalse(ui.has(tip: "Paste Options"))
    }

    /// Ctrl+Alt+V lists the clipboard's formats; OK pastes the chosen one alone, in one undo step.
    func testPasteSpecialPastesTheChosenFormat() throws {
        let (ui, state, deck) = shell()
        let n = deck.currentSlide.shapes.count
        deck.addTextBox(text: "Hello")
        XCTAssertTrue(deck.copyShapes())
        deck.selectShapes([]); ui.pump()
        XCTAssertTrue(state._shortcut(KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0x76, character: nil, synthesized: false),
                                      KeyModifiers.primary.union(.alt)))
        drain(ui)
        XCTAssertTrue(ui.has(text: "Paste Special"))
        XCTAssertTrue(ui.has(text: "Starling Slides Shapes"))
        XCTAssertTrue(ui.has(text: "Picture (PNG)"))
        ui.tap(text: "Unformatted Text"); ui.tap(text: "OK"); ui.pump()
        XCTAssertFalse(ui.has(text: "Paste Special"))
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2)
        XCTAssertEqual(deck.selection.first?.text?.document.plainText(), "Hello")
        XCTAssertEqual(deck.slidePasteOptions, .textOnly)
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
    }
}
