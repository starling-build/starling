// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Swift concurrency on the page's event loop.
//
// On WASI the runtime's global executor puts jobs on a queue that only an
// `async main` drains, and this module has no main: the page calls in and
// every call returns. So every `Task {}` in the framework — image decoding
// is one — would be queued forever. The runtime provides hooks for exactly
// this case (JavaScriptKit's JavaScriptEventLoop uses the same ones): each
// enqueued job becomes a timer on the page, and runs on the one thread there
// is, which is also the main actor's.

#if compiler(>=6.4) || (swift(>=6.3) && arch(wasm32))
@_spi(ExperimentalCustomExecutors) @_spi(ExperimentalScheduling) import _Concurrency
#endif

import CSkwasm
import FlutterSwiftBridgeCxx

/// The one executor. Serial by construction: there is one thread.
final class WebExecutor: SerialExecutor, @unchecked Sendable {
    static let shared = WebExecutor()

    func enqueue(_ job: UnownedJob) {
        WebTimers.schedule(afterMilliseconds: 0) {
            job.runSynchronously(on: self.asUnownedSerialExecutor())
            WebExecutor.drainRuntimeQueue()
        }
    }

    #if compiler(>=6.4) || (swift(>=6.3) && arch(wasm32))
    static func drainRuntimeQueue() {}
    #else
    private nonisolated(unsafe) static var draining = false
    private nonisolated(unsafe) static var drainScheduled = false

    /// The 6.2 runtime keeps one queue this executor cannot stand in for:
    /// `Task.sleep` parks its job on the DEFAULT executor's timer queue —
    /// the runtime's cooperative one, since the protocol that would let
    /// this class take it (`SchedulableExecutor`) is internal there — and
    /// only a thread donated to that executor runs it. So after every job
    /// the thread is donated for one pass: due sleepers and ready jobs
    /// run, and the pass returns instead of sleeping until the next
    /// deadline (the page answers poll_oneoff with ENOSYS at once, and the
    /// condition, asked again, says stop). A second ask means sleepers are
    /// still waiting, and the next pass is a timer away. Without this a
    /// task that sleeps never wakes: Slides' PDF export waited for ever on
    /// a picture the browser could not decode.
    static func drainRuntimeQueue() {
        guard !draining else { return }
        draining = true
        var asked = 0
        withUnsafeMutablePointer(to: &asked) { count in
            swift_task_donateThreadToGlobalExecutorUntil({ context in
                let count = context.assumingMemoryBound(to: Int.self)
                count.pointee += 1
                return count.pointee > 1
            }, count)
        }
        draining = false
        if asked > 1 && !drainScheduled {
            drainScheduled = true
            WebTimers.schedule(afterMilliseconds: 8) {
                drainScheduled = false
                drainRuntimeQueue()
            }
        }
    }
    #endif

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    #if !(compiler(>=6.4) || (swift(>=6.3) && arch(wasm32)))
    // The page calls in from outside any job, on the one thread there is.
    func checkIsolated() {}
    #endif

    /// Installs the hooks. Once, before the first `Task`.
    static func install() {
        #if compiler(>=6.4) || (swift(>=6.3) && arch(wasm32))
        _Concurrency._createExecutors(factory: WebExecutor.self)
        #else
        swift_task_enqueueGlobal_hook = unsafeBitCast(
            enqueueGlobal as EnqueueGlobalHook, to: UnsafeMutableRawPointer?.self)
        swift_task_enqueueGlobalWithDelay_hook = unsafeBitCast(
            enqueueGlobalWithDelay as EnqueueGlobalWithDelayHook,
            to: UnsafeMutableRawPointer?.self)
        swift_task_enqueueGlobalWithDeadline_hook = unsafeBitCast(
            enqueueGlobalWithDeadline as EnqueueGlobalWithDeadlineHook,
            to: UnsafeMutableRawPointer?.self)
        swift_task_enqueueMainExecutor_hook = unsafeBitCast(
            enqueueMain as EnqueueMainHook, to: UnsafeMutableRawPointer?.self)
        // The 6.2 runtime has the executor objects of 6.3 and no way to
        // supply one: the main actor's executor is its own cooperative
        // queue, a task for the main actor is enqueued on that object
        // directly — past every hook above — and nothing here drains it.
        // This hook is what the runtime asks for that object.
        swift_task_getMainExecutor_hook = unsafeBitCast(
            getMainExecutor as GetMainExecutorHook, to: UnsafeMutableRawPointer?.self)
        #endif
    }
}

// The hook signatures, from the runtime's Concurrency/GlobalExecutor.cpp.
// Each receives the original implementation, which is not called.

private typealias EnqueueGlobalHook =
    @convention(thin) (UnownedJob, @convention(thin) (UnownedJob) -> Void) -> Void
private typealias EnqueueGlobalWithDelayHook =
    @convention(thin) (UInt64, UnownedJob, @convention(thin) (UInt64, UnownedJob) -> Void) -> Void
private typealias EnqueueGlobalWithDeadlineHook =
    @convention(thin) (
        Int64, Int64, Int64, Int64, Int32, UnownedJob,
        @convention(thin) (Int64, Int64, Int64, Int64, Int32, UnownedJob) -> Void
    ) -> Void
