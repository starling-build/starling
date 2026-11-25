import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs a body on a thread with a large stack.
///
/// Word layout recurses (table inside table, footnote inside a table cell, a text box inside a header) and its
/// frames are big: in the release build `_StyledFrame.go` alone reserves ~565 KB, `flush` 86 KB, `_blk7` 53 KB.
/// An ordinary document needs 2-3 MB of stack and a nested table 4-6 MB (`--convert` under `ulimit -s`, 130
/// documents), against 8 MB for a Mac main thread and **1 MB for an iPad's** (512 KB on any other thread). A
/// debug build's frames are larger still, which is why four unit tests died with signal 11 on a Mac.
/// The browser build sets its stack at link time (16 MB), so it needs no hop.
///
/// The thread is made with `pthread_create` and the result is checked. `Foundation.Thread.start()` on Linux
/// ignores a failed `pthread_create`, so under load (many renders at once, a pid or address-space limit) the body
/// never ran and the caller waited forever on the semaphore. Now a refused thread is retried for about half a second,
/// then tried with 32 and 16 MB, and as the last resort the body runs on the caller's own stack, as it did before the
/// hop existed. Each refusal and step down prints one line on stderr.
public enum BigStack {
    static let size = 64 << 20
    /// Test hook: this many of the next thread creations are treated as refused.
    nonisolated(unsafe) public static var simulatedRefusals = 0
    private static let refusalLock = NSLock()

    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }

    public static func run<T>(_ body: @escaping () -> T) -> T {
        #if arch(wasm32) || !(canImport(Darwin) || canImport(Glibc))
        return body()
        #else
        if _onBigStack() { return body() }
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        let job = { () -> Void in
            _markBigStack()
            box.value = body()
            done.signal()
        }
        if !_spawn(job) { return body() }
        done.wait()
        return box.value!
        #endif
    }

    /// `STARLING_BIGSTACK_ALWAYS=1`: `runIfSmall` always hops, so a Mac (8 MB main thread) or the simulator exercises the path an
    /// iPad's takes.
    private static let alwaysHop = getenv("STARLING_BIGSTACK_ALWAYS") != nil

    /// `run`, but only when this thread's own stack is smaller than `threshold` (7 MB: a Mac's main thread has 8 MB, and reports a little less): for work that
    /// happens every frame, where a thread per call is not free and a big stack needs no hop. Only Darwin can ask a thread its
    /// stack size (`pthread_get_stacksize_np`), and only there does an app's small main thread exist (an iPad's): elsewhere the body
    /// runs here, as it did before.
    public static func runIfSmall<T>(threshold: Int = 7 << 20, _ body: @escaping () -> T) -> T {
        #if canImport(Darwin) && !(arch(wasm32))
        if _onBigStack() || (pthread_get_stacksize_np(pthread_self()) >= threshold && !alwaysHop) { return body() }
        if perCallThread { return run(body) }
        guard let worker = Worker.shared else { return run(body) }
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        worker.submit {
            box.value = body()
            done.signal()
        }
        done.wait()
        return box.value!
        #else
        return body()
        #endif
    }

    /// `STARLING_BIGSTACK_PERCALL=1`: `runIfSmall` makes a thread per call, as `run` does (to measure what the worker saves).
    private static let perCallThread = getenv("STARLING_BIGSTACK_PERCALL") != nil

    #if canImport(Darwin) && !(arch(wasm32))
    /// ONE long-lived thread with the big stack, fed by a queue: what `runIfSmall` hands its bodies to, so a paint every frame
    /// costs a wake-up and not a `pthread_create` with a 64 MB mapping. Jobs run one at a time, in order; the thread is made on
    /// the first hop, and nil when the system refused it (the caller then falls back to `run`).
    private final class Worker: @unchecked Sendable {
        static let shared: Worker? = Worker()
        private let cond = NSCondition()
        private var jobs: [() -> Void] = []

        private init?() {
            let started = BigStack._spawn { [self] in
                BigStack._markBigStack()
                while true {
                    cond.lock()
                    while jobs.isEmpty { cond.wait() }
                    let job = jobs.removeFirst()
                    cond.unlock()
                    job()
                }
            }
            if !started { return nil }
        }

        func submit(_ job: @escaping () -> Void) {
            cond.lock()
            jobs.append(job)
            cond.signal()
            cond.unlock()
        }
    }
    #endif

    /// The same for a body that throws.
    public static func run<T>(_ body: @escaping () throws -> T) throws -> T {
        try run { Result { try body() } }.get()
    }

    #if !(arch(wasm32) || !(canImport(Darwin) || canImport(Glibc)))
    private final class Job {
        let run: () -> Void
        /// The stack this job's thread was asked for, bytes.
        var stack = 0
        init(_ run: @escaping () -> Void) { self.run = run }

        /// Runs the body; `STARLING_BIGSTACK_LOG=1` first prints the thread's stack range (its top is read off a
        /// local, its bottom is `size` below that) so a fault address in a crash report can be placed against it:
        /// inside means a real overflow of the guard page or a wild pointer, far outside means not the stack.
        func start() {
            if BigStack.logRanges {
                var probe = 0
                withUnsafeMutablePointer(to: &probe) { p in
                    let top = UInt(bitPattern: p)
                    fputs("BigStack: thread stack 0x\(String(top - UInt(stack), radix: 16))-0x\(String(top, radix: 16)) (\(stack >> 20) MB)\n", stderr)
                }
            }
            run()
        }
    }

    private static let logRanges = getenv("STARLING_BIGSTACK_LOG") != nil
    /// A/B switch for a stress run: make the thread with `Foundation.Thread`, as this file did before it used
    /// `pthread_create` (no checking, no retry), to tell a crash of this change from one of the hop itself.
    private static let useFoundationThread = getenv("STARLING_BIGSTACK_FOUNDATION") != nil

    private static let flagKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()
    private static func _onBigStack() -> Bool { pthread_getspecific(flagKey) != nil }
    private static func _markBigStack() { pthread_setspecific(flagKey, UnsafeRawPointer(bitPattern: 1)) }

    private static func _refused() -> Bool {
        refusalLock.lock(); defer { refusalLock.unlock() }
        if simulatedRefusals > 0 { simulatedRefusals -= 1; return true }
        return false
    }

    /// One thread, detached, with `stack` bytes. False when the system refused it.
    private static func _create(_ job: Job, stack: Int) -> Int32 {
        if _refused() { return EAGAIN }
        job.stack = stack
        if useFoundationThread {
            let thread = Thread { job.start() }
            thread.stackSize = stack
            thread.start()
            return 0
        }
        var attr = pthread_attr_t()
        let initRC = pthread_attr_init(&attr)
        guard initRC == 0 else { return initRC }
        defer { pthread_attr_destroy(&attr) }
        pthread_attr_setstacksize(&attr, stack)
        pthread_attr_setdetachstate(&attr, Int32(PTHREAD_CREATE_DETACHED))
        let ref = Unmanaged.passRetained(job)
        #if canImport(Darwin)
        var tid: pthread_t? = nil
        let rc = pthread_create(&tid, &attr, { raw in
            Unmanaged<Job>.fromOpaque(raw).takeRetainedValue().start()
            return nil
        }, ref.toOpaque())
        #else
        var tid = pthread_t()
        let rc = pthread_create(&tid, &attr, { raw in
            Unmanaged<Job>.fromOpaque(raw!).takeRetainedValue().start()
            return nil
        }, ref.toOpaque())
        #endif
        if rc != 0 { ref.release() }
        return rc
    }

    /// Tries the full stack for about half a second (a refusal under load is usually brief), then 32 and 16 MB. Every
    /// refusal and every step down says so on stderr, with the errno and the size got, so a stress run shows what a
    /// crash was running on: a deep document needs 6 MB, and a smaller stack than the full one is a risk, not a cure.
    private static func _spawn(_ run: @escaping () -> Void) -> Bool {
        let job = Job(run)
        for stack in [size, size / 2, size / 4] {
            let attempts = stack == size ? 8 : 2
            for attempt in 0..<attempts {
                let rc = _create(job, stack: stack)
                if rc == 0 {
                    if stack != size { fputs("BigStack: thread got only \(stack >> 20) MB (the full \(size >> 20) MB was refused)\n", stderr) }
                    return true
                }
                fputs("BigStack: pthread_create refused a \(stack >> 20) MB stack (errno \(rc), attempt \(attempt + 1) of \(attempts))\n", stderr)
                usleep(UInt32(min(100_000, 2_000 << attempt)))
            }
        }
        fputs("BigStack: no thread could be created; running on the caller's stack\n", stderr)
        return false
    }
    #endif
}
