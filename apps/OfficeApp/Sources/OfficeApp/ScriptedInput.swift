// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// OFFICE_SCRIPT=path: play clicks, drags and keys into the app's own
// framework entry points (PlatformDispatcher.onPointerDataPacket and
// onKeyData) and photograph its own window — no synthetic OS events, so
// nothing reaches any other app, and with STARLING_WINDOW_BACKGROUND=1 the
// window never takes focus either. For driving the app while another
// session or a person is using the machine (2026-09-30: an OS-level
// driver's keystrokes landed in another session's window).
//
// One command per line; coordinates are logical points in the Flutter
// view (below the window's title bar):
//
//   wait MS                     sleep (default between commands: 120 ms)
//   click X Y [shift|cmd|ctrl|alt …]
//   dclick X Y                  a double click
//   drag X1 Y1 X2 Y2
//   scroll X Y DX DY            a wheel turn
//   key NAME [mods…]            enter tab escape backspace delete left right
//                               up down home end pageup pagedown f2 f4
//   type TEXT                   the rest of the line, one key per character
//   chord MODS LETTER           e.g. "chord cmd d", "chord cmd,shift z"
//   shot PATH                   screencapture -l of this window; ${OUT} expands
//                               to $OFFICE_SCRIPT_OUT
//   quit
//
// Lines starting with # are comments.

#if os(macOS)
import AppKit
import Flutter
import FlutterSwiftBridge
import Foundation

