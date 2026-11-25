// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// VoiceOver on macOS. The engine's own semantics path is a stub here, so this publishes the semantics
// snapshot (the same one the Linux AT-SPI bridge uses) as NSAccessibilityElement children of the
// window's content view: each labelled node is a button, text field, check box ... that VoiceOver can
// read, move to and press. It only runs while VoiceOver is on, so it costs nothing otherwise.

#if os(macOS)
import AppKit
import Flutter
import Foundation

final class CocoaAccessibleNode: NSAccessibilityElement {
    var tap: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let tap else { return false }
        tap()
        return true
    }
}

public enum CocoaAccessibility {
    nonisolated(unsafe) private static var timer: Timer?
    nonisolated(unsafe) private static var lastKey = ""

    /// Starts watching: while VoiceOver is on, the content view's accessibility children follow the app.
    public static func start() {
        guard timer == nil else { return }
        ScreenReader.sink = { text, priority in
            guard NSWorkspace.shared.isVoiceOverEnabled else { return }
            let level: NSAccessibilityPriorityLevel = priority == .assertive ? .high : .medium
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: level.rawValue])
        }
        pollDisplaySettings()
        let t = Timer(timeInterval: 0.4, repeats: true) { _ in refresh(); pollDisplaySettings() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Increase Contrast. macOS has no system-wide text size or bold-text setting, so those stay at their defaults.
    static func pollDisplaySettings() {
        SystemDisplay.update(DisplaySettings(textScale: 1, increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                                             boldText: false))
    }

    static func refresh() {
        guard NSWorkspace.shared.isVoiceOverEnabled,
              let root = SemanticsRoot.provider?(),
              let view = NSApp.mainWindow?.contentView ?? NSApp.windows.first?.contentView else { return }
        let nodes = SemanticsSnapshot.build(from: root).filter { !$0.label.isEmpty || $0.isTextField }
        // Only tell VoiceOver when something it would say differs.
        let key = nodes.map { "\($0.label)|\($0.value)|\($0.isEnabled ?? true)|\($0.isChecked.map(String.init(describing:)) ?? "")|\($0.isFocused ?? false)" }
            .joined(separator: "\n")
        if key == lastKey { return }
        let focusChanged = lastKey.isEmpty ? false : nodes.map { $0.isFocused ?? false } != previousFocus
        lastKey = key
        previousFocus = nodes.map { $0.isFocused ?? false }
        view.setAccessibilityChildren(elements(for: nodes, in: view))
        NSAccessibility.post(element: view, notification: .layoutChanged)
        if focusChanged { NSAccessibility.post(element: view, notification: .focusedUIElementChanged) }
    }
    nonisolated(unsafe) private static var previousFocus: [Bool] = []

    /// One accessibility element per node, with its place on screen (AppKit wants bottom-left screen points).
    static func elements(for nodes: [SemanticsSnapshotNode], in view: NSView) -> [NSAccessibilityElement] {
        nodes.map { n in
            let e = CocoaAccessibleNode()
            e.setAccessibilityParent(view)
            e.setAccessibilityLabel(n.label)
            if !n.hint.isEmpty { e.setAccessibilityHelp(n.hint) }
            e.setAccessibilityEnabled(n.isEnabled ?? true)
            e.setAccessibilityFocused(n.isFocused ?? false)
            e.setAccessibilityRole(role(of: n))
            if n.isTextField { e.setAccessibilityValue(n.value) }
            else if let c = n.isChecked ?? n.isToggled { e.setAccessibilityValue(c ? 1 : 0) }
            if let s = n.isSelected { e.setAccessibilitySelected(s) }
            if let f = n.frame {
                // The Flutter view is flipped (y down); AppKit's screen space is y up.
                let local = NSRect(x: f.x, y: f.y, width: f.width, height: f.height)
                let flipped = view.isFlipped ? local
                    : NSRect(x: local.minX, y: view.bounds.height - local.maxY, width: local.width, height: local.height)
                let inWindow = view.convert(flipped, to: nil)
                if let w = view.window { e.setAccessibilityFrame(w.convertToScreen(inWindow)) }
            }
            e.tap = n.tap
            return e
        }
    }

    static func role(of n: SemanticsSnapshotNode) -> NSAccessibility.Role {
        if n.isTextField { return .textField }
        if n.isHeader { return .staticText }
        if n.isChecked != nil { return .checkBox }
        if n.isToggled != nil { return .checkBox }
        if n.isButton || n.canTap { return .button }
        return .staticText
    }
}
#endif
