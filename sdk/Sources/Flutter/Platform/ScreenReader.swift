// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What the app says to a screen reader when something changes that has no focus move of its own:
// "Bold on", "Selected B3", "Slide 4 of 9", "Dialog opened". The app calls `ScreenReader.announce`; each
// platform bridge (AT-SPI on Linux, VoiceOver on macOS and iOS) installs a `sink` that hands the text to
// its own announcement call. With no sink (no screen reader running) the call costs nothing.

import Foundation

public enum ScreenReader {
    public enum Priority: Int, Sendable { case polite = 0, assertive = 1 }

    /// Set by a platform bridge. Called on the thread that announced.
    nonisolated(unsafe) public static var sink: ((String, Priority) -> Void)?
    /// Tests turn this on to read what was said; every announcement is appended.
    nonisolated(unsafe) public static var recorded: [String]?
    nonisolated(unsafe) private static var lastText = ""
    nonisolated(unsafe) private static var lastTime = Date.distantPast

    /// True when something would hear an announcement (a bridge sink, or a test capturing): callers skip building text otherwise.
    public static var isListening: Bool { sink != nil || recorded != nil }

    /// Says `text`. The same text twice within a quarter of a second is said once (a key held down).
    public static func announce(_ text: String, priority: Priority = .polite) {
        let t = text
        if t.allSatisfy({ $0 == " " || $0 == "\n" || $0 == "\t" }) { return }
        let now = Date()
        if t == lastText && now.timeIntervalSince(lastTime) < 0.25 { return }
        lastText = t; lastTime = now
        recorded?.append(t)
        sink?(t, priority)
    }

    public static func resetForTesting() { sink = nil; recorded = nil; lastText = ""; lastTime = .distantPast }
}