enum ScriptedInput {
    static func startIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["OFFICE_SCRIPT"], !path.isEmpty,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").map { $0.trimmingWhitespace() }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        // Let the window come up and the first frames land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { _run(lines[...]) }
    }

    private static var _pointerId: Int64 = 1
    private static var _added = false
    private static var _time = 0.0

    private static func _run(_ lines: ArraySlice<String>) {
        guard let line = lines.first else { return }
        let rest = lines.dropFirst()
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var delay = 0.12
        switch parts[0] {
        case "wait": delay = (Double(parts.count > 1 ? parts[1] : "0") ?? 0) / 1000
        case "click":
            let mods = _mods(parts.dropFirst(3))
            _modifiers(mods, down: true)
            _pointer(Double(parts[1])!, Double(parts[2])!, .down)
            _pointer(Double(parts[1])!, Double(parts[2])!, .up)
            _modifiers(mods, down: false)
        case "dclick":
            for _ in 0 ..< 2 {
                _pointer(Double(parts[1])!, Double(parts[2])!, .down)
                _pointer(Double(parts[1])!, Double(parts[2])!, .up)
            }
        case "drag":
            let x1 = Double(parts[1])!, y1 = Double(parts[2])!, x2 = Double(parts[3])!, y2 = Double(parts[4])!
            _pointer(x1, y1, .down)
            for i in 1 ... 8 {
                let t = Double(i) / 8
                _pointer(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, .move)
            }
            _pointer(x2, y2, .up)
        case "key":
            let mods = _mods(parts.dropFirst(2))
            _modifiers(mods, down: true)
            if let logical = _named[parts[1].lowercased()] { _key(logical, character: nil) }
            _modifiers(mods, down: false)
        case "type":
            let text = line.dropFirst("type ".count)
            for ch in text {
                let lower = ch.lowercased().unicodeScalars.first!.value
                _key(Int64(lower), character: String(ch))
            }
        case "chord":
            let mods = _mods(parts[1].split(separator: ",").map(String.init)[...])
            _modifiers(mods, down: true)
            let ch = parts[2].lowercased().unicodeScalars.first!.value
            _key(Int64(ch), character: parts[2])
            _modifiers(mods, down: false)
        case "scroll":
            // A wheel turn at (X, Y) by (DX, DY) logical points.
            let dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 2
            let x = Double(parts[1])! * dpr, y = Double(parts[2])! * dpr
            let t = Duration.microseconds(Int64(_time * 1_000_000))
            PlatformDispatcher.instance.onPointerDataPacket?(PointerDataPacket(data: [
                PointerData(timeStamp: t, change: .hover, kind: .mouse, signalKind: .scroll, device: 0, physicalX: x, physicalY: y,
                            scrollDeltaX: Double(parts[3])! * dpr, scrollDeltaY: Double(parts[4])! * dpr),
            ]))
        case "shot":
            // ${OUT} is the directory the runner passes (OFFICE_SCRIPT_OUT).
            let out = ProcessInfo.processInfo.environment["OFFICE_SCRIPT_OUT"] ?? NSTemporaryDirectory()
            _shot(parts[1].replacingAll("${OUT}", with: out))
            delay = 0.4
        case "quit":
            exit(0)
        default:
            FileHandle.standardError.write(Data("[script] unknown: \(line)\n".utf8))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { _run(rest) }
    }

    // MARK: Pointer

    private enum _Change { case down, move, up }

    private static func _pointer(_ x: Double, _ y: Double, _ change: _Change) {
        let dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 2
        _time += 0.02
        var packet: [PointerData] = []
        let px = x * dpr, py = y * dpr
        let t = Duration.microseconds(Int64(_time * 1_000_000))
        if !_added {
            packet.append(PointerData(timeStamp: t, change: .add, kind: .mouse, device: 0, physicalX: px, physicalY: py))
            _added = true
        }
        switch change {
        case .down:
            packet.append(PointerData(timeStamp: t, change: .hover, kind: .mouse, device: 0, physicalX: px, physicalY: py))
            _pointerId += 1
            packet.append(PointerData(timeStamp: t, change: .down, kind: .mouse, device: 0, pointerIdentifier: _pointerId,
                                      physicalX: px, physicalY: py, buttons: 1, pressure: 1, pressureMax: 1))
        case .move:
            packet.append(PointerData(timeStamp: t, change: .move, kind: .mouse, device: 0, pointerIdentifier: _pointerId,
                                      physicalX: px, physicalY: py, buttons: 1, pressure: 1, pressureMax: 1))
        case .up:
            packet.append(PointerData(timeStamp: t, change: .up, kind: .mouse, device: 0, pointerIdentifier: _pointerId,
                                      physicalX: px, physicalY: py, buttons: 0, pressure: 0, pressureMax: 1))
        }
        PlatformDispatcher.instance.onPointerDataPacket?(PointerDataPacket(data: packet))
    }

    // MARK: Keys

    private static let _named: [String: Int64] = [
        "enter": 0x1_0000_000D, "tab": 0x1_0000_0009, "escape": 0x1_0000_001B, "backspace": 0x1_0000_0008,
        "delete": 0x1_0000_007F, "left": 0x1_0000_0302, "right": 0x1_0000_0303, "up": 0x1_0000_0304,
        "down": 0x1_0000_0301, "home": 0x1_0000_0306, "end": 0x1_0000_0305, "pageup": 0x1_0000_0308,
        "pagedown": 0x1_0000_0307, "f2": 0x1_0000_0802, "f4": 0x1_0000_0804,
    ]
    private static let _modKeys: [String: Int64] = [
        "shift": 0x2_0000_0102, "ctrl": 0x2_0000_0100, "alt": 0x2_0000_0104, "cmd": 0x2_0000_0106,
    ]

    private static func _mods(_ s: ArraySlice<String>) -> [Int64] { s.compactMap { _modKeys[$0.lowercased()] } }

    private static func _modifiers(_ mods: [Int64], down: Bool) {
        for m in mods { _send(m, down ? .down : .up, nil) }
    }

    private static func _key(_ logical: Int64, character: String?) {
        _send(logical, .down, character)
        _send(logical, .up, nil)
    }

    private static func _send(_ logical: Int64, _ type: KeyEventType, _ character: String?) {
        _time += 0.01
        _ = PlatformDispatcher.instance.onKeyData?(KeyData(timeStamp: _time, type: type, physical: logical,
                                                           logical: logical, character: character, synthesized: false))
    }

    // MARK: Shots

    private static func _shot(_ path: String) {
        // The framework paints on the next frame; give it one.
        PlatformDispatcher.instance.scheduleFrame()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 200 }) else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? p.run()
            p.waitUntilExit()
        }
    }
}

#endif
