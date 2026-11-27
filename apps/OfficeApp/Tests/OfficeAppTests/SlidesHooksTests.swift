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
        var before: () -> Void = {}
        func sweep() {
            for k in keys {
                before()
                for m in [[], [.shift], [.alt], [.shift, .alt]] as [KeyModifiers] {
                    let mods = m.union(.primary)
                    if state._shortcut(key(k), mods) { handled.insert("\(k)/\(mods.rawValue)"); handledKeys.insert(k) }
                    // Paste reads the system clipboard and lands on the main queue (S-ED-1 step 2).
                    if k == 0x76 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
                }
            }
        }
        sweep()
        // Again with a shape selected and copied (Group and Paste need one).
        // (Each key gets its own, since an earlier chord (Cmd+N, Cmd+X) can take the selection away.)
        before = {
            let deck = state.session.deck!
            if deck.selection.isEmpty {
                _ = deck.addTextBox(at: Rect.fromLTWH(10, 10, 100, 40))
                deck.copyShapes()
            }
        }
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

    /// The page is the slide's own size, as PowerPoint writes it (8640763 by
    /// 5759450 EMU is 680.4 by 453.48 pt), not Skia's whole points. Done as
    /// the PDF is written (PdfDocument's rewrite), so a browser download gets
    /// it too: the web wrote 680 by 454 (oox-tdf125085 0.16% off native).
    func testExportedPageIsTheSlidesExactSize() async throws {
        let (_, state) = await MainActor.run { shell() }
        let deck = await MainActor.run { () -> DeckController in
            let d = state.session.deck!
            d.setSlideSize(Size(8640763 / 12700.0, 5759450 / 12700.0))
            return d
        }
        let path = NSTemporaryDirectory() + "slides-hooks-exact-size.pdf"
        let ok = await SlidesPdf.write(deck, cache: SlideTextCache(), to: path, title: "T", slides: nil, output: .slides,
                                       notesTheme: RichTextTheme(fontFamily: "Calibri", fontSize: 12, headingColor: nil))
        XCTAssertTrue(ok)
        let text = String(decoding: FileManager.default.contents(atPath: path) ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("/MediaBox [0 0.52 680.4 454]"), "page box as written: \(text.components(separatedBy: "/MediaBox").dropFirst().first?.prefix(30) ?? "none")")
    }
}
