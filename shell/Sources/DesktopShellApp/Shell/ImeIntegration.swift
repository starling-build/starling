// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import Flutter
import FlutterSwiftBridge
import ImeBridge

/// Bridges the shell's key stream to fcitx5 (via ImeBridge/DBus) and surfaces
/// preedit + candidate state for the shell-drawn input panel.
///
/// Flow: `handleKey` offers every key to fcitx while IME input is enabled.
/// Consumed keys are swallowed (their key-ups too); fcitx answers with
/// `CommitString` / client-side-panel signals, which arrive on the bridge
/// thread and are marshalled onto the main queue before touching shell state.
final class ImeIntegration: @unchecked Sendable {

    /// Committed text ready for insertion into the focused app.
    var onCommit: ((String) -> Void)?
    /// Preedit (composition) text + candidate list for the shell's panel UI.
    var onPanelChanged: ((_ preedit: String, _ candidates: [(String, String)],
                         _ highlighted: Int) -> Void)?
    /// A key fcitx did NOT consume — deliver it to the focused app now.
    /// (Keys are swallowed optimistically and replayed on this verdict; the
    /// DRM event loop must never block waiting for fcitx.)
    var onReplayKey: ((KeyData) -> Void)?

    private var bridge: OpaquePointer? = nil
    private var bridgeBox: ImeBridgeBox? = nil

    // Modifier state tracked from the raw key stream (HID usage ids).
    private(set) var ctrlDown = false
    private var shiftDown = false
    private var altDown = false

    // Physical ids whose key-down was routed to fcitx — swallow the
    // matching ups (replayed downs deliver a full down+up to the app).
    private var swallowedPhysical: Set<Int64> = []

    // Keys in flight to fcitx, by cookie — replayed if the verdict is
    // "unhandled". Ordered map semantics aren't needed: fcitx answers FIFO
    // and each cookie is unique.
    private var inflight: [UInt64: KeyData] = [:]
    private var nextCookie: UInt64 = 1

    /// Wrapper class so C callbacks can hold a stable context pointer.
    private final class ImeBridgeBox {
        unowned let owner: ImeIntegration
        init(owner: ImeIntegration) { self.owner = owner }
    }

    init() {
        let box = ImeBridgeBox(owner: self)
        bridgeBox = box
        let ctx = Unmanaged.passUnretained(box).toOpaque()

        var cbs = ImeBridgeCallbacks()
        cbs.ctx = ctx
        cbs.commit_string = { (ctx, text) in
            guard let ctx, let text else { return }
            let owner = Unmanaged<ImeBridgeBox>.fromOpaque(ctx)
                .takeUnretainedValue().owner
            let s = String(cString: text)
            onPlatformThread { owner.onCommit?(s) }
        }
        cbs.preedit = { (ctx, text, _) in
            guard let ctx, let text else { return }
            let owner = Unmanaged<ImeBridgeBox>.fromOpaque(ctx)
                .takeUnretainedValue().owner
            let s = String(cString: text)
            onPlatformThread {
                owner.preedit = s
                owner.emitPanel()
            }
        }
        cbs.candidates = { (ctx, labels, texts, count, highlighted, _, _) in
            guard let ctx else { return }
            let owner = Unmanaged<ImeBridgeBox>.fromOpaque(ctx)
                .takeUnretainedValue().owner
            var list: [(String, String)] = []
            if let labels, let texts, count > 0 {
                for i in 0 ..< Int(count) {
                    let label = labels[i].map { String(cString: $0) } ?? ""
                    let text = texts[i].map { String(cString: $0) } ?? ""
                    list.append((label, text))
                }
            }
            let hl = Int(highlighted)
            onPlatformThread {
                owner.candidates = list
                owner.highlighted = hl
                owner.emitPanel()
            }
        }
        cbs.forward_key = { (_, _, _, _) in
            // Keys fcitx explicitly bounces back mid-stream. The async
            // verdict path already replays unhandled keys, so nothing extra
            // to inject here.
        }
        cbs.key_verdict = { (ctx, cookie, handled) in
            guard let ctx else { return }
            let owner = Unmanaged<ImeBridgeBox>.fromOpaque(ctx)
                .takeUnretainedValue().owner
            onPlatformThread {
                owner.resolveVerdict(cookie: cookie, handled: handled != 0)
            }
        }
        // Root shell (DRM master) → the bridge thread must authenticate to
        // the user's bus as the login user (the runtime dir's owner).
        var targetUid: UInt32 = 0
        if getuid() == 0 { targetUid = UInt32(LoginUser.uid) }
        bridge = ime_bridge_create(&cbs, targetUid)
    }

