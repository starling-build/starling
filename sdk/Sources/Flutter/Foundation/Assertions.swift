// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Error handling and assertions library for the Flutter framework.
///
/// This library provides infrastructure for error handling, including:
/// - `FlutterError`: The main error class for Flutter-specific errors
/// - `FlutterErrorDetails`: Details about caught exceptions
/// - Error diagnostic classes: `ErrorDescription`, `ErrorSummary`, `ErrorHint`, `ErrorSpacer`
/// - Stack filtering utilities for cleaner error messages
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`

import Foundation

// MARK: - Type Aliases

/// Signature for `FlutterError.onError` handler.
///
/// **Dart Source:** `assertions.dart:30-31`
public typealias FlutterExceptionHandler = (FlutterErrorDetails) -> Void

/// Signature for `DiagnosticPropertiesBuilder` transformer.
///
/// **Dart Source:** `assertions.dart:33-35`
public typealias DiagnosticPropertiesTransformer = ([any DiagnosticsNodeProtocol]) -> [any DiagnosticsNodeProtocol]

/// Signature for `FlutterErrorDetails.informationCollector` callback
/// and other callbacks that collect information describing an error.
///
/// **Dart Source:** `assertions.dart:37-39`
public typealias InformationCollector = () -> [any DiagnosticsNodeProtocol]

/// Signature for a function that demangles stack traces into a format
/// that can be parsed by `StackFrame`.
///
/// **Dart Source:** `assertions.dart:41-47`
public typealias StackTraceDemangler = (String) -> String

// MARK: - PartialStackFrame

/// Partial information from a stack frame for stack filtering purposes.
///
/// See also:
///
///  * `RepetitiveStackFrameFilter`, which uses this class to compare against `StackFrame`s.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 49-97
public struct PartialStackFrame: Sendable, Hashable {
    /// Creates a new `PartialStackFrame` instance.
    ///
    /// **Dart Source:** `assertions.dart:56-57`
    public init(package: String, className: String, method: String) {
        self.package = package
        self.className = className
        self.method = method
    }

    /// An `<asynchronous suspension>` line in a stack trace.
    ///
    /// **Dart Source:** `assertions.dart:59-64`
    public static let asynchronousSuspension = PartialStackFrame(
        package: "",
        className: "",
        method: "asynchronous suspension"
    )

    /// The package to match, e.g. `package:flutter/src/foundation/assertions.dart`,
    /// or `dart:ui/window.dart`.
    ///
    /// In Swift, we use simple string matching instead of Dart's Pattern type.
    ///
    /// **Dart Source:** `assertions.dart:66-68`
    public let package: String

    /// The class name for the method.
    ///
    /// On web, this is ignored, since class names are not available.
    /// On all platforms, top level methods should use the empty string.
    ///
    /// **Dart Source:** `assertions.dart:70-75`
    public let className: String

    /// The method name for this frame line.
    ///
    /// On web, private methods are wrapped with `[]`.
    ///
    /// **Dart Source:** `assertions.dart:77-80`
    public let method: String

    /// Tests whether the `StackFrame` matches the information in this
    /// `PartialStackFrame`.
    ///
    /// **Dart Source:** `assertions.dart:82-96`
    public func matches(_ stackFrame: StackFrame) -> Bool {
        let stackFramePackage = "\(stackFrame.packageScheme):\(stackFrame.package)/\(stackFrame.packagePath)"

        // In Swift/native environment, kIsWeb is always false
        if kIsWeb {
            return stackFramePackage.contains(package) &&
                stackFrame.method == (method.hasPrefix("_") ? "[\(method)]" : method)
        }
        return stackFramePackage.contains(package) &&
            stackFrame.method == method &&
            stackFrame.className == className
    }
}

// MARK: - StackFilter Protocol

/// A class that filters stack frames for additional filtering on
/// `FlutterError.defaultStackFilter`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 99-111
public protocol StackFilter: Sendable {
    /// Filters the list of `StackFrame`s by updating corresponding indices in
    /// `reasons`.
    ///
    /// To elide a frame or number of frames, set the string.
    ///
    /// **Dart Source:** `assertions.dart:106-110`
    func filter(stackFrames: inout [StackFrame], reasons: inout [String?])
}

// MARK: - RepetitiveStackFrameFilter

/// A `StackFilter` that filters based on repeating lists of
/// `PartialStackFrame`s.
///
/// See also:
///
///   * `FlutterError.addDefaultStackFilter`, a method to register additional
///     stack filters for `FlutterError.defaultStackFilter`.
///   * `StackFrame`, a class that can help with parsing stack frames.
///   * `PartialStackFrame`, a class that helps match partial method information
///     to a stack frame.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 113-164
public struct RepetitiveStackFrameFilter: StackFilter {
    /// Creates a new RepetitiveStackFrameFilter. All parameters are required.
    ///
    /// **Dart Source:** `assertions.dart:124-126`
    public init(frames: [PartialStackFrame], replacement: String) {
        self.frames = frames
        self.replacement = replacement
    }

    /// The shape of this repetitive stack pattern.
    ///
    /// **Dart Source:** `assertions.dart:128-129`
    public let frames: [PartialStackFrame]

    /// The number of frames in this pattern.
    ///
    /// **Dart Source:** `assertions.dart:131-132`
    public var numFrames: Int { frames.count }

    /// The string to replace the frames with.
    ///
    /// If the same replacement string is used multiple times in a row, the
    /// `FlutterError.defaultStackFilter` will insert a repeat count after this
    /// line rather than repeating it.
    ///
    /// **Dart Source:** `assertions.dart:134-139`
    public let replacement: String

    /// **Dart Source:** `assertions.dart:141`
    private var replacements: [String] {
        Array(repeating: replacement, count: numFrames)
    }

    /// **Dart Source:** `assertions.dart:143-151`
    public func filter(stackFrames: inout [StackFrame], reasons: inout [String?]) {
        var index = 0
        while index < stackFrames.count - numFrames {
            let framesToCheck = Array(stackFrames[index..<(index + numFrames)])
            if matchesFrames(framesToCheck) {
                for i in 0..<numFrames {
                    reasons[index + i] = replacements[i]
                }
                index += numFrames
            } else {
                index += 1
            }
        }
    }

    /// **Dart Source:** `assertions.dart:153-163`
    private func matchesFrames(_ stackFrames: [StackFrame]) -> Bool {
        if stackFrames.count < numFrames {
            return false
        }
        for index in 0..<stackFrames.count {
            if !frames[index].matches(stackFrames[index]) {
                return false
            }
        }
        return true
    }
}

// MARK: - ErrorDiagnostic (Internal Base Class)

/// Internal base class for error diagnostic classes.
///
/// This constructor provides a reliable hook for a kernel transformer to find
/// error messages that need to be rewritten to include object references for
/// interactive display of errors.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 166-238
open class ErrorDiagnostic: DiagnosticsProperty<[Any]> {
    /// Creates an error diagnostic with the given message.
    ///
    /// **Dart Source:** `assertions.dart:170-182`
    public init(
        _ message: String,
        style: DiagnosticsTreeStyle = .flat,
        level: DiagnosticLevel = .info
    ) {
        self._messageValue = [message]
        super.init(
            nil,
            [message] as [Any]?,
            showName: false,
            showSeparator: false,
            defaultValue: kNoDefaultValue,
            style: style,
            level: level
        )
    }

    /// Creates an error diagnostic from parts.
    ///
    /// In debug builds, a kernel transformer rewrites calls to the default
    /// constructors for `ErrorSummary`, `ErrorDescription`, and `ErrorHint` to use
    /// this constructor.
    ///
    /// **Dart Source:** `assertions.dart:209-221`
    public init(
        fromParts messageParts: [Any],
        style: DiagnosticsTreeStyle = .flat,
        level: DiagnosticLevel = .info
    ) {
        self._messageValue = messageParts
        super.init(
            nil,
            messageParts,
            showName: false,
            showSeparator: false,
            defaultValue: kNoDefaultValue,
            style: style,
            level: level
        )
    }

    private let _messageValue: [Any]

    /// Returns the message value.
    ///
    /// **Dart Source:** `assertions.dart:231-232`
    public var messageValue: [Any] { _messageValue }

    /// **Dart Source:** `assertions.dart:223-229`
    public override func toString(parentConfiguration: TextTreeConfiguration?, minLevel: DiagnosticLevel) -> String {
        return valueToString(parentConfiguration: parentConfiguration)
    }

    /// **Dart Source:** `assertions.dart:234-237`
    public override func valueToString(parentConfiguration: TextTreeConfiguration?) -> String {
        return _messageValue.map { "\($0)" }.joined()
    }
}

// MARK: - ErrorDescription

/// An explanation of the problem and its cause, any information that may help
/// track down the problem, background information, etc.
///
/// Use `ErrorDescription` for any part of an error message where neither
/// `ErrorSummary` or `ErrorHint` is appropriate.
///
/// In debug builds, values interpolated into the `message` are
/// expanded and placed into `value`, which is of type `[Any]`.
/// This allows IDEs to examine values interpolated into error messages.
///
/// See also:
///
///  * `ErrorSummary`, which provides a short (one line) description of the
///    problem that was detected.
///  * `ErrorHint`, which provides specific, non-obvious advice that may be
///    applicable.
///  * `ErrorSpacer`, which renders as a blank line.
///  * `FlutterError`, which is the most common place to use an
///    `ErrorDescription`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 240-275
public class ErrorDescription: ErrorDiagnostic {
    /// Creates an error description with the given message.
    ///
    /// **Dart Source:** `assertions.dart:259-269`
    public override init(_ message: String, style: DiagnosticsTreeStyle = .flat, level: DiagnosticLevel = .info) {
        super.init(message, style: style, level: .info)
    }

    /// Creates an error description from message parts.
    ///
    /// **Dart Source:** `assertions.dart:271-274`
    public init(fromParts messageParts: [Any]) {
        super.init(fromParts: messageParts, style: .flat, level: .info)
    }
}

// MARK: - ErrorSummary

/// A short (one line) description of the problem that was detected.
///
/// Error summaries from the same source location should have little variance,
/// so that they can be recognized as related. For example, they shouldn't
/// include hash codes.
///
/// A `FlutterError` must start with an `ErrorSummary` and may not contain
/// multiple summaries.
///
/// In debug builds, values interpolated into the `message` are
/// expanded and placed into `value`, which is of type `[Any]`.
/// This allows IDEs to examine values interpolated into error messages.
///
/// See also:
///
///  * `ErrorDescription`, which provides an explanation of the problem and its
///    cause, any information that may help track down the problem, background
///    information, etc.
///  * `ErrorHint`, which provides specific, non-obvious advice that may be
///    applicable.
///  * `FlutterError`, which is the most common place to use an `ErrorSummary`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 277-314
public class ErrorSummary: ErrorDiagnostic {
    /// Creates an error summary with the given message.
    ///
    /// **Dart Source:** `assertions.dart:298-308`
    public override init(_ message: String, style: DiagnosticsTreeStyle = .flat, level: DiagnosticLevel = .summary) {
        super.init(message, style: style, level: .summary)
    }

    /// Creates an error summary from message parts.
    ///
    /// **Dart Source:** `assertions.dart:310-313`
    public init(fromParts messageParts: [Any]) {
        super.init(fromParts: messageParts, style: .flat, level: .summary)
    }
}

// MARK: - ErrorHint

/// An `ErrorHint` provides specific, non-obvious advice that may be applicable.
///
/// If your message provides obvious advice that is always applicable, it is an
/// `ErrorDescription` not a hint.
///
/// In debug builds, values interpolated into the `message` are
/// expanded and placed into `value`, which is of type `[Any]`.
/// This allows IDEs to examine values interpolated into error messages.
///
/// See also:
///
///  * `ErrorSummary`, which provides a short (one line) description of the
///    problem that was detected.
///  * `ErrorDescription`, which provides an explanation of the problem and its
///    cause, any information that may help track down the problem, background
///    information, etc.
///  * `ErrorSpacer`, which renders as a blank line.
///  * `FlutterError`, which is the most common place to use an `ErrorHint`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 316-350
public class ErrorHint: ErrorDiagnostic {
    /// Creates an error hint with the given message.
    ///
    /// **Dart Source:** `assertions.dart:334-344`
    public override init(_ message: String, style: DiagnosticsTreeStyle = .flat, level: DiagnosticLevel = .hint) {
        super.init(message, style: style, level: .hint)
    }

    /// Creates an error hint from message parts.
    ///
    /// **Dart Source:** `assertions.dart:346-349`
    public init(fromParts messageParts: [Any]) {
        super.init(fromParts: messageParts, style: .flat, level: .hint)
    }
}

// MARK: - ErrorSpacer

/// An `ErrorSpacer` creates an empty `DiagnosticsNode`, that can be used to
/// tune the spacing between other `DiagnosticsNode` objects.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 352-358
public class ErrorSpacer: DiagnosticsProperty<Void> {
    /// Creates an empty space to insert into a list of `DiagnosticsNode` objects
    /// typically within a `FlutterError` object.
    ///
    /// **Dart Source:** `assertions.dart:354-357`
    public init() {
        super.init(
            "",
            nil,
            description: "",
            showName: false
        )
    }
}

// MARK: - FlutterErrorDetails

/// Class for information provided to `FlutterExceptionHandler` callbacks.
///
/// See also:
///
///   * `FlutterError.onError`, which is called whenever the Flutter framework
///     catches an error.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 360-753
public final class FlutterErrorDetails: Diagnosticable {
    /// Creates a `FlutterErrorDetails` object with the given arguments setting
    /// the object's properties.
    ///
    /// The framework calls this constructor when catching an exception that will
    /// subsequently be reported using `FlutterError.onError`.
    ///
    /// **Dart Source:** `assertions.dart:386-400`
    public init(
        exception: Any,
        stack: String? = nil,
        library: String? = "Flutter framework",
        context: (any DiagnosticsNodeProtocol)? = nil,
        stackFilter: IterableFilter<String>? = nil,
        informationCollector: InformationCollector? = nil,
        silent: Bool = false
    ) {
        self.exception = exception
        self.stack = stack
        self.library = library
        self.context = context
        self.stackFilter = stackFilter
        self.informationCollector = informationCollector
        self.silent = silent
    }

    /// Creates a copy of the error details but with the given fields replaced
    /// with new values.
    ///
    /// **Dart Source:** `assertions.dart:402-422`
    public func copyWith(
        context: (any DiagnosticsNodeProtocol)? = nil,
        exception: Any? = nil,
        informationCollector: InformationCollector? = nil,
        library: String? = nil,
        silent: Bool? = nil,
        stack: String? = nil,
        stackFilter: IterableFilter<String>? = nil
    ) -> FlutterErrorDetails {
        return FlutterErrorDetails(
            exception: exception ?? self.exception,
            stack: stack ?? self.stack,
            library: library ?? self.library,
            context: context ?? self.context,
            stackFilter: stackFilter ?? self.stackFilter,
            informationCollector: informationCollector ?? self.informationCollector,
            silent: silent ?? self.silent
        )
    }

    /// Transformers to transform `DiagnosticsNode` in `DiagnosticPropertiesBuilder`
    /// into a more descriptive form.
    ///
    /// There are layers that attach certain `DiagnosticsNode` into
    /// `FlutterErrorDetails` that require knowledge from other layers to parse.
    /// To correctly interpret those `DiagnosticsNode`, register transformers in
    /// the layers that possess the knowledge.
    ///
    /// **Dart Source:** `assertions.dart:424-436`
    nonisolated(unsafe) public static var propertiesTransformers: [DiagnosticPropertiesTransformer] = []

    /// The exception. Often this will be an `AssertionError`, maybe specifically
    /// a `FlutterError`. However, this could be any value at all.
    ///
    /// **Dart Source:** `assertions.dart:438-440`
    public let exception: Any

    /// The stack trace from where the `exception` was thrown (as opposed to where
    /// it was caught).
    ///
    /// **Dart Source:** `assertions.dart:442-453`
    public let stack: String?

    /// A human-readable brief name describing the library that caught the error
    /// message. This is used by the default error handler in the header dumped to
    /// the console.
    ///
    /// **Dart Source:** `assertions.dart:455-458`
    public let library: String?

    /// A `DiagnosticsNode` that provides a human-readable description of where
    /// the error was caught (as opposed to where it was thrown).
    ///
    /// **Dart Source:** `assertions.dart:460-499`
    public let context: (any DiagnosticsNodeProtocol)?

    /// A callback which filters the `stack` trace. Receives an iterable of
    /// strings representing the frames encoded in the way that
    /// `StackTrace.toString()` provides. Should return an iterable of lines to
    /// output for the stack.
    ///
    /// **Dart Source:** `assertions.dart:501-515`
    public let stackFilter: IterableFilter<String>?

    /// A callback which will provide information that could help with debugging
    /// the problem.
    ///
    /// **Dart Source:** `assertions.dart:517-563`
    public let informationCollector: InformationCollector?

    /// Whether this error should be ignored by the default error reporting
    /// behavior in release mode.
    ///
    /// **Dart Source:** `assertions.dart:565-579`
    public let silent: Bool

    /// Converts the `exception` to a string.
    ///
    /// This applies some additional logic to make `AssertionError` exceptions
    /// prettier, to handle exceptions that stringify to empty strings, to handle
    /// objects that don't inherit from `Error`, and so forth.
    ///
    /// **Dart Source:** `assertions.dart:581-625`
    public func exceptionAsString() -> String {
        var longMessage: String?

        #if canImport(ObjectiveC)
        if let error = exception as? NSException {
            longMessage = "\(error)"
        } else if let stringException = exception as? String {
            longMessage = stringException
        } else if let error = exception as? Error {
            longMessage = "\(error)"
        } else {
            longMessage = "  \(exception)"
        }
        #else
        if let stringException = exception as? String {
            longMessage = stringException
        } else if let error = exception as? Error {
            longMessage = "\(error)"
        } else {
            longMessage = "  \(exception)"
        }
        #endif

        longMessage = longMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if longMessage?.isEmpty ?? true {
            longMessage = "  <no message available>"
        }
        return longMessage!
    }

    /// Returns the exception as a `Diagnosticable` if possible.
    ///
    /// **Dart Source:** `assertions.dart:627-636`
    private func exceptionToDiagnosticable() -> Diagnosticable? {
        if let flutterError = exception as? FlutterError {
            return flutterError
        }
        return nil
    }

    /// Returns a short (one line) description of the problem that was detected.
    ///
    /// **Dart Source:** `assertions.dart:638-662`
    public var summary: any DiagnosticsNodeProtocol {
        func formatException() -> String {
            return exceptionAsString().split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        }

        if kReleaseMode {
            return DiagnosticsNode.message(formatException())
        }

        let diagnosticable = exceptionToDiagnosticable()
        var summaryNode: (any DiagnosticsNodeProtocol)?

        if diagnosticable != nil {
            let builder = DiagnosticPropertiesBuilder()
            debugFillProperties(builder)
            summaryNode = builder.properties.first(where: { $0.level == .summary })
        }

        return summaryNode ?? ErrorSummary(formatException())
    }

    /// **Dart Source:** `assertions.dart:664-737`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        let verb: any DiagnosticsNodeProtocol
        if let context = context {
            verb = ErrorDescription("thrown \(context.toDescription(parentConfiguration: nil))")
        } else {
            verb = ErrorDescription("thrown")
        }

        let diagnosticable = exceptionToDiagnosticable()

        if exception is NSNumber {
            properties.add(ErrorDescription("The number \(exception) was \(verb.toDescription(parentConfiguration: nil))."))
        } else {
            let errorName: String
            #if canImport(ObjectiveC)
            if exception is NSException {
                errorName = "assertion"
            } else if exception is String {
                errorName = "message"
            } else if exception is Error {
                errorName = "\(type(of: exception))"
            } else {
                errorName = "\(type(of: exception)) object"
            }
            #else
            if exception is String {
                errorName = "message"
            } else if exception is Error {
                errorName = "\(type(of: exception))"
            } else {
                errorName = "\(type(of: exception)) object"
            }
            #endif
            properties.add(ErrorDescription("The following \(errorName) was \(verb.toDescription(parentConfiguration: nil)):"))

            if let diagnosticable = diagnosticable {
                diagnosticable.debugFillProperties(properties)
            } else {
                // Many exception classes put their type at the head of their message.
                // This is redundant with the way we display exceptions, so attempt to
                // strip out that header when we see it.
                let prefix = "\(type(of: exception)): "
                var message = exceptionAsString()
                if message.hasPrefix(prefix) {
                    message = String(message.dropFirst(prefix.count))
                }
                properties.add(ErrorSummary(message))
            }
        }

        if let stack = stack {
            #if canImport(ObjectiveC)
            if exception is NSException && diagnosticable == nil {
                // Check if this is "our fault" - an assertion in the framework itself
                let stackFrames = StackFrame.fromStackString(FlutterError.demangleStackTrace(stack))
                    .drop(while: { $0.packageScheme == "dart" })
                let frameArray = Array(stackFrames)

                let ourFault = frameArray.count >= 2 &&
                    frameArray[0].package == "flutter" &&
                    frameArray[1].package == "flutter"

                if ourFault {
                    properties.add(ErrorSpacer())
                    properties.add(ErrorHint(
                        "Either the assertion indicates an error in the framework itself, or we should " +
                        "provide substantially more information in this error message to help you determine " +
                        "and fix the underlying cause.\n" +
                        "In either case, please report this assertion by filing a bug on GitHub:\n" +
                        "  https://github.com/flutter/flutter/issues/new?template=02_bug.yml"
                    ))
                }
            }
            #endif
            properties.add(ErrorSpacer())
            properties.add(DiagnosticsStackTrace(
                "When the exception was thrown, this was the stack",
                stack: stack,
                stackFilter: stackFilter
            ))
        }

        if let informationCollector = informationCollector {
            properties.add(ErrorSpacer())
            for node in informationCollector() {
                properties.add(node)
            }
        }
    }

    /// **Dart Source:** `assertions.dart:739-742`
    public func toStringShort() -> String {
        return library != nil ? "Exception caught by \(library!)" : "Exception caught"
    }

    /// **Dart Source:** `assertions.dart:744-747`
    public func toString(minLevel: DiagnosticLevel = .info) -> String {
        return toDiagnosticsNode(style: .error).toStringDeep(minLevel: minLevel)
    }

    /// **Dart Source:** `assertions.dart:749-752`
    public func toDiagnosticsNode(name: String? = nil, style: DiagnosticsTreeStyle? = nil) -> any DiagnosticsNodeProtocol {
        return FlutterErrorDetailsNode(name: name, value: self, style: style ?? .error)
    }
}

// MARK: - FlutterError

/// Error class used to report Flutter-specific assertion failures and
/// contract violations.
///
/// See also:
///
///  * <https://docs.flutter.dev/testing/errors>, more information about error
///    handling in Flutter.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 755-1205
public final class FlutterError: Error, DiagnosticableTreeMixin, @unchecked Sendable {
    /// Create an error message from a string.
    ///
    /// The message may have newlines in it. The first line should be a terse
    /// description of the error. Subsequent lines should contain
    /// substantial additional information.
    ///
    /// This constructor defers to the `FlutterError.fromParts` constructor.
    /// The first line is wrapped in an implied `ErrorSummary`, and subsequent
    /// lines are wrapped in implied `ErrorDescription`s.
    ///
    /// **Dart Source:** `assertions.dart:762-790`
    public convenience init(_ message: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        var diagnostics: [any DiagnosticsNodeProtocol] = [ErrorSummary(lines.first ?? "")]
        for line in lines.dropFirst() {
            diagnostics.append(ErrorDescription(line))
        }
        self.init(fromParts: diagnostics)
    }

    /// Create an error message from a list of `DiagnosticsNode`s.
    ///
    /// By convention, there should be exactly one `ErrorSummary` in the list,
    /// and it should be the first entry.
    ///
    /// **Dart Source:** `assertions.dart:792-909`
    public init(fromParts diagnostics: [any DiagnosticsNodeProtocol]) {
        assert(!diagnostics.isEmpty, "Empty FlutterError")
        assert(
            diagnostics.first?.level == .summary,
            "FlutterError is missing a summary. All FlutterError objects should start with a short (one line) summary description of the problem that was detected."
        )

        // Check for multiple summaries in debug mode
        assert({
            let summaries = diagnostics.filter { $0.level == .summary }
            if summaries.count > 1 {
                assertionFailure("FlutterError contained multiple error summaries.")
            }
            return true
        }())

        self.diagnostics = diagnostics
    }

    /// The information associated with this error, in structured form.
    ///
    /// The first node is typically an `ErrorSummary` giving a short description
    /// of the problem, suitable for an index of errors, a log, etc.
    ///
    /// **Dart Source:** `assertions.dart:911-921`
    public let diagnostics: [any DiagnosticsNodeProtocol]

    /// The message associated with this error.
    ///
    /// This is generated by serializing the `diagnostics`.
    ///
    /// **Dart Source:** `assertions.dart:923-927`
    public var message: String {
        return toString()
    }

    /// Called whenever the Flutter framework catches an error.
    ///
    /// The default behavior is to call `presentError`.
    ///
    /// **Dart Source:** `assertions.dart:929-951`
    nonisolated(unsafe) public static var onError: FlutterExceptionHandler? = presentError

    /// Called by the Flutter framework before attempting to parse a stack trace.
    ///
    /// **Dart Source:** `assertions.dart:953-981`
    nonisolated(unsafe) public static var demangleStackTrace: StackTraceDemangler = { $0 }

    /// Called whenever the Flutter framework wants to present an error to the
    /// users.
    ///
    /// The default behavior is to call `dumpErrorToConsole`.
    ///
    /// **Dart Source:** `assertions.dart:983-992`
    nonisolated(unsafe) public static var presentError: FlutterExceptionHandler = { details in
        dumpErrorToConsole(details)
    }

    /// Internal error count for tracking repeated errors.
    ///
    /// **Dart Source:** `assertions.dart:994`
    nonisolated(unsafe) private static var _errorCount: Int = 0

    /// Resets the count of errors used by `dumpErrorToConsole` to decide whether
    /// to show a complete error message or an abbreviated one.
    ///
    /// After this is called, the next error message will be shown in full.
    ///
    /// **Dart Source:** `assertions.dart:996-1002`
    public static func resetErrorCount() {
        _errorCount = 0
    }

    /// The width to which `dumpErrorToConsole` will wrap lines.
    ///
    /// **Dart Source:** `assertions.dart:1004-1008`
    public static let wrapWidth: Int = 100

    /// Prints the given exception details to the console.
    ///
    /// The first time this is called, it dumps a very verbose message to the
    /// console using `debugPrint`.
    ///
    /// Subsequent calls only dump the first line of the exception, unless
    /// `forceReport` is set to true.
    ///
    /// **Dart Source:** `assertions.dart:1010-1053`
    public static func dumpErrorToConsole(_ details: FlutterErrorDetails, forceReport: Bool = false) {
        var isInDebugMode = false
        assert({
            isInDebugMode = true
            return true
        }())

        let reportError = isInDebugMode || !details.silent
        if !reportError && !forceReport {
            return
        }

        if _errorCount == 0 || forceReport {
            if isInDebugMode {
                let renderer = TextTreeRenderer(
                    wrapWidthProperties: wrapWidth,
                    maxDescendentsTruncatableNode: 5
                )
                let output = renderer.render(details.toDiagnosticsNode(style: .error))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                debugPrint(output, nil)
            } else {
                debugPrintStack(
                    stackTrace: details.stack,
                    label: "\(details.exception)",
                    maxFrames: 100
                )
            }
        } else {
            debugPrint("Another exception was thrown: \(details.summary.toDescription(parentConfiguration: nil))", nil)
        }
        _errorCount += 1
    }

    /// Internal list of stack filters.
    ///
    /// **Dart Source:** `assertions.dart:1055`
    nonisolated(unsafe) private static var _stackFilters: [StackFilter] = []

    /// Adds a stack filtering function to `defaultStackFilter`.
    ///
    /// **Dart Source:** `assertions.dart:1057-1066`
    public static func addDefaultStackFilter(_ filter: StackFilter) {
        _stackFilters.append(filter)
    }

    /// Converts a stack to a string that is more readable by omitting stack
    /// frames that correspond to Dart internals.
    ///
    /// **Dart Source:** `assertions.dart:1068-1155`
    public static func defaultStackFilter(_ frames: any Sequence<String>) -> any Sequence<String> {
        var removedPackagesAndClasses: [String: Int] = [
            "dart:async-patch": 0,
            "dart:async": 0,
            "package:stack_trace": 0,
            "class _AssertionError": 0,
            "class _FakeAsync": 0,
            "class _FrameCallbackEntry": 0,
            "class _Timer": 0,
            "class _RawReceivePortImpl": 0,
        ]
        var skipped = 0

        var parsedFrames = StackFrame.fromStackString(Array(frames).joined(separator: "\n"))

        var index = 0
        while index < parsedFrames.count {
            let frame = parsedFrames[index]
            let className = "class \(frame.className)"
            let package = "\(frame.packageScheme):\(frame.package)"

            if removedPackagesAndClasses.keys.contains(className) {
                skipped += 1
                removedPackagesAndClasses[className] = (removedPackagesAndClasses[className] ?? 0) + 1
                parsedFrames.remove(at: index)
            } else if removedPackagesAndClasses.keys.contains(package) {
                skipped += 1
                removedPackagesAndClasses[package] = (removedPackagesAndClasses[package] ?? 0) + 1
                parsedFrames.remove(at: index)
            } else {
                index += 1
            }
        }

        var reasons: [String?] = Array(repeating: nil, count: parsedFrames.count)
        for filter in _stackFilters {
            filter.filter(stackFrames: &parsedFrames, reasons: &reasons)
        }

        var result: [String] = []

        // Collapse duplicated reasons
        index = 0
        while index < parsedFrames.count {
            let start = index
            while index < reasons.count - 1 &&
                  reasons[index] != nil &&
                  reasons[index + 1] == reasons[index] {
                index += 1
            }

            var suffix = ""
            if reasons[index] != nil {
                if index != start {
                    suffix = " (\(index - start + 2) frames)"
                } else {
                    suffix = " (1 frame)"
                }
            }

            let resultLine = "\(reasons[index] ?? parsedFrames[index].source)\(suffix)"
            result.append(resultLine)
            index += 1
        }

        // Only include packages we actually elided from
        var where_: [String] = removedPackagesAndClasses
            .filter { $0.value > 0 }
            .map { $0.key }
            .sorted()

        if skipped == 1 {
            result.append("(elided one frame from \(where_.first ?? ""))")
        } else if skipped > 1 {
            if where_.count > 1 {
                where_[where_.count - 1] = "and \(where_.last!)"
            }
            if where_.count > 2 {
                result.append("(elided \(skipped) frames from \(where_.joined(separator: ", ")))")
            } else {
                result.append("(elided \(skipped) frames from \(where_.joined(separator: " ")))")
            }
        }

        return result
    }

    // MARK: - DiagnosticableTreeMixin

    /// **Dart Source:** `assertions.dart:1157-1160`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        for diagnostic in diagnostics {
            properties.add(diagnostic)
        }
    }

    /// **Dart Source:** `assertions.dart:1162-1163`
    public func toStringShort() -> String {
        return "FlutterError"
    }

    /// **Dart Source:** `assertions.dart:1165-1174`
    public func toString(minLevel: DiagnosticLevel = .info) -> String {
        if kReleaseMode {
            let errors = diagnostics.compactMap { $0 as? ErrorDiagnostic }
            return errors.isEmpty ? toStringShort() : errors.first!.valueToString(parentConfiguration: nil)
        }
        // Avoid wrapping lines
        let renderer = TextTreeRenderer(wrapWidth: 1_000_000_000)  // fits a 32-bit Int (wasm32)
        return diagnostics.map { renderer.render($0).trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
    }

    /// Calls `onError` with the given details, unless it is null.
    ///
    /// **Dart Source:** `assertions.dart:1176-1204`
    public static func reportError(_ details: FlutterErrorDetails) {
        onError?(details)
    }

    // MARK: - DiagnosticableTree conformance

    public func debugDescribeChildren() -> [any DiagnosticsNodeProtocol] {
        return []
    }

    public func toDiagnosticsNode(name: String?, style: DiagnosticsTreeStyle?) -> any DiagnosticsNodeProtocol {
        return DiagnosticableTreeNode(name: name, value: self, style: style ?? .error)
    }

    public func toStringDeep(
        prefixLineOne: String,
        prefixOtherLines: String?,
        minLevel: DiagnosticLevel
    ) -> String {
        return toDiagnosticsNode(name: nil, style: nil).toStringDeep(
            prefixLineOne: prefixLineOne,
            prefixOtherLines: prefixOtherLines,
            minLevel: minLevel
        )
    }

    public func toStringShallow(
        joiner: String = ", ",
        minLevel: DiagnosticLevel = .debug
    ) -> String {
        #if DEBUG
        var result = ""
        result += toStringShort()
        result += joiner
        let builder = DiagnosticPropertiesBuilder()
        debugFillProperties(builder)
        let filteredProperties = builder.properties.filter { !$0.isFiltered(minLevel) }
        result += filteredProperties.map { node in
            if let diagnosticsNode = node as? DiagnosticsNode {
                return diagnosticsNode.toString(parentConfiguration: nil, minLevel: minLevel)
            }
            return node.toDescription(parentConfiguration: nil)
        }.joined(separator: joiner)
        return result
        #else
        return toStringShort()
        #endif
    }
}

// MARK: - debugPrintStack Function

/// Dump the stack to the console using `debugPrint` and
/// `FlutterError.defaultStackFilter`.
///
/// If the `stackTrace` parameter is nil, the current call stack is used.
///
/// The `maxFrames` argument can be given to limit the stack to the given number
/// of lines before filtering is applied. By default, all stack lines are
/// included.
///
/// The `label` argument, if present, will be printed before the stack.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 1207-1242
public func debugPrintStack(stackTrace: String? = nil, label: String? = nil, maxFrames: Int? = nil) {
    if let label = label {
        debugPrint(label, nil)
    }

    let stack: String
    if let stackTrace = stackTrace {
        stack = FlutterError.demangleStackTrace(stackTrace)
    } else {
        // Get current call stack
        stack = Thread.callStackSymbols.joined(separator: "\n")
    }

    var lines: [String] = stack.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .map { String($0) }

    // On web, skip certain internal frames
    if kIsWeb && !lines.isEmpty {
        lines = Array(lines.drop(while: { line in
            line.contains("StackTrace.current") ||
            line.contains("dart-sdk/lib/_internal") ||
            line.contains("dart:sdk_internal")
        }))
    }

    if let maxFrames = maxFrames {
        lines = Array(lines.prefix(maxFrames))
    }

    let filtered = FlutterError.defaultStackFilter(lines)
    debugPrint(Array(filtered).joined(separator: "\n"), nil)
}

// MARK: - DiagnosticsStackTrace

/// Diagnostic with a stack trace value suitable for displaying stack traces
/// as part of a `FlutterError` object.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 1244-1296
public class DiagnosticsStackTrace: DiagnosticsBlock {
    /// Creates a diagnostic for a stack trace.
    ///
    /// `name` describes a name the stack trace is given, e.g.
    /// `When the exception was thrown, this was the stack`.
    /// `stackFilter` provides an optional filter to use to filter which frames
    /// are included. If no filter is specified, `FlutterError.defaultStackFilter`
    /// is used.
    /// `showSeparator` indicates whether to include a ':' after the `name`.
    ///
    /// **Dart Source:** `assertions.dart:1246-1266`
    public init(
        _ name: String,
        stack: String?,
        stackFilter: IterableFilter<String>? = nil,
        showSeparator: Bool = true
    ) {
        super.init(
            name: name,
            style: .flat,
            showName: true,
            showSeparator: showSeparator,
            value: stack,
            level: .info,
            allowTruncate: true,
            properties: DiagnosticsStackTrace.applyStackFilter(stack, stackFilter)
        )
    }

    /// Creates a diagnostic describing a single frame from a StackTrace.
    ///
    /// **Dart Source:** `assertions.dart:1268-1274`
    public init(singleFrame name: String, frame: String, showSeparator: Bool = true) {
        super.init(
            name: name,
            style: .whitespace,
            showName: true,
            showSeparator: showSeparator,
            properties: [DiagnosticsStackTrace.createStackFrame(frame)]
        )
    }

    /// **Dart Source:** `assertions.dart:1276-1288`
    private static func applyStackFilter(
        _ stack: String?,
        _ stackFilter: IterableFilter<String>?
    ) -> [any DiagnosticsNodeProtocol] {
        guard let stack = stack else {
            return []
        }

        let filter: IterableFilter<String> = stackFilter ?? { frames in FlutterError.defaultStackFilter(frames) }
        let demangled = FlutterError.demangleStackTrace(stack)
        let lines = demangled.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map { String($0) }
        let frames = filter(lines)

        return Array(frames).map { DiagnosticsStackTrace.createStackFrame($0) }
    }

    /// **Dart Source:** `assertions.dart:1290-1292`
    private static func createStackFrame(_ frame: String) -> any DiagnosticsNodeProtocol {
        return DiagnosticsNode.message(frame, allowWrap: false)
    }

    /// **Dart Source:** `assertions.dart:1294-1295`
    public override var allowTruncate: Bool { false }
}

// MARK: - FlutterErrorDetailsNode (Internal)

/// Internal node class for FlutterErrorDetails diagnostics.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/assertions.dart`
/// **Lines:** 1298-1314
internal class FlutterErrorDetailsNode: DiagnosticsNode {
    /// **Dart Source:** `assertions.dart:1299`
    init(name: String?, value: FlutterErrorDetails, style: DiagnosticsTreeStyle) {
        self._value = value
        super.init(name: name, style: style)
    }

