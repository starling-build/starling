#if os(Linux)
import XCTest
import Foundation
import Flutter

/// A screen reader (any AT-SPI client) sees the app's named button on the accessibility bus, and a
/// "press" from it runs the widget's tap. Needs dbus-daemon, at-spi-bus-launcher and python3-gi
/// (Atspi 2.0); the test is skipped where they are missing.
final class AtspiBridgeTests: XCTestCase {
    // The bridge is process-wide: leave it off for the tests that follow (a screen reader listening makes every
    // Sheets edit describe the active cell, and that once cost a 50,000-row test 150 s).
    override func tearDown() {
        AtspiAccessibility.stop()
        ScreenReader.resetForTesting()
        super.tearDown()
    }

    private func which(_ tool: String) -> String? {
        for dir in ["/usr/bin", "/usr/libexec", "/usr/local/bin"] {
            if FileManager.default.isExecutableFile(atPath: dir + "/" + tool) { return dir + "/" + tool }
        }
        return nil
    }

    func testScreenReaderClientSeesNamedButtonAndPressesIt() throws {
        guard let dbus = which("dbus-daemon"), let launcher = which("at-spi-bus-launcher"),
              let python = which("python3") else { throw XCTSkip("no dbus / at-spi tools") }
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: python)
        probe.arguments = ["-c", "import gi; gi.require_version('Atspi','2.0')"]
        probe.standardError = FileHandle.nullDevice
        try probe.run(); probe.waitUntilExit()
        if probe.terminationStatus != 0 { throw XCTSkip("python3 gi Atspi missing") }

        // Our own session bus, so the test never touches the user's desktop.
        let bus = Process()
        bus.executableURL = URL(fileURLWithPath: dbus)
        bus.arguments = ["--session", "--nofork", "--print-address"]
        let out = Pipe(); bus.standardOutput = out
        try bus.run()
        defer { bus.terminate() }
        let addr = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(addr.isEmpty)
        setenv("DBUS_SESSION_BUS_ADDRESS", addr, 1)
        let al = Process()
        al.executableURL = URL(fileURLWithPath: launcher)
        al.arguments = ["--launch-immediately"]
        al.standardError = FileHandle.nullDevice
        try al.run()
        defer { al.terminate() }

        var pressed = 0
        let t = WidgetTester(Directionality(textDirection: .ltr, child: Semantics(label: "Save document", button: true, onTap: { pressed += 1 },
                                       child: SizedBox(width: 20, height: 20, child: nil))))
        defer { t.dispose() }
        let rc = AtspiAccessibility.start(appName: "bridge-test", provider: { t.elements().first })
        XCTAssertEqual(rc, 0, "bridge failed to start")