private typealias EnqueueMainHook =
    @convention(thin) (UnownedJob, @convention(thin) (UnownedJob) -> Void) -> Void
private typealias GetMainExecutorHook =
    @convention(thin) (@convention(thin) () -> UnownedSerialExecutor) -> UnownedSerialExecutor

private func enqueueGlobal(_ job: UnownedJob, _ original: @convention(thin) (UnownedJob) -> Void) {
    WebExecutor.shared.enqueue(job)
}

private func enqueueGlobalWithDelay(
    _ nanoseconds: UInt64, _ job: UnownedJob,
    _ original: @convention(thin) (UInt64, UnownedJob) -> Void
) {
    WebTimers.schedule(afterMilliseconds: Double(nanoseconds) / 1_000_000) {
        job.runSynchronously(on: WebExecutor.shared.asUnownedSerialExecutor())
        WebExecutor.drainRuntimeQueue()
    }
}

/// `Task.sleep(until:)` and clock-based waits: the deadline is seconds and
/// nanoseconds on the given clock, of which only the continuous one
/// (`clock` 1, monotonic) is meaningful here; both are treated as "from
/// now", against the same monotonic time the runtime reads.
private func enqueueGlobalWithDeadline(
    _ seconds: Int64, _ nanoseconds: Int64, _ leewaySeconds: Int64, _ leewayNanoseconds: Int64,
    _ clock: Int32, _ job: UnownedJob,
    _ original: @convention(thin) (Int64, Int64, Int64, Int64, Int32, UnownedJob) -> Void
) {
    // The runtime reads its monotonic clock through WASI's clock_time_get,
    // which the page answers with performance.now() — the same number
    // starling_host_now returns, so the two are one clock.
    let deadlineMs = Double(seconds) * 1000 + Double(nanoseconds) / 1_000_000
    let nowMs = starling_host_now()
    WebTimers.schedule(afterMilliseconds: max(0, deadlineMs - nowMs)) {
        job.runSynchronously(on: WebExecutor.shared.asUnownedSerialExecutor())
        WebExecutor.drainRuntimeQueue()
    }
}

private func enqueueMain(_ job: UnownedJob, _ original: @convention(thin) (UnownedJob) -> Void) {
    WebExecutor.shared.enqueue(job)
}

private func getMainExecutor(
    _ original: @convention(thin) () -> UnownedSerialExecutor
) -> UnownedSerialExecutor {
    WebExecutor.shared.asUnownedSerialExecutor()
}

// The runtime's hook variables.
@_silgen_name("swift_task_enqueueGlobal_hook")
private var swift_task_enqueueGlobal_hook: UnsafeMutableRawPointer?
@_silgen_name("swift_task_enqueueGlobalWithDelay_hook")
private var swift_task_enqueueGlobalWithDelay_hook: UnsafeMutableRawPointer?
@_silgen_name("swift_task_enqueueGlobalWithDeadline_hook")
private var swift_task_enqueueGlobalWithDeadline_hook: UnsafeMutableRawPointer?
@_silgen_name("swift_task_enqueueMainExecutor_hook")
private var swift_task_enqueueMainExecutor_hook: UnsafeMutableRawPointer?
@_silgen_name("swift_task_getMainExecutor_hook")
private var swift_task_getMainExecutor_hook: UnsafeMutableRawPointer?

#if !(compiler(>=6.4) || (swift(>=6.3) && arch(wasm32)))
@_silgen_name("swift_task_donateThreadToGlobalExecutorUntil")
private func swift_task_donateThreadToGlobalExecutorUntil(
    _ condition: @convention(c) (UnsafeMutableRawPointer) -> CBool,
    _ context: UnsafeMutableRawPointer)
#endif

#if compiler(>=6.4) || (swift(>=6.3) && arch(wasm32))
// New runtimes obtain the main/global executors from a factory instead of
// the legacy hooks. Without it, MainActor tasks remain on an undrained queue.
extension WebExecutor: MainExecutor, TaskExecutor, SchedulingExecutor, ExecutorFactory {
    static var mainExecutor: any MainExecutor { shared }
    static var defaultExecutor: any TaskExecutor { shared }

    // The browser owns the event loop; this host uses a synchronous entry point.
    func run() throws {}
    func stop() {}
    func checkIsolated() {} // Every call runs on the page's one thread.

    func enqueue(_ job: consuming ExecutorJob) { enqueue(UnownedJob(job)) }

    func enqueue<C: Clock>(_ job: consuming ExecutorJob, after delay: C.Duration,
                           tolerance: C.Duration?, clock: C) {
        guard let duration = delay as? Duration else {
            fatalError("WebExecutor requires a Duration-based clock")
        }
        let (seconds, attoseconds) = duration.components
        let milliseconds = Double(seconds) * 1000 + Double(attoseconds) / 1e15
        let unowned = UnownedJob(job)
        WebTimers.schedule(afterMilliseconds: milliseconds) {
            unowned.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }
}
#endif