    private let _value: FlutterErrorDetails

    /// The value associated with this node.
    public override var value: Any? { _value }

    private var _cachedBuilder: DiagnosticPropertiesBuilder?

    private var _transformedProperties: [any DiagnosticsNodeProtocol]?

    /// **Dart Source:** `assertions.dart:1301-1313`
    private func getBuilder() -> DiagnosticPropertiesBuilder {
        if _cachedBuilder == nil {
            _cachedBuilder = DiagnosticPropertiesBuilder()
            _value.debugFillProperties(_cachedBuilder!)
        }
        return _cachedBuilder!
    }

    /// Get properties with transformers applied
    private func getTransformedProperties() -> [any DiagnosticsNodeProtocol] {
        if _transformedProperties == nil {
            var properties: [any DiagnosticsNodeProtocol] = getBuilder().properties
            for transformer in FlutterErrorDetails.propertiesTransformers {
                properties = transformer(properties)
            }
            _transformedProperties = properties
        }
        return _transformedProperties!
    }

    /// Style to use for this node.
    public override var style: DiagnosticsTreeStyle? {
        return super.style ?? getBuilder().defaultDiagnosticsTreeStyle
    }

    /// Description to show if the node has no displayed properties or children.
    public override var emptyBodyDescription: String? {
        return getBuilder().emptyBodyDescription
    }

    /// Properties of this `DiagnosticsNode`.
    public override func getProperties() -> [any DiagnosticsNodeProtocol] {
        return getTransformedProperties()
    }

    /// Returns a description with a short summary of the node itself.
    public override func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        return _value.toStringShort()
    }
}
