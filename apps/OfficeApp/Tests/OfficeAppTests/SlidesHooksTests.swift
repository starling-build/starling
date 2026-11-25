import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Slides' shortcut list and Print dialog against the real shell.
final class SlidesHooksTests: XCTestCase {
    private func shell() -> (WidgetTester, SlidesShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "T"),
                              size: Size(1280, 800))
        return (ui, ui.state(SlidesShellState.self)!)
    }

    private func key(_ k: UInt32) -> KeyData {
        KeyData(timeStamp: 0, type: .down, physical: 0, logical: Int64(k), character: nil, synthesized: false)
    }

    func testShellChordsMatchTheTable() {
        let (_, state) = shell()
        var exact = Set<String>(), listedKeys = Set<UInt32>()
        for e in ShortcutTable.slides { exact.insert("\(e.key)/\(e.modifiers.rawValue)"); listedKeys.insert(e.key) }
        var keys: [UInt32] = Array(0x61...0x7A) + Array(0x30...0x39)
        keys += "=-+[]/\\,.;'`*".unicodeScalars.map { $0.value }
        var handled = Set<String>(), handledKeys = Set<UInt32>()
        func sweep() {
            for k in keys {
                for m in [[], [.shift], [.alt], [.shift, .alt]] as [KeyModifiers] {
                    let mods = m.union(.primary)
                    if state._shortcut(key(k), mods) { handled.insert("\(k)/\(mods.rawValue)"); handledKeys.insert(k) }
                }
            }
        }
        sweep()
        // Again with a shape selected and copied (Group and Paste need one).
        _ = state.session.deck!.addTextBox(at: Rect.fromLTWH(10, 10, 100, 40))
        state.session.deck!.copyShapes()
        sweep()
        XCTAssertEqual(handledKeys.subtracting(listedKeys), [], "keys work that the list does not show")
        XCTAssertEqual(exact.subtracting(handled), [], "the list shows chords that do nothing")
    }

    func testEveryEntryIsUnique() {
        let ids = ShortcutTable.slides.map { "\($0.key)/\($0.modifiers.rawValue)" }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testShortcutListOpens() {
        let (ui, state) = shell()
        _ = state._shortcut(key(0x2F), .primary)
        ui.pump()
        XCTAssertTrue(ui.has(text: "Keyboard shortcuts"))
        XCTAssertTrue(ui.has(text: "New slide"))
        ui.tap(text: "Close")
        XCTAssertFalse(ui.has(text: "New slide"))
    }

    func testPrintDialogAsksWhatToPrint() {
        let (ui, state) = shell()
        _ = state._shortcut(key(0x70), .primary)
        ui.pump()
        XCTAssertTrue(ui.has(text: "Print"))
        XCTAssertTrue(ui.has(text: "Print what"))
    }

    /// Slides, notes pages and handouts each make a PDF with the right page count.
    func testPrintOutputsMakeTheirPages() async throws {
        let (_, state) = await MainActor.run { shell() }
        let deck = await MainActor.run { () -> DeckController in
            let d = state.session.deck!
            for _ in 0..<7 { d.addSlide() }     // eight slides
            return d
        }
        let cache = SlideTextCache()
        func pages(_ out: SlidesPdf.Output, _ only: [Int]?) async -> Int {
            let path = NSTemporaryDirectory() + "slides-hooks-\(out.rawValue).pdf"
            let ok = await SlidesPdf.write(deck, cache: cache, to: path, title: "T", slides: only, output: out,
                                           notesTheme: RichTextTheme(fontFamily: "Calibri", fontSize: 12, headingColor: nil))
            XCTAssertTrue(ok)
            let text = String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self)
            return text.components(separatedBy: "/Type /Page\n").count - 1 + text.components(separatedBy: "/Type/Page/").count - 1
        }
        let slides = await pages(.slides, [1, 2, 3])
        let notes = await pages(.notes, [1, 2, 3])
        let handouts = await pages(.handouts, nil)
        XCTAssertEqual(slides, 3)
        XCTAssertEqual(notes, 3)
        XCTAssertEqual(handouts, 2)     // eight slides, six to a page
    }
}
