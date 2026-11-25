#if os(Linux)
import XCTest
import Foundation
import Flutter

/// A screen reader (any AT-SPI client) sees the app's named button on the accessibility bus, and a
/// "press" from it runs the widget's tap. Needs dbus-daemon, at-spi-bus-launcher and python3-gi
/// (Atspi 2.0); the test is skipped where they are missing.
final class AtspiBridgeTests: XCTestCase {
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
    }
}
#endif
