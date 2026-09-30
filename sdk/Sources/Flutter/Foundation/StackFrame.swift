// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation

// MARK: - StackFrame

/// A object representation of a frame from a stack trace.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/stack_frame.dart`
/// **Lines:** 10-322
public struct StackFrame: Hashable, CustomStringConvertible, Sendable {
    /// The original source of this stack frame.
    ///
    /// **Dart Source:** `stack_frame.dart:255-256`
    public let source: String

    /// The zero-indexed frame number.
    ///
    /// This value may be -1 to indicate an unknown frame number.
    ///
    /// **Dart Source:** `stack_frame.dart:258-261`
    public let number: Int

    /// The scheme of the package for this frame, e.g. "dart" for
    /// dart:core/errors_patch.dart or "package" for
    /// package:flutter/src/widgets/text.dart.
    ///
    /// The path property refers to the source file.
    ///
    /// **Dart Source:** `stack_frame.dart:263-268`
    public let packageScheme: String

    /// The package for this frame, e.g. "core" for
    /// dart:core/errors_patch.dart or "flutter" for
    /// package:flutter/src/widgets/text.dart.
    ///
    /// **Dart Source:** `stack_frame.dart:270-273`
    public let package: String

    /// The path of the file for this frame, e.g. "errors_patch.dart" for
    /// dart:core/errors_patch.dart or "src/widgets/text.dart" for
    /// package:flutter/src/widgets/text.dart.
    ///
    /// **Dart Source:** `stack_frame.dart:275-278`
    public let packagePath: String

    /// The source line number.
    ///
    /// **Dart Source:** `stack_frame.dart:280-281`
    public let line: Int

    /// The source column number.
    ///
    /// **Dart Source:** `stack_frame.dart:283-284`
    public let column: Int

    /// The class name, if any, for this frame.
    ///
    /// This may be an empty string for top level methods in a library or anonymous closure
    /// methods.
    ///
    /// **Dart Source:** `stack_frame.dart:286-290`
    public let className: String

    /// The method name for this frame.
    ///
    /// This will be an empty string if the stack frame is from the default
    /// constructor.
    ///
    /// **Dart Source:** `stack_frame.dart:292-296`
    public let method: String

    /// Whether or not this was thrown from a constructor.
    ///
    /// **Dart Source:** `stack_frame.dart:298-299`
    public let isConstructor: Bool

    /// Creates a new StackFrame instance.
    ///
    /// The `className` may be the empty string if there is no class (e.g. for a
    /// top level library method).
    ///
    /// **Dart Source:** `stack_frame.dart:23-38`
    public init(
        number: Int,
        column: Int,
        line: Int,
        packageScheme: String,
        package: String,
        packagePath: String,
        className: String = "",
        method: String,
        isConstructor: Bool = false,
        source: String
    ) {
        self.number = number
        self.column = column
        self.line = line
        self.packageScheme = packageScheme
        self.package = package
        self.packagePath = packagePath
        self.className = className
        self.method = method
        self.isConstructor = isConstructor
        self.source = source
    }

    // MARK: - Static Constants

    /// A stack frame representing an asynchronous suspension.
    ///
    /// **Dart Source:** `stack_frame.dart:40-50`
    public static let asynchronousSuspension = StackFrame(
        number: -1,
        column: -1,
        line: -1,
        packageScheme: "",
        package: "",
        packagePath: "",
        className: "",
        method: "asynchronous suspension",
        isConstructor: false,
        source: "<asynchronous suspension>"
    )

    /// A stack frame representing a Dart elided stack overflow frame.
    ///
    /// **Dart Source:** `stack_frame.dart:52-62`
    public static let stackOverFlowElision = StackFrame(
        number: -1,
        column: -1,
        line: -1,
        packageScheme: "",
        package: "",
        packagePath: "",
        className: "",
        method: "...",
        isConstructor: false,
        source: "..."
    )

    // MARK: - Parsing Methods

    /// Parses a list of StackFrames from the current call stack.
    ///
    /// This is the Swift equivalent of `StackTrace.current` in Dart.
    ///
    /// **Dart Source:** `stack_frame.dart:64-69`
    public static func fromCurrentStack() -> [StackFrame] {
        return Thread.callStackSymbols.compactMap { fromStackTraceLine($0) }
    }

    /// Parses a list of StackFrames from a stack trace string.
    ///
    /// **Dart Source:** `stack_frame.dart:71-86`
    public static func fromStackString(_ stack: String) -> [StackFrame] {
        return stack
            .trimmingWhitespace()
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .compactMap { fromStackTraceLine($0) }
    }

