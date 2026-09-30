// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Print utilities for Flutter debugging.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 1-216

import Foundation

// MARK: - DebugPrintCallback

/// Signature for `debugPrint` implementations.
///
/// If a `wrapWidth` is provided, each line of the `message` is word-wrapped to
/// that width. (Lines may be separated by newline characters, as in '\n'.)
///
/// By default, this function very crudely attempts to throttle the rate at
/// which messages are sent to avoid data loss on Android. This means that
/// interleaving calls to this function (directly or indirectly via, e.g.,
/// `debugDumpRenderTree` or `debugDumpApp`) and to the standard `print` method can
/// result in out-of-order messages in the logs.
///
/// The implementation of this function can be replaced by setting the
/// `debugPrint` variable to a new implementation that matches the
/// `DebugPrintCallback` signature. For example, flutter_test does this.
///
/// The default value is `debugPrintThrottled`. For a version that acts
/// identically but does not throttle, use `debugPrintSynchronously`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 15-32
public typealias DebugPrintCallback = (_ message: String?, _ wrapWidth: Int?) -> Void

// MARK: - debugPrint Variable

/// Prints a message to the console, which you can access using the "flutter"
/// tool's "logs" command ("flutter logs").
///
/// The `debugPrint` function logs to console even in release mode.
/// As per convention, calls to `debugPrint` should be within a debug mode check or an assert.
///
/// DIFFERENCE FROM DART: Uses nonisolated(unsafe) for Swift 6 concurrency.
///
/// See also:
///
///   * `DebugPrintCallback`, for function parameters and usage details.
///   * `debugPrintThrottled`, the default implementation.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 34-49
nonisolated(unsafe) public var debugPrint: DebugPrintCallback = debugPrintThrottled

// MARK: - Private State
// NOTE: WordWrapParseMode is already defined in Diagnostics.swift and is reused here.

/// Number of characters printed since last reset.
///
/// DIFFERENCE FROM DART: Uses nonisolated(unsafe) for Swift 6 concurrency.
/// The throttling state is accessed on the main queue to avoid race conditions.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 84
nonisolated(unsafe) private var _debugPrintedCharacters: Int = 0

/// Maximum capacity before throttling kicks in.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 85
private let _kDebugPrintCapacity: Int = 12 * 1024

/// Pause time between throttled print batches.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 86
private let _kDebugPrintPauseTime: TimeInterval = 1.0

/// Buffer of lines waiting to be printed.
///
/// DIFFERENCE FROM DART: Uses nonisolated(unsafe) for Swift 6 concurrency.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 87
nonisolated(unsafe) private var _debugPrintBuffer: [String] = []

/// Time of last print operation for throttle tracking.
///
/// Replaces Dart's `Stopwatch` with a simple `Date` for elapsed time tracking.
///
/// DIFFERENCE FROM DART: Uses nonisolated(unsafe) for Swift 6 concurrency.
/// Uses Date instead of Stopwatch for elapsed time tracking.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 88
nonisolated(unsafe) private var _debugPrintLastTime: Date?

/// Completion handlers waiting for print buffer to drain.
///
/// Replaces Dart's `Completer<void>?` with a list of callbacks.
///
/// DIFFERENCE FROM DART: Uses nonisolated(unsafe) for Swift 6 concurrency.
/// Uses callback list instead of Completer.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 90
nonisolated(unsafe) private var _debugPrintCompletionHandlers: [() -> Void] = []

/// Whether a throttled print task is currently scheduled.
///
/// DIFFERENCE FROM DART: Uses nonisolated(unsafe) for Swift 6 concurrency.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 91
nonisolated(unsafe) private var _debugPrintScheduled: Bool = false

/// The list-style indentation prefix of `message`, if it has one: leading
/// spaces, then optionally a bullet (`- `, `+ `, `* `) or an ordinal
/// (`1. `, `2) `, `3: `).
///
/// DIFFERENCE FROM DART: Dart's `_indentPattern` is the regex
/// `/^ *(?:[-+*] |[0-9]+[.):] )?/`. Spelled out as character tests instead.
/// REASON: one regex literal links the Swift regex engine — 1.2 MB in the
/// web build (docs/plans/wasm-size.md) — for a prefix that is ten lines to
/// scan by hand.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 121
private func _indentPrefix(of message: String) -> Substring {
    let chars = message.utf8
    var i = chars.startIndex
    while i < chars.endIndex, chars[i] == UInt8(ascii: " ") { i = chars.index(after: i) }
    let afterSpaces = i
    if i < chars.endIndex, "-+*".utf8.contains(chars[i]) {
        let next = chars.index(after: i)
        if next < chars.endIndex, chars[next] == UInt8(ascii: " ") {
            return message[..<chars.index(after: next)]
        }
    } else {
        while i < chars.endIndex, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(chars[i]) {
            i = chars.index(after: i)
        }
        if i > afterSpaces, i < chars.endIndex, ".):".utf8.contains(chars[i]) {
            let next = chars.index(after: i)
            if next < chars.endIndex, chars[next] == UInt8(ascii: " ") {
                return message[..<chars.index(after: next)]
            }
        }
    }
    return message[..<afterSpaces]
}