    deinit {
        ime_bridge_destroy(bridge)
    }

    private var preedit = ""
    private var candidates: [(String, String)] = []
    private var highlighted = -1

    private func emitPanel() {
        onPanelChanged?(preedit, candidates, highlighted)
    }

    var isReady: Bool { ime_bridge_ready(bridge) != 0 }

    /// Abandon any in-progress composition (target window changed/closed).
    func resetComposition() {
        ime_bridge_reset(bridge)
        preedit = ""
        candidates = []
        highlighted = -1
        swallowedPhysical.removeAll()
        inflight.removeAll()
        emitPanel()
    }

    /// Forward the caret rect (screen logical coords) to fcitx.
    func setCursorRect(x: Double, y: Double, width: Double, height: Double) {
        ime_bridge_set_cursor_rect(bridge, Int32(x), Int32(y),
                                   Int32(width), Int32(height))
    }

    func focusIn() { ime_bridge_focus_in(bridge) }
    func focusOut() {
        ime_bridge_focus_out(bridge)
        ime_bridge_reset(bridge)
        preedit = ""
        candidates = []
        highlighted = -1
        emitPanel()
    }

    /// Offer a key to fcitx. Returns true when the key was routed (the
    /// caller must not deliver it now — an unhandled verdict replays it via
    /// `onReplayKey`). Fully async: never blocks the DRM event loop.
    /// Modifier keys are tracked but never routed.
    func handleKey(_ keyData: KeyData) -> Bool {
        let phys = keyData.physical & 0xFFFF

        // Modifier tracking (HID usage: E0..E7).
        if (0xE0 ... 0xE7).contains(phys) {
            let down = keyData.type != .up
            switch phys {
            case 0xE0, 0xE4: ctrlDown = down
            case 0xE1, 0xE5: shiftDown = down
            case 0xE2, 0xE6: altDown = down
            default: break
            }
            return false
        }

        if keyData.type == .up {
            if swallowedPhysical.remove(keyData.physical) != nil {
                return true
            }
            return false
        }

        guard let keysym = Self.keysym(for: keyData) else { return false }
        var state: UInt32 = 0
        if shiftDown { state |= 1 << 0 }
        if ctrlDown { state |= 1 << 2 }
        if altDown { state |= 1 << 3 }

        let cookie = nextCookie
        nextCookie += 1
        inflight[cookie] = keyData
        swallowedPhysical.insert(keyData.physical)
        ime_bridge_process_key_async(
            bridge, keysym, 0, state, 0,
            UInt32(truncatingIfNeeded: DispatchTime.now().uptimeNanoseconds
                / 1_000_000),
            cookie)
        return true
    }

    /// Async verdict from fcitx (main queue). Unhandled → replay to the app.
    fileprivate func resolveVerdict(cookie: UInt64, handled: Bool) {
        guard let keyData = inflight.removeValue(forKey: cookie) else { return }
        if !handled {
            onReplayKey?(keyData)
        }
    }

    /// HID usage / character → X11 keysym (what fcitx expects).
    private static func keysym(for keyData: KeyData) -> UInt32? {
        switch keyData.physical & 0xFFFF {
        case 0x28: return 0xFF0D  // Enter
        case 0x29: return 0xFF1B  // Escape
        case 0x2A: return 0xFF08  // Backspace
        case 0x2B: return 0xFF09  // Tab
        case 0x4A: return 0xFF50  // Home
        case 0x4B: return 0xFF55  // PageUp
        case 0x4C: return 0xFFFF  // Delete
        case 0x4D: return 0xFF57  // End
        case 0x4E: return 0xFF56  // PageDown
        case 0x4F: return 0xFF53  // Right
        case 0x50: return 0xFF51  // Left
        case 0x51: return 0xFF54  // Down
        case 0x52: return 0xFF52  // Up
        default:
            guard let scalar = keyData.character?.unicodeScalars.first,
                  scalar.value >= 0x20 else { return nil }
            // Latin-1 keysyms equal the codepoint; others use the Unicode
            // keysym range.
            return scalar.value < 0x100
                ? scalar.value
                : 0x0100_0000 | scalar.value
        }
    }
}
#endif
