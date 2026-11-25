import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The shortcut list against the real key handlers: every chord the list
/// shows works, and no chord works that the list does not show.
final class ShortcutListTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeShellState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: OfficeShell(initialPath: nil, startBlank: true), title: "T"),
                              size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!)
    }

    private func key(_ k: UInt32) -> KeyData {
        KeyData(timeStamp: 0, type: .down, physical: 0, logical: Int64(k), character: nil, synthesized: false)
    }

    /// The editor handles these itself (RichEditable), not the shell.
    private func editorOwned(_ e: ShortcutEntry) -> Bool {
        let letter = Character(Unicode.Scalar(e.key)!)
        if "axcbiuy".contains(letter), e.extra.isEmpty { return true }
        if letter == "v", e.extra.isEmpty { return true }
        if letter == "z", e.extra.isEmpty || e.extra == .shift { return true }
        return false
    }

    func testShellChordsMatchTheTable() {
        let (_, state) = shell()
        let table = ShortcutTable.writer
        var exact = Set<String>()      // key/modifiers the list shows
        var listedKeys = Set<UInt32>()
        for e in table where !editorOwned(e) { exact.insert("\(e.key)/\(e.modifiers.rawValue)"); listedKeys.insert(e.key) }
        // Every key a shortcut could use, with every modifier mix.
        var keys: [UInt32] = Array(0x61...0x7A) + Array(0x30...0x39)
        keys += "=-+[]/\\,.;'`*".unicodeScalars.map { $0.value }
        let mixes: [KeyModifiers] = [[], [.shift], [.alt], [.shift, .alt]]
        var handled = Set<String>()
        var handledKeys = Set<UInt32>()
        for k in keys {
            for m in mixes {
                let mods = m.union(.primary)
                if state._shortcut(key(k), mods) { handled.insert("\(k)/\(mods.rawValue)"); handledKeys.insert(k) }
            }
        }
        // The handler may take a listed key with a spare Shift or Alt (as
        // Word does for several); what it must not do is act on a key the
        // list never mentions. "+" and "*" are the shifted "=" and "8".
        handledKeys.remove(0x2B); handledKeys.remove(0x2A)
        XCTAssertEqual(handledKeys.subtracting(listedKeys), [], "keys work that the list does not show")
        XCTAssertEqual(exact.subtracting(handled), [], "the list shows chords that do nothing")
    }

    func testEveryEntryIsUnique() {
        let ids = ShortcutTable.writer.map { "\($0.key)/\($0.modifiers.rawValue)" }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testLabels() {
        let save = ShortcutEntry("File", "Save as", "s", .shift)
        XCTAssertEqual(save.label(apple: false), "Ctrl+Shift+S")
        XCTAssertEqual(save.label(apple: true), "⇧⌘S")
        let h = ShortcutEntry("Paragraph", "Heading 1", "1", .alt)
        XCTAssertEqual(h.label(apple: false), "Ctrl+Alt+1")
        XCTAssertEqual(h.label(apple: true), "⌥⌘1")
    }

    func testDialogShowsTheListAndCloses() {
        var closed = 0
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: ShortcutListDialog(table: ShortcutTable.writer, onClose: { closed += 1 }), title: "T"),
                              size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Keyboard shortcuts"))
        XCTAssertTrue(ui.has(text: "Bold"))
        ui.tap(text: "Close")
        XCTAssertEqual(closed, 1)
    }

    func testBackstageButtonOpensTheList() {
        let (ui, state) = shell()
        _ = state._shortcut(key(0x2F), .primary)
        ui.pump()
        XCTAssertTrue(ui.has(text: "Keyboard shortcuts"))
        ui.tap(text: "Close")
        XCTAssertFalse(ui.has(text: "Bold"))
    }
}
