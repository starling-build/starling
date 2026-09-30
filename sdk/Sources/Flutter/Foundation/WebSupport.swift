// What the rest of this module takes for granted that WASI does not supply.

#if os(WASI)
// Exported module-wide, so that each file sees what Foundation would have
// brought with it elsewhere: libm (sin, pow…), which Foundation re-exports
// through Glibc or Darwin, and DispatchQueue, which on the web is
// FlutterSwiftBridge's stand-in over the page's event loop.
@_exported import FlutterSwiftBridge
@_exported import WASILibc

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
#endif
