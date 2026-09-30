// What the rest of this module takes for granted that WASI does not supply.
// The counterpart of Flutter/Foundation/WebSupport.swift.

#if os(WASI)
import FlutterSwiftBridgeCxx
import Foundation

// MARK: - Names Foundation owns, re-made so the legacy module is not linked
//
// These three are the framework's only reasons to reach the legacy
// `Foundation` module (the NS layer), and on this target that module drags
// ICU in — 40 MB (docs/plans/wasm-size.md). A declaration in this module
// shadows the imported one, so the call sites stay as they are.
// build/web-app.sh --check fails the build if the shadow ever slips.

extension String {
    /// printf-style, for the specifiers the framework uses: see
    /// FlutterSwiftBridgeWeb/Format.swift.
    ///
    /// One argument, not `CVarArg...`: a variadic twin of Foundation's is
    /// "ambiguous" to the type checker, and so, it turns out, is a fixed
    /// arity of two or more — only the one-argument form outranks the
    /// variadic. Every call in the framework passes one argument; the two
    /// that passed several (ColorPicker's hex string) were split.
    public init(format: String, _ a: CVarArg) { self = webFormat(format, [a]) }
}

/// Only the two standard streams; there is no file to open.
final class FileHandle: Sendable {
    static let standardError = FileHandle(descriptor: 2)
    static let standardOutput = FileHandle(descriptor: 1)
    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }

    func write(_ data: Data) {
        data.withUnsafeBytes { bytes in
            if descriptor == 2 { webWriteStandardError(bytes) } else { print(String(decoding: bytes, as: UTF8.self), terminator: "") }
        }
    }

    func write(contentsOf data: Data) throws { write(data) }
}

/// One thread: locking is a no-op, and every `withLock` is just its body.
final class NSLock: Sendable {
    init() {}
    func lock() {}
    func unlock() {}
    func `try`() -> Bool { true }
    func withLock<T>(_ body: () throws -> T) rethrows -> T { try body() }
}
#endif