        let script = """
        import gi, sys
        gi.require_version('Atspi','2.0')
        from gi.repository import Atspi
        Atspi.init()
        d = Atspi.get_desktop(0)
        for i in range(d.get_child_count()):
            app = d.get_child_at_index(i)
            if app.get_name() != 'bridge-test': continue
            for j in range(app.get_child_count()):
                c = app.get_child_at_index(j)
                if c.get_name() == 'Save document':
                    print('FOUND', c.get_role_name())
                    e = Atspi.Component.get_extents(c, Atspi.CoordType.WINDOW)
                    print('SIZE', e.width, e.height)
                    print('PRESSED', Atspi.Action.do_action(c, 0))
        """
        let client = Process()
        client.executableURL = URL(fileURLWithPath: python)
        client.arguments = ["-c", script]
        let cout = Pipe(); client.standardOutput = cout; client.standardError = FileHandle.nullDevice
        try client.run()
        // The bridge asks the main thread for snapshots, so keep it turning while the client works.
        let deadline = Date().addingTimeInterval(30)
        while client.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if client.isRunning { client.terminate() }
        let text = String(decoding: cout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(text.contains("FOUND button"), "client saw: \(text)")
        XCTAssertTrue(text.contains("SIZE 20 20"), "client saw: \(text)")
        XCTAssertTrue(text.contains("PRESSED True"), "client saw: \(text)")
        XCTAssertEqual(pressed, 1)
    
        // And a client that listens hears a rename.
        let script2 = """
        import gi, sys
        gi.require_version('Atspi','2.0')
        from gi.repository import Atspi, GLib
        Atspi.init()
        d = Atspi.get_desktop(0)
        for i in range(d.get_child_count()):
            app = d.get_child_at_index(i)
            if app.get_name() == 'bridge-test': app.get_child_count(); app.get_child_at_index(0).get_name()
        def on(e):
            print('EVENT', e.type, e.source.get_name()); sys.stdout.flush()
        l = Atspi.EventListener.new(on)
        l.register('object:property-change:accessible-name')
        l.register('object:state-changed:focused')
        print('READY'); sys.stdout.flush()
        GLib.timeout_add_seconds(15, lambda: sys.exit(0))
        Atspi.event_main()
        """
        let client2 = Process()
        client2.executableURL = URL(fileURLWithPath: python)
        client2.arguments = ["-c", script2]
        let cout2 = Pipe(); client2.standardOutput = cout2; client2.standardError = FileHandle.nullDevice
        var seen = ""
        cout2.fileHandleForReading.readabilityHandler = { h in seen += String(decoding: h.availableData, as: UTF8.self) }
        try client2.run()
        defer { if client2.isRunning { client2.terminate() } }
        func wait(_ cond: () -> Bool, _ secs: Double) {
            let end = Date().addingTimeInterval(secs)
            while !cond() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        }
        wait({ seen.contains("READY") }, 20)
        XCTAssertTrue(seen.contains("READY"), "client saw: \(seen)")
        t.replace(with: Directionality(textDirection: .ltr, child: Semantics(label: "Saved", button: true, onTap: {}, child: SizedBox(width: 20, height: 20, child: nil))))
        wait({ seen.contains("EVENT") }, 10)
        XCTAssertTrue(seen.contains("EVENT object:property-change:accessible-name Saved"), "client saw: \(seen)")

        // Moving focus is announced too: the control that gets it is named in the event.
        t.replace(with: Directionality(textDirection: .ltr, child: Semantics(label: "Saved", button: true, focused: true, onTap: {}, child: SizedBox(width: 20, height: 20, child: nil))))
        wait({ seen.contains("EVENT object:state-changed:focused Saved") }, 10)
        XCTAssertTrue(seen.contains("EVENT object:state-changed:focused Saved"), "client saw: \(seen)")

        // And a text field is read as text: contents, caret and selection, counted in characters.
        t.replace(with: Directionality(textDirection: .ltr, child: Semantics(
            label: "Name", value: "h\u{e9}llo w\u{f6}rld \u{1F600}!", textField: true,
            textSelection: TextSelection(baseOffset: 1, extentOffset: 4),
            child: SizedBox(width: 20, height: 20, child: nil))))
        let script3 = """
        import gi
        gi.require_version('Atspi','2.0')
        from gi.repository import Atspi
        Atspi.init()
        d = Atspi.get_desktop(0)
        for i in range(d.get_child_count()):
            app = d.get_child_at_index(i)
            if app.get_name() != 'bridge-test': continue
            for j in range(app.get_child_count()):
                c = app.get_child_at_index(j)
                if c.get_name() == 'Name':
                    print('COUNT', Atspi.Text.get_character_count(c))
                    print('TEXT', Atspi.Text.get_text(c, 6, 12))
                    print('CARET', Atspi.Text.get_caret_offset(c))
                    s = Atspi.Text.get_selection(c, 0)
                    print('SEL', s.start_offset, s.end_offset)
        """
        let client3 = Process()
        client3.executableURL = URL(fileURLWithPath: python)
        client3.arguments = ["-c", script3]
        let cout3 = Pipe(); client3.standardOutput = cout3; client3.standardError = FileHandle.nullDevice
        try client3.run()
        let end3 = Date().addingTimeInterval(30)
        while client3.isRunning && Date() < end3 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if client3.isRunning { client3.terminate() }
        let text3 = String(decoding: cout3.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(text3.contains("COUNT 14"), "client saw: \(text3)")
        XCTAssertTrue(text3.contains("TEXT w\u{f6}rld"), "client saw: \(text3)")
        XCTAssertTrue(text3.contains("CARET 4"), "client saw: \(text3)")
        XCTAssertTrue(text3.contains("SEL 1 4"), "client saw: \(text3)")

        // A screen reader types, deletes and moves the caret; the field's own handlers see it (offsets in characters).
        var edits: [String] = []
        var caret: (Int, Int)? = nil
        AtspiAccessibility.windowOrigin = { (100, 50) }
        defer { AtspiAccessibility.windowOrigin = nil }
        t.replace(with: Directionality(textDirection: .ltr, child: Semantics(
            label: "Edit me", value: "\u{1F600}ab", textField: true,
            textSelection: TextSelection(baseOffset: 0, extentOffset: 0),
            onSetSelection: { caret = (Int($0.baseOffset), Int($0.extentOffset)) },
            onReplaceRange: { edits.append("\($0)-\($1)=\($2)") },
            child: SizedBox(width: 20, height: 10, child: nil))))
        let script4 = """
        import gi
        gi.require_version('Atspi','2.0')
        from gi.repository import Atspi
        Atspi.init()
        d = Atspi.get_desktop(0)
        for i in range(d.get_child_count()):
            app = d.get_child_at_index(i)
            if app.get_name() != 'bridge-test': continue
            for j in range(app.get_child_count()):
                c = app.get_child_at_index(j)
                if c.get_name() == 'Edit me':
                    e = Atspi.Component.get_extents(c, Atspi.CoordType.SCREEN)
                    print('SCREEN', e.x, e.y)
                    w = Atspi.Component.get_extents(c, Atspi.CoordType.WINDOW)
                    print('WINDOW', w.x, w.y)
                    print('INSERT', Atspi.EditableText.insert_text(c, 1, 'Z', 1))
                    print('DELETE', Atspi.EditableText.delete_text(c, 2, 3))
                    print('CARET', Atspi.Text.set_caret_offset(c, 2))
                    print('SELECT', Atspi.Text.set_selection(c, 0, 1, 3))
        """
        let client4 = Process()
        client4.executableURL = URL(fileURLWithPath: python)
        client4.arguments = ["-c", script4]
        let cout4 = Pipe(); client4.standardOutput = cout4; client4.standardError = FileHandle.nullDevice
        try client4.run()
        let end4 = Date().addingTimeInterval(30)
        while client4.isRunning && Date() < end4 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if client4.isRunning { client4.terminate() }
        let text4 = String(decoding: cout4.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(text4.contains("SCREEN 100 50"), "client saw: \(text4)")
        XCTAssertTrue(text4.contains("WINDOW 0 0"), "client saw: \(text4)")
        // The emoji is one character but two UTF-16 units: character 1 is unit 2, character 2..3 is units 3..4.
        XCTAssertEqual(edits, ["2-2=Z", "3-4="])
        XCTAssertTrue(text4.contains("INSERT True") && text4.contains("DELETE True"), "client saw: \(text4)")
        XCTAssertTrue(text4.contains("SELECT True"), "client saw: \(text4)")
        XCTAssertEqual(caret?.0, 2); XCTAssertEqual(caret?.1, 4)   // the last select: characters 1..3 = units 2..4
    }
}
#endif
