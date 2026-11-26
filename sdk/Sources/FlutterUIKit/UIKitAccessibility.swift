// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// VoiceOver on iOS and iPadOS. The engine's own semantics path is not used here, so this publishes the
// semantics snapshot (the one the Linux AT-SPI and macOS bridges use) as UIAccessibilityElements of the
// root view: each labelled node is a button, text field, switch ... that VoiceOver can read, move to
// and double-tap. It only runs while VoiceOver is on, so it costs nothing otherwise.

#if os(iOS)
import Flutter
import Foundation
import UIKit

final class UIKitAccessibleNode: UIAccessibilityElement {
    var tap: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let tap else { return false }
        tap()
        return true
    }
}

public enum UIKitAccessibility {
    nonisolated(unsafe) private static var timer: Timer?
    nonisolated(unsafe) private static var lastKey = ""
    nonisolated(unsafe) private static var previousFocus: [Bool] = []

    /// Starts watching: while VoiceOver is on, the root view's accessibility elements follow the app.
    public static func start() {
        guard timer == nil else { return }
        ScreenReader.sink = { text, _ in
            guard UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(notification: .announcement, argument: text)
        }
        pollDisplaySettings()
        let t = Timer(timeInterval: 0.4, repeats: true) { _ in refresh(); pollDisplaySettings() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Dynamic Type, Increase Contrast and Bold Text, as the chrome follows them.
    static func pollDisplaySettings() {
        let scale = Double(UIFontMetrics.default.scaledValue(for: 100)) / 100
        SystemDisplay.update(DisplaySettings(textScale: scale, increasedContrast: UIAccessibility.isDarkerSystemColorsEnabled,
                                             boldText: UIAccessibility.isBoldTextEnabled))
    }

    static func rootView() -> UIView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.rootViewController?.view
    }

    static func refresh() {
        guard UIAccessibility.isVoiceOverRunning,
              let root = SemanticsRoot.provider?(),
              let view = rootView() else { return }
        let nodes = SemanticsSnapshot.build(from: root).filter { !$0.label.isEmpty || $0.isTextField }
        // Only tell VoiceOver when something it would say differs.
        let key = nodes.map { "\($0.label)|\($0.value)|\($0.isEnabled ?? true)|\($0.isChecked.map(String.init(describing:)) ?? "")|\($0.isFocused ?? false)" }
            .joined(separator: "\n")
        if key == lastKey { return }
        let focus = nodes.map { $0.isFocused ?? false }
        let focusChanged = !lastKey.isEmpty && focus != previousFocus
        lastKey = key
        previousFocus = focus
        let elements = self.elements(for: nodes, in: view)
        view.isAccessibilityElement = false
        view.accessibilityElements = elements
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
        if focusChanged, let f = zip(nodes, elements).first(where: { $0.0.isFocused == true })?.1 {
            UIAccessibility.post(notification: .layoutChanged, argument: f)
        }
    }

    /// One accessibility element per node, with its place on screen (the Flutter view is y down, like UIKit).
    static func elements(for nodes: [SemanticsSnapshotNode], in view: UIView) -> [UIAccessibilityElement] {
        nodes.map { n in
            let e = UIKitAccessibleNode(accessibilityContainer: view)
            e.isAccessibilityElement = true
            e.accessibilityLabel = n.label
            if !n.hint.isEmpty { e.accessibilityHint = n.hint }
            if n.isTextField { e.accessibilityValue = n.value }
            else if let c = n.isChecked ?? n.isToggled { e.accessibilityValue = c ? "1" : "0" }
            e.accessibilityTraits = traits(of: n)
            if let f = n.frame {
                let local = CGRect(x: f.x, y: f.y, width: f.width, height: f.height)
                e.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(local, in: view)
            }
            e.tap = n.tap
            return e
        }
    }

    static func traits(of n: SemanticsSnapshotNode) -> UIAccessibilityTraits {
        var t: UIAccessibilityTraits = []
        if n.isTextField { t.insert(.allowsDirectInteraction) }
        else if n.isHeader { t.insert(.header) }
        else if n.isChecked != nil || n.isToggled != nil { t.insert(.button) }
        else if n.isButton || n.canTap { t.insert(.button) }
        else { t.insert(.staticText) }
        if n.isEnabled == false { t.insert(.notEnabled) }
        if n.isSelected == true || n.isChecked == true || n.isToggled == true { t.insert(.selected) }
        return t
    }
}
#endif
