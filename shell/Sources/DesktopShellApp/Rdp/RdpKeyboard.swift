// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import FlutterEmbedderBridge
import RdpServer

/// Keyboard for display mode. The client is the only keyboard the desktop
/// has, so this stands in for `FlDrmInput::HandleKeyboard`.
///
/// The representation is the whole job. RDP sends PC/AT set-1 scancodes;
/// the engine wants a HID usage code as `physical`, an xkb keysym as
/// `logical`, and UTF-8 as `character`; Wayland clients then receive evdev
/// back through `HidEvdev`. Convert in the wrong place — or invent a second
/// table — and letters break for clients while the shell's own UI looks
/// perfect, which is the failure CLAUDE.md warns about for this pair.
///
/// Main queue only.
final class RdpKeyboard {

    private var engine: OpaquePointer?
    private let xkb: OpaquePointer?
    private var logged = 0

    private func warn(_ msg: String) {
        FileHandle.standardError.write(Data("[RdpKbd] \(msg)\n".utf8))
    }

    init() {
        xkb = rdp_keyboard_create()
        if xkb == nil {
            FileHandle.standardError.write(Data(
                "[RdpKbd] xkb unavailable — keyboard disabled\n".utf8))
        }
    }

    deinit {
        if let xkb { rdp_keyboard_destroy(xkb) }
    }

    func attach(engine: OpaquePointer?) {
        self.engine = engine
    }

    func handle(scancode: UInt32, extended: Bool, down: Bool) {
        guard let engine, let xkb else { return }
        var evdev: UInt32 = 0
        var keysym: UInt32 = 0
        var utf8 = [CChar](repeating: 0, count: 16)
        let ok = utf8.withUnsafeMutableBufferPointer { buf in
            rdp_keyboard_key(xkb, scancode, extended ? 1 : 0, down ? 1 : 0,
                             &evdev, &keysym, buf.baseAddress, Int32(buf.count))
        }
        guard ok != 0 else {
            logged += 1
            if logged <= 20 {
                warn("scancode \(String(scancode, radix: 16))"
                     + "\(extended ? " ext" : "") has no evdev — dropped")
            }
            return
        }
        // First events only, like the engine's [Input] logging: enough to
        // see the translation is right, not enough to flood a session.
        logged += 1
        if logged <= 20 {
            let ch = utf8[0] != 0 ? String(cString: utf8) : ""
            warn("key sc=\(String(scancode, radix: 16))\(extended ? "ext" : "")"
                 + " evdev=\(evdev) hid=0x\(String(HidEvdev.hid(fromEvdev: evdev), radix: 16))"
                 + " sym=0x\(String(keysym, radix: 16))"
                 + " char=\(ch.isEmpty ? "-" : ch) \(down ? "DOWN" : "up")")
        }
        send(engine, evdev: evdev, keysym: keysym, utf8: utf8, down: down)
    }

    func sync(toggleFlags: UInt32) {
        guard let xkb else { return }
        rdp_keyboard_sync(xkb, toggleFlags)
    }

    /// Release everything still held. A client that vanishes mid-chord would
    /// otherwise leave Ctrl or Shift down forever — stuck at every layer,
    /// poisoning later characters, exactly what the engine's ReleaseAllKeys
    /// exists to prevent on a VT switch.
    func releaseAll() {
        guard let engine, let xkb else { return }
        var held = [UInt32](repeating: 0, count: 64)
        let n = held.withUnsafeMutableBufferPointer {
            rdp_keyboard_pressed(xkb, $0.baseAddress, Int32($0.count))
        }
        if n > 0 {
            let empty = [CChar](repeating: 0, count: 1)
            for i in 0 ..< Int(n) {
                send(engine, evdev: held[i], keysym: 0, utf8: empty,
                     down: false, synthesized: true)
            }
        }
        rdp_keyboard_reset(xkb)
    }

    private func send(_ engine: OpaquePointer, evdev: UInt32, keysym: UInt32,
                      utf8: [CChar], down: Bool, synthesized: Bool = false) {
        var event = FlutterKeyEvent()
        event.struct_size = MemoryLayout<FlutterKeyEvent>.size
        event.timestamp = Double(FlutterEngineGetCurrentTime() / 1000)
        event.type = down ? kFlutterKeyEventTypeDown : kFlutterKeyEventTypeUp
        event.physical = HidEvdev.hid(fromEvdev: evdev)
        event.logical = UInt64(keysym)
        event.synthesized = synthesized
        if utf8[0] != 0 {
            utf8.withUnsafeBufferPointer { p in
                event.character = p.baseAddress
                FlutterEngineSendKeyEvent(engine, &event, nil, nil)
            }
        } else {
            event.character = nil
            FlutterEngineSendKeyEvent(engine, &event, nil, nil)
        }
    }
}
#endif