// MARK: - Word Wrap Parse Mode (Private)

/// Internal enum for word wrap parsing state machine.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 123
private enum _WordWrapParseMode {
    case inSpace
    case inWord
    case atBreak
}

// MARK: - Throttling Task (Private)

/// Internal task handler for throttled debug printing.
///
/// This function processes the print buffer, respecting the capacity limit
/// and scheduling delayed continuation when the buffer is not empty.
///
/// DIFFERENCE FROM DART: Uses DispatchQueue.main.asyncAfter instead of Timer.
/// Uses Date/timeIntervalSince instead of Stopwatch for elapsed time tracking.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 92-114
private func _debugPrintTask() {
    _debugPrintScheduled = false

    // Check if enough time has passed to reset the character count
    // This mimics Dart's Stopwatch.elapsed > _kDebugPrintPauseTime behavior
    if let lastTime = _debugPrintLastTime,
       Date().timeIntervalSince(lastTime) > _kDebugPrintPauseTime {
        _debugPrintLastTime = nil
        _debugPrintedCharacters = 0
    }

    // Print lines from the buffer up to the capacity limit
    while _debugPrintedCharacters < _kDebugPrintCapacity && !_debugPrintBuffer.isEmpty {
        let line = _debugPrintBuffer.removeFirst()
        _debugPrintedCharacters += line.count  // TODO: Use UTF-8 byte length instead
        Swift.print(line)
    }

    if !_debugPrintBuffer.isEmpty {
        // More lines to print; schedule a delayed continuation
        _debugPrintScheduled = true
        _debugPrintedCharacters = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + _kDebugPrintPauseTime) {
            _debugPrintTask()
        }
    } else {
        // Buffer is now empty; record the time for future throttle reset
        _debugPrintLastTime = Date()
        // Call all completion handlers and clear the list
        let handlers = _debugPrintCompletionHandlers
        _debugPrintCompletionHandlers.removeAll()
        for handler in handlers {
            handler()
        }
    }
}

// MARK: - debugPrintThrottled

/// Implementation of `debugPrint` that throttles messages. This avoids dropping
/// messages on platforms that rate-limit their logging (for example, Android).
///
/// If `wrapWidth` is not nil, the message is wrapped using `debugWordWrap`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 66-82
public func debugPrintThrottled(_ message: String?, wrapWidth: Int? = nil) {
    // Split message by newlines, defaulting to ["null"] if message is nil
    let messageLines = message?.split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0) } ?? ["null"]

    if let wrapWidth = wrapWidth {
        // Word-wrap each line and add to buffer
        for line in messageLines {
            _debugPrintBuffer.append(contentsOf: debugWordWrap(line, wrapWidth))
        }
    } else {
        // Add lines directly to buffer
        _debugPrintBuffer.append(contentsOf: messageLines)
    }

    // Trigger the print task if not already scheduled
    if !_debugPrintScheduled {
        _debugPrintTask()
    }
}

// MARK: - debugPrintSynchronously

/// Alternative implementation of `debugPrint` that does not throttle.
/// Used by tests.
///
/// If both `message` and `wrapWidth` are provided, the message is word-wrapped
/// at the given width. Each line is wrapped using `debugWordWrap`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 51-64
public func debugPrintSynchronously(_ message: String?, wrapWidth: Int? = nil) {
    if let message = message, let wrapWidth = wrapWidth {
        // Split message by newlines, wrap each line, then join with newlines
        let wrappedLines = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { line in debugWordWrap(String(line), wrapWidth) }
            .joined(separator: "\n")
        Swift.print(wrappedLines)
    } else {
        Swift.print(message ?? "null")
    }
}

// MARK: - debugPrintDone

/// Calls the provided completion handler when there is no longer any buffered
/// content being printed by `debugPrintThrottled` (which is the default
/// implementation for `debugPrint`, which is used to report errors to the console).
///
/// If the buffer is already empty and no print task is scheduled, the completion
/// handler is called immediately. Otherwise, it will be called when all buffered
/// content has been printed.
///
/// DIFFERENCE FROM DART: Uses a callback-based API instead of returning a Future.
/// Use the async version `debugPrintDone()` for await-based code.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 116-119
public func debugPrintDone(completion: @escaping () -> Void) {
    if _debugPrintBuffer.isEmpty && !_debugPrintScheduled {
        completion()
    } else {
        _debugPrintCompletionHandlers.append(completion)
    }
}

