// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The display settings a person sets in the system, as the app's chrome should follow them: text size,
// increased contrast, bold text. Each platform bridge reads its own setting (iOS: Dynamic Type, Increase
// Contrast, Bold Text; macOS: Increase Contrast) and calls `update`; the app builds its theme from `current`
// and rebuilds when `onChange` fires. Linux has no such setting yet and stays at the defaults.

import Foundation

public struct DisplaySettings: Equatable, Sendable {
    /// 1.0 is the default text size.
    public var textScale: Double
    public var increasedContrast: Bool
    public var boldText: Bool
    public init(textScale: Double = 1, increasedContrast: Bool = false, boldText: Bool = false) {
        self.textScale = textScale; self.increasedContrast = increasedContrast; self.boldText = boldText
    }
    /// The chrome's rows grow with the text; this is only a sanity limit (the largest accessibility size on iOS is about 3.1).
    public static let maxChromeTextScale = 3.0
    /// `textScale` limited: never below 1 (a smaller size is not honoured), never past the sanity limit.
    public var chromeTextScale: Double { min(max(textScale, 1), Self.maxChromeTextScale) }
}

public enum SystemDisplay {
    nonisolated(unsafe) public private(set) static var current = DisplaySettings()
    /// Called on the main thread after `current` changed. The app sets it once, on its root.
    nonisolated(unsafe) public static var onChange: (() -> Void)?

    public static func update(_ s: DisplaySettings) {
        guard s != current else { return }
        current = s
        onChange?()
    }

    public static func resetForTesting() { current = DisplaySettings(); onChange = nil }
}
