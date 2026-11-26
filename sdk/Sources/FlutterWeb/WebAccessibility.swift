// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Screen readers in the browser. Like the AT-SPI and VoiceOver bridges, this reads the semantics snapshot (the
// same labels, values, roles and taps) and hands it to the page, which keeps one ARIA element per node over the
// canvas (web/host/starling.js, "a11y"). Announcements go to the page's aria-live regions. Off until the page
// turns it on (the hidden "Turn on screen reader support" button, ?a11y=1, or a remembered choice), because the
// snapshot walks the whole tree.

import CSkwasm
import Flutter

extension WebAccessibility {
    nonisolated(unsafe) static var enabled = false
    nonisolated(unsafe) static var nodes: [SemanticsSnapshotNode] = []
    nonisolated(unsafe) static var lastPayload = ""
    nonisolated(unsafe) static var lastSent = 0.0
    nonisolated(unsafe) static var trailing = false
    /// The shortest gap between two trees sent to the page, in milliseconds.
    static let gap = 250.0

    static func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on {
            ScreenReader.sink = { text, priority in
                text.withUTF8String { starling_host_announce($0, $1, UInt32(priority.rawValue)) }
            }
            lastPayload = ""
            refresh()
        } else {
            ScreenReader.sink = nil
            nodes = []
            lastPayload = ""
            send("[]")
        }
    }

    /// After each presented frame: send the tree when it changed, at most once per `gap`, with one trailing update
    /// so the last change of a burst is never lost.
    static func framePresented() {
        guard enabled else { return }
        let wait = lastSent + gap - starling_host_now()
        if wait <= 0 { refresh(); return }
        if trailing { return }
        trailing = true
        WebTimers.schedule(afterMilliseconds: wait + 1) {
            trailing = false
            if enabled { refresh() }
        }
    }

    static func refresh() {
        guard let root = SemanticsRoot.provider?() else { return }
        lastSent = starling_host_now()
        let list = SemanticsSnapshot.build(from: root).filter { !$0.label.isEmpty || $0.isTextField || !$0.value.isEmpty }
        let payload = encode(list)
        nodes = list
        if payload == lastPayload { return }
        lastPayload = payload
        send(payload)
    }

    /// The page clicked node `index` (browse mode Enter, VoiceOver VO+Space).
    static func perform(_ index: Int) {
        guard index >= 0, index < nodes.count, let tap = nodes[index].tap else { return }
        tap()
    }

    // MARK: Payload

    /// Flags, one bit each; the page reads the same numbers.
    enum Flag {
        static let button = 1, textField = 2, header = 4, hasChecked = 8, checked = 16, hasToggled = 32, toggled = 64
        static let hasSelected = 128, selected = 256, disabled = 512, focused = 1024, canTap = 2048
    }

    static func flags(_ n: SemanticsSnapshotNode) -> Int {
        var f = 0
        if n.isButton { f |= Flag.button }
        if n.isTextField { f |= Flag.textField }
        if n.isHeader { f |= Flag.header }
        if let c = n.isChecked { f |= Flag.hasChecked | (c ? Flag.checked : 0) }
        if let t = n.isToggled { f |= Flag.hasToggled | (t ? Flag.toggled : 0) }
        if let s = n.isSelected { f |= Flag.hasSelected | (s ? Flag.selected : 0) }
        if n.isEnabled == false { f |= Flag.disabled }
        if n.isFocused == true { f |= Flag.focused }
        if n.canTap { f |= Flag.canTap }
        return f
    }

    /// A JSON array with one `[flags, x, y, width, height, label, value, hint]` per node, frames in CSS pixels.
    static func encode(_ list: [SemanticsSnapshotNode]) -> String {
        var out = "["
        for (i, n) in list.enumerated() {
            if i > 0 { out += "," }
            let f = n.frame ?? (0, 0, 0, 0)
            out += "[\(flags(n)),\(Int(f.x.rounded())),\(Int(f.y.rounded())),\(Int(f.width.rounded())),\(Int(f.height.rounded())),"
            out += json(n.label) + "," + json(n.value) + "," + json(n.hint) + "]"
        }
        return out + "]"
    }

    static func json(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    static func send(_ payload: String) {
        var p = payload
        p.withUTF8 { starling_host_a11y_tree($0.baseAddress, UInt32($0.count)) }
    }
}

extension String {
    fileprivate func withUTF8String(_ body: (UnsafeRawPointer?, UInt32) -> Void) {
        var s = self
        s.withUTF8 { body($0.baseAddress, UInt32($0.count)) }
    }
}

// MARK: - What the page calls

/// The page turned screen reader support on (1) or off (0).
@_expose(wasm, "starling_a11y_enable")
@_cdecl("starling_a11y_enable")
func starlingA11yEnable(_ on: Int32) {
    WebAccessibility.setEnabled(on != 0)
}

/// The reader activated the ARIA element for node `index` of the last tree sent.
@_expose(wasm, "starling_a11y_action")
@_cdecl("starling_a11y_action")
func starlingA11yAction(_ index: Int32) {
    WebAccessibility.perform(Int(index))
}
