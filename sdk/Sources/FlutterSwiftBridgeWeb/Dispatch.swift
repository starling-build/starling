// Timers, and the part of Dispatch the framework uses, on the page's event
// loop.
//
// There is no Dispatch on WASI: no threads, so no queues. But the framework
// uses `DispatchQueue.main` for exactly one idea — "run this later, on the
// thread I am already on" — and a tab has that: setTimeout. So the names are
// re-made here over it, and the framework's call sites stay as they are.
// Every queue is the main queue, because every thread is the main thread.
import CSkwasm

/// One-shot timers on the page's event loop.
public enum WebTimers {
    nonisolated(unsafe) private static var pending: [Int32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextId: Int32 = 0

    /// Returns a token for `cancel`.
    @discardableResult
    public static func schedule(
        afterMilliseconds milliseconds: Double, _ body: @escaping () -> Void
    ) -> Int32 {
        nextId &+= 1
        pending[nextId] = body
        starling_host_set_timeout(nextId, max(0, milliseconds))
        return nextId
    }

    public static func cancel(_ id: Int32) { pending[id] = nil }

    /// Called by the host when the page calls `starling_timer_fired`.
    public static func fire(_ id: Int32) { pending.removeValue(forKey: id)?() }
}

public enum DispatchTimeInterval: Equatable, Sendable {
    case seconds(Int)
    case milliseconds(Int)
    case microseconds(Int)
    case nanoseconds(Int)
    case never

    var milliseconds: Double {
        switch self {
        case .seconds(let s): return Double(s) * 1000
        case .milliseconds(let ms): return Double(ms)
        case .microseconds(let us): return Double(us) / 1000
        case .nanoseconds(let ns): return Double(ns) / 1_000_000
        case .never: return .infinity
        }
    }
}

public struct DispatchTime: Comparable, Sendable {
    /// Milliseconds since the page loaded.
    var milliseconds: Double

    public static func now() -> DispatchTime {
        DispatchTime(milliseconds: starling_host_now())
    }

    public static let distantFuture = DispatchTime(milliseconds: .infinity)

    public var uptimeNanoseconds: UInt64 {
        milliseconds.isFinite ? UInt64(max(0, milliseconds) * 1_000_000) : .max
    }

    public static func < (a: DispatchTime, b: DispatchTime) -> Bool {
        a.milliseconds < b.milliseconds
    }

    public static func + (time: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime {
        DispatchTime(milliseconds: time.milliseconds + interval.milliseconds)
    }

    public static func + (time: DispatchTime, seconds: Double) -> DispatchTime {
        DispatchTime(milliseconds: time.milliseconds + seconds * 1000)
    }
}

public struct DispatchQoS: Sendable {
    public enum QoSClass: Sendable {
        case background, utility, `default`, userInitiated, userInteractive, unspecified
    }
    public static let background = DispatchQoS()
    public static let utility = DispatchQoS()
    public static let `default` = DispatchQoS()
    public static let userInitiated = DispatchQoS()
    public static let userInteractive = DispatchQoS()
    public static let unspecified = DispatchQoS()
}

public final class DispatchWorkItem {
    private let body: () -> Void
    public private(set) var isCancelled = false

    public init(block: @escaping () -> Void) { body = block }

    public func perform() { if !isCancelled { body() } }
    public func cancel() { isCancelled = true }
}

public final class DispatchQueue: @unchecked Sendable {
    public static let main = DispatchQueue()

    public struct Attributes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let concurrent = Attributes(rawValue: 1)
    }

    init() {}

    /// Labels and attributes are accepted and mean nothing: see the top.
    public convenience init(
        label: String, qos: DispatchQoS = .unspecified, attributes: Attributes = []
    ) {
        self.init()
    }

    public static func global(qos: DispatchQoS.QoSClass = .default) -> DispatchQueue { main }

    public func async(execute work: @escaping () -> Void) {
        WebTimers.schedule(afterMilliseconds: 0, work)
    }

    public func async(execute item: DispatchWorkItem) {
        WebTimers.schedule(afterMilliseconds: 0) { item.perform() }
    }

    public func asyncAfter(deadline: DispatchTime, execute work: @escaping () -> Void) {
        WebTimers.schedule(
            afterMilliseconds: deadline.milliseconds - starling_host_now(), work)
    }

    public func asyncAfter(deadline: DispatchTime, execute item: DispatchWorkItem) {
        asyncAfter(deadline: deadline) { item.perform() }
    }

    /// We are already on the only thread.
    public func sync<T>(execute work: () throws -> T) rethrows -> T { try work() }
}
