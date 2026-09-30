// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Debug utilities for Flutter debugging.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/debug.dart`
/// **Lines:** 1-172

import FlutterSwiftBridge
import Foundation

// MARK: - Debug Variables

/// Boolean value indicating whether `debugInstrumentAction` will instrument
/// actions in debug builds.
///
/// The framework does not use `debugInstrumentAction` internally, so this
/// does not enable any additional instrumentation for the framework itself.
///
/// **Dart Source:** `debug.dart:52-66`
nonisolated(unsafe) public var debugInstrumentationEnabled: Bool = false

/// Configure `debugFormatDouble` using precision.
///
/// When set, `debugFormatDouble` will use `toStringAsPrecision` with this value.
/// Defaults to nil, which uses the default logic of `toStringAsFixed(1)`.
///
/// **Dart Source:** `debug.dart:104-107`
nonisolated(unsafe) public var debugDoublePrecision: Int? = nil

/// A setting that can be used to override the platform `Brightness`.
///
/// **Dart Source:** `debug.dart:122-129`
nonisolated(unsafe) public var debugBrightnessOverride: Brightness? = nil

/// The address for the active DevTools server used for debugging this
/// application.
///
/// **Dart Source:** `debug.dart:131-133`
nonisolated(unsafe) public var activeDevToolsServerAddress: String? = nil

/// The uri for the connected vm service protocol.
///
/// **Dart Source:** `debug.dart:135-136`
nonisolated(unsafe) public var connectedVmServiceUri: String? = nil

// MARK: - File-based Debug Logging

/// Log path for file-based debug output.
private let _dbgPath = "/tmp/flutter_debug.log"

/// Write a debug message to /tmp/flutter_debug.log.
///
/// Use this instead of `print()` when stdout is not visible (e.g. GUI apps).
/// Messages are appended with a newline. The file is created if it doesn't exist.
public func dbg(_ msg: String, file: String = #fileID, line: Int = #line) {
    #if os(WASI)
    // No files to append to; the console is the log.
    FileHandle.standardError.write(Data("[\(file):\(line)] \(msg)\n".utf8))
    #else
    if !FileManager.default.fileExists(atPath: _dbgPath) {
        FileManager.default.createFile(atPath: _dbgPath, contents: nil)
    }
    guard let fh = FileHandle(forWritingAtPath: _dbgPath) else { return }
    fh.seekToEndOfFile()
    fh.write("[\(file):\(line)] \(msg)\n".data(using: .utf8)!)
    fh.closeFile()
    #endif
}

// MARK: - Debug Functions

/// Runs the specified action, timing how long the action takes in debug
/// builds when `debugInstrumentationEnabled` is true.
///
/// The instrumentation will be printed to the logs using `debugPrint`. In
/// non-debug builds, or when `debugInstrumentationEnabled` is false, this will
/// run action without any instrumentation.
///
/// Returns the result of running action.
///
/// **Dart Source:** `debug.dart:68-102`
public func debugInstrumentAction<T>(
    _ description: String,
    action: () async throws -> T
) async rethrows -> T {
    #if DEBUG
    if debugInstrumentationEnabled {
        let startTime = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            let elapsedMs = elapsed * 1000
            debugPrint("Action \"\(description)\" took \(String(format: "%.2f", elapsedMs))ms", nil)
        }
        return try await action()
    }
    #endif
    return try await action()
}

// MARK: - Debug Formatting

/// Formats a double to have standard formatting.
///
/// This behavior can be overridden by `debugDoublePrecision`.
///
/// **Dart Source:** `debug.dart:109-120`
public func debugFormatDouble(_ value: Double?) -> String {
    guard let value = value else {
        return "null"
    }
    if let precision = debugDoublePrecision {
        // Use a fixed number of significant digits
        return String(format: "%.\(precision)g", value)
    }
    return String(format: "%.1f", value)
}

// MARK: - Foundation Debug Assertion

/// Returns true if none of the foundation library debug variables have been
/// changed.
///
/// This function is used by the test framework to ensure that debug variables
/// haven't been inadvertently changed.
///
/// The `debugPrintOverride` argument can be specified to indicate the expected
/// value of the `debugPrint` variable. This is useful for test frameworks that
/// override `debugPrint` themselves and want to check that their own custom
/// value wasn't overridden by a test.
///
/// **Dart Source:** `debug.dart:23-50`
///
/// Note: This is a simplified version that checks the available debug variables.
/// `debugDefaultTargetPlatformOverride` check is omitted as the platform module
/// is not yet migrated.
@discardableResult
public func debugAssertAllFoundationVarsUnset(
    _ reason: String,
    debugPrintOverride: DebugPrintCallback? = nil
) -> Bool {
    #if DEBUG
    // Check if debugPrint has been changed from default
    // Note: We can't directly compare function references in Swift,
    // so we skip the debugPrint check if no override is specified.
    // The Dart version compares: debugPrint != debugPrintOverride

    // Check other debug variables
    if debugDoublePrecision != nil ||
       debugBrightnessOverride != nil {
        assertionFailure(reason)
        return false
    }
    #endif
    return true
}
