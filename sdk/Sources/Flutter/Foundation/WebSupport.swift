// What the rest of this module takes for granted that WASI does not supply.

#if os(WASI)
// Exported module-wide, so that each file sees what Foundation would have
// brought with it elsewhere: libm (sin, pow…), which Foundation re-exports
// through Glibc or Darwin, and DispatchQueue, which on the web is
// FlutterSwiftBridge's stand-in over the page's event loop.
@_exported import FlutterSwiftBridge
@_exported import WASILibc
import Foundation

/// One thread, and no unwinder to ask for symbols.
enum Thread {
    static var callStackSymbols: [String] { [] }
    static var isMainThread: Bool { true }
}

// Foundation ships `Timer` and `RunLoop` for WASI, but both are built on a
// CoreFoundation run loop that is not there: they compile and then fail to
// link. These two take the names for this module — a declaration here wins
// over an imported one — and run on the page's event loop instead.

/// Foundation.Timer, as far as the framework uses it.
final class Timer {
    private var token: Int32 = 0
    private let interval: Double
    private let repeats: Bool
    private let block: (Timer) -> Void
    private(set) var isValid = true

    private init(interval: Double, repeats: Bool, block: @escaping (Timer) -> Void) {
        self.interval = interval
        self.repeats = repeats
        self.block = block
    }

    @discardableResult
    static func scheduledTimer(
        withTimeInterval interval: Double, repeats: Bool,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let timer = Timer(interval: interval, repeats: repeats, block: block)
        timer.arm()
        return timer
    }

    private func arm() {
        // The pending closure keeps the timer alive until it fires, as a
        // run loop keeps a scheduled Foundation.Timer.
        token = WebTimers.schedule(afterMilliseconds: interval * 1000) {
            guard self.isValid else { return }
            if self.repeats { self.arm() } else { self.isValid = false }
            self.block(self)
        }
    }

    func invalidate() {
        isValid = false
        WebTimers.cancel(token)
    }

    func fire() { block(self) }
}

final class RunLoop {
    static let main = RunLoop()
    static var current: RunLoop { main }

    func perform(_ block: @escaping () -> Void) {
        WebTimers.schedule(afterMilliseconds: 0, block)
    }
}

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
    /// Internal: a public twin would be ambiguous with Foundation's in an
    /// app. Apps use `String(printf:)`, which is one spelling everywhere.
    init(format: String, _ a: CVarArg) { self = webFormat(format, [a]) }
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