    /// Parses a single StackFrame from a line of a stack trace.
    ///
    /// Returns nil if format is not as expected.
    ///
    /// **Dart Source:** `stack_frame.dart:186-253`
    public static func fromStackTraceLine(_ line: String) -> StackFrame? {
        if line == "<asynchronous suspension>" {
            return asynchronousSuspension
        } else if line == "..." {
            return stackOverFlowElision
        }

        // Assert check for package:stack_trace format
        assert(
            line != "===== asynchronous gap ===========================",
            "Got a stack frame from package:stack_trace, where a vm or web frame was expected. " +
            "This can happen if FlutterError.demangleStackTrace was not set in an environment " +
            "that propagates non-standard stack traces to the framework, such as during tests."
        )

        #if os(WASI)
        // The parsers below are NSRegularExpression, the legacy Foundation
        // layer, and there is nothing to parse: the stack is always empty
        // here (Thread.callStackSymbols in WebSupport.swift).
        return nil
        #else
        // Web frames (lines that don't start with '#')
        if !line.hasPrefix("#") {
            return tryParseWebFrame(line)
        }

        // VM frames: #N method (uri:line:column)
        return tryParseVMFrame(line)
        #endif
    }

    #if !os(WASI)

    /// Parses a single StackFrame from a line of a StackTrace (web format).
    ///
    /// Returns nil if format is not as expected.
    ///
    /// **Dart Source:** `stack_frame.dart:91-99`
    private static func tryParseWebFrame(_ line: String) -> StackFrame? {
        // dart2wasm doesn't emit stack frames in the same way DDC does, so we need
        // to do the less clever non-debug path here when compiled to wasm.
        // Note: In Swift, kIsWasm is always false, so we check kDebugMode directly.
        if kDebugMode && !kIsWasm {
            return tryParseWebDebugFrame(line)
        } else {
            return tryParseWebNonDebugFrame(line)
        }
    }

    /// Regex pattern for web non-debug frames.
    ///
    /// **Dart Source:** `stack_frame.dart:146`
    private static let webNonDebugFramePattern = try! NSRegularExpression(
        pattern: #"^\s*at ([^\s]+).*$"#,
        options: []
    )

    /// Parses a single StackFrame from a line of a StackTrace (web debug format).
    ///
    /// Returns nil if format is not as expected.
    ///
    /// **Dart Source:** `stack_frame.dart:104-140`
    private static func tryParseWebDebugFrame(_ line: String) -> StackFrame? {
        // This RegExp is only partially correct for flutter run/test differences.
        // https://github.com/flutter/flutter/issues/52685
        let hasPackage = line.hasPrefix("package")
        let pattern = hasPackage
            ? #"^(package.+) (\d+):(\d+)\s+(.+)$"#
            : #"^(.+) (\d+):(\d+)\s+(.+)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }

        var package = "<unknown>"
        var packageScheme = "<unknown>"
        var packagePath = "<unknown>"

        if hasPackage {
            packageScheme = "package"
            if let group1Range = Range(match.range(at: 1), in: line) {
                let packageUriString = String(line[group1Range])
                if let packageUri = URL(string: packageUriString),
                   let firstPathComponent = packageUri.pathComponents.dropFirst().first {
                    package = firstPathComponent
                    // Only the first occurrence: the package name may recur.
                    packagePath = packageUri.path.removingFirst("\(firstPathComponent)/")
                }
            }
        }

        guard let group2Range = Range(match.range(at: 2), in: line),
              let group3Range = Range(match.range(at: 3), in: line),
              let group4Range = Range(match.range(at: 4), in: line),
              let lineNum = Int(line[group2Range]),
              let columnNum = Int(line[group3Range]) else {
            return nil
        }

        return StackFrame(
            number: -1,
            column: columnNum,
            line: lineNum,
            packageScheme: packageScheme,
            package: package,
            packagePath: packagePath,
            className: "<unknown>",
            method: String(line[group4Range]),
            source: line
        )
    }

    /// Parses a single StackFrame from a line of a StackTrace (web non-debug format).
    ///
    /// Non-debug builds do not point to dart code but compiled JavaScript, so
    /// line numbers are meaningless. We only attempt to parse the class and
    /// method name, which is more or less readable in profile builds, and
    /// minified in release builds.
    ///
    /// **Dart Source:** `stack_frame.dart:148-184`
    private static func tryParseWebNonDebugFrame(_ line: String) -> StackFrame? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = webNonDebugFramePattern.firstMatch(in: line, options: [], range: range) else {
            // On the Web in non-debug builds the stack trace includes the exception
            // message that precedes the stack trace itself. Instead of crashing when
            // a line is not recognized as a stack frame, we return nil.
            return nil
        }