/// Awaits until there is no longer any buffered content being printed by
/// `debugPrintThrottled` (which is the default implementation for `debugPrint`,
/// which is used to report errors to the console).
///
/// If the buffer is already empty and no print task is scheduled, this returns
/// immediately.
///
/// DIFFERENCE FROM DART: Uses Swift's async/await instead of Dart's Future.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 116-119
public func debugPrintDone() async {
    if _debugPrintBuffer.isEmpty && !_debugPrintScheduled {
        return
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        _debugPrintCompletionHandlers.append {
            continuation.resume()
        }
    }
}

// MARK: - debugWordWrap

/// Wraps the given string at the given width.
///
/// The `message` should not contain newlines (`\n`, U+000A). Strings that may
/// contain newlines should be split before being wrapped.
///
/// Wrapping occurs at space characters (U+0020). Lines that start with an
/// octothorpe ("#", U+0023) are not wrapped (so for example, Dart stack traces
/// won't be wrapped).
///
/// Subsequent lines attempt to duplicate the indentation of the first line, for
/// example if the first line starts with multiple spaces. In addition, if a
/// `wrapIndent` argument is provided, each line after the first is prefixed by
/// that string.
///
/// This is not suitable for use with arbitrary Unicode text. For example, it
/// doesn't implement UAX #14, can't handle ideographic text, doesn't hyphenate,
/// and so forth. It is only intended for formatting error messages.
///
/// The default `debugPrint` implementation uses this for its line wrapping.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/print.dart`
/// **Lines:** 125-215
public func debugWordWrap(_ message: String, _ width: Int, wrapIndent: String = "") -> [String] {
    // Early return: if message is short or starts with '#' (after trimming leading spaces)
    let trimmed = message.drop(while: { $0 == " " })
    if message.count < width || (trimmed.first == "#") {
        return [message]
    }

    var wrapped: [String] = []

    // Match the indent pattern at the start of the message
    let matchedPrefix = _indentPrefix(of: message)
    let prefix = wrapIndent + String(repeating: " ", count: matchedPrefix.count)

    var start = message.startIndex
    var startForLengthCalculations = message.startIndex
    var addPrefix = false
    var index = message.index(message.startIndex, offsetBy: min(prefix.count, message.count), limitedBy: message.endIndex) ?? message.endIndex
    var mode = _WordWrapParseMode.inSpace
    var lastWordStart = index
    var lastWordEnd: String.Index? = nil

    while true {
        switch mode {
        case .inSpace:
            // At start of break point (or start of line); can't break until next break
            while index < message.endIndex && message[index] == " " {
                index = message.index(after: index)
            }
            lastWordStart = index
            mode = .inWord

        case .inWord:
            // Looking for a good break point
            while index < message.endIndex && message[index] != " " {
                index = message.index(after: index)
            }
            mode = .atBreak

        case .atBreak:
            // At start of break point
            let currentLength = message.distance(from: startForLengthCalculations, to: index)
            let atEnd = index == message.endIndex

            if currentLength > width || atEnd {
                // We are over the width line, so break
                if currentLength <= width || lastWordEnd == nil {
                    // We should use this point, because either it doesn't actually go over the
                    // end (last line), or it does, but there was no earlier break point
                    lastWordEnd = index
                }

                let lineEnd = lastWordEnd!
                if addPrefix {
                    wrapped.append(prefix + String(message[start..<lineEnd]))
                } else {
                    wrapped.append(String(message[start..<lineEnd]))
                    addPrefix = true
                }

                if lineEnd >= message.endIndex {
                    return wrapped
                }

                // Just yielded a line
                if lineEnd == index {
                    // We broke at current position
                    // Eat all the spaces, then set our start point
                    while index < message.endIndex && message[index] == " " {
                        index = message.index(after: index)
                    }
                    start = index
                    mode = .inWord
                } else {
                    // We broke at the previous break point, and we're at the start of a new one
                    assert(lastWordStart > lineEnd)
                    start = lastWordStart
                    mode = .atBreak
                }

                // Calculate the new startForLengthCalculations by offsetting backward by prefix length
                let prefixLength = prefix.count
                if let newStart = message.index(start, offsetBy: -prefixLength, limitedBy: message.startIndex) {
                    startForLengthCalculations = newStart
                } else {
                    startForLengthCalculations = message.startIndex
                }

                assert(addPrefix)
                lastWordEnd = nil
            } else {
                // Save this break point, we're not yet over the line width
                lastWordEnd = index
                // Skip to the end of this break point
                mode = .inSpace
            }
        }
    }
}