        guard let group1Range = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let classAndMethod = String(line[group1Range]).split(separator: ".")
        let className: String
        let method: String

        if classAndMethod.count > 1 {
            className = String(classAndMethod.first!)
            method = classAndMethod.dropFirst().joined(separator: ".")
        } else {
            className = "<unknown>"
            method = classAndMethod.first.map { String($0) } ?? ""
        }

        return StackFrame(
            number: -1,
            column: -1,
            line: -1,
            packageScheme: "<unknown>",
            package: "<unknown>",
            packagePath: "<unknown>",
            className: className,
            method: method,
            source: line
        )
    }

    /// Parses a VM-style stack frame line.
    ///
    /// Format: #N method (uri:line:column)
    ///
    /// **Dart Source:** `stack_frame.dart:208-252`
    private static func tryParseVMFrame(_ line: String) -> StackFrame? {
        // Pattern: #N method (uri:line:column)
        let pattern = #"^#(\d+) +(.+) \((.+?):?(\d+)?:?(\d+)?\)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            assertionFailure("Expected \(line) to match \(pattern).")
            return nil
        }

        // Extract frame number
        guard let group1Range = Range(match.range(at: 1), in: line),
              let frameNumber = Int(line[group1Range]) else {
            return nil
        }

        // Extract method (group 2)
        guard let group2Range = Range(match.range(at: 2), in: line) else {
            return nil
        }

        // Extract URI (group 3)
        guard let group3Range = Range(match.range(at: 3), in: line) else {
            return nil
        }

        var isConstructor = false
        var className = ""
        var method = String(line[group2Range]).replacingAll(".<anonymous closure>", with: "")

        if method.hasPrefix("new") {
            let methodParts = method.split(separator: " ")
            // Sometimes a web frame will only read "new" and have no class name.
            className = methodParts.count > 1 ? String(method.split(separator: " ")[1]) : "<unknown>"
            method = ""
            if className.contains(".") {
                let parts = className.split(separator: ".")
                className = String(parts[0])
                method = String(parts[1])
            }
            isConstructor = true
        } else if method.contains(".") {
            let parts = method.split(separator: ".")
            className = String(parts[0])
            method = String(parts[1])
        }

        // Parse URI for package info
        let uriString = String(line[group3Range])
        var package = "<unknown>"
        var packagePath = uriString
        var packageScheme = ""

        if let packageUri = URL(string: uriString) {
            packageScheme = packageUri.scheme ?? ""
            if packageScheme == "dart" || packageScheme == "package" {
                let pathComponents = packageUri.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0) }
                if !pathComponents.isEmpty {
                    package = pathComponents[0]
                    packagePath = packageUri.path.removingFirst("\(pathComponents[0])/")
                }
            }
        }

        // Extract line number (group 4, optional)
        var lineNum = -1
        if match.range(at: 4).location != NSNotFound,
           let group4Range = Range(match.range(at: 4), in: line),
           let parsed = Int(line[group4Range]) {
            lineNum = parsed
        }

        // Extract column number (group 5, optional)
        var columnNum = -1
        if match.range(at: 5).location != NSNotFound,
           let group5Range = Range(match.range(at: 5), in: line),
           let parsed = Int(line[group5Range]) {
            columnNum = parsed
        }

        return StackFrame(
            number: frameNumber,
            column: columnNum,
            line: lineNum,
            packageScheme: packageScheme,
            package: package,
            packagePath: packagePath,
            className: className,
            method: method,
            isConstructor: isConstructor,
            source: line
        )
    }

    // MARK: - Hashable

    /// **Dart Source:** `stack_frame.dart:301-302`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(number)
        hasher.combine(package)
        hasher.combine(line)
        hasher.combine(column)
        hasher.combine(className)
        hasher.combine(method)
        hasher.combine(source)
    }

    // MARK: - Equatable

    /// **Dart Source:** `stack_frame.dart:304-317`
    #endif

    public static func == (lhs: StackFrame, rhs: StackFrame) -> Bool {
        return lhs.number == rhs.number &&
            lhs.package == rhs.package &&
            lhs.line == rhs.line &&
            lhs.column == rhs.column &&
            lhs.className == rhs.className &&
            lhs.method == rhs.method &&
            lhs.source == rhs.source
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `stack_frame.dart:319-321`
    public var description: String {
        return "\(objectRuntimeType(self, "StackFrame"))(#\(number), \(packageScheme):\(package)/\(packagePath):\(line):\(column), className: \(className), method: \(method))"
    }
}
