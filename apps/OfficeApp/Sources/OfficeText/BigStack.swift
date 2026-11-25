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
/// never ran and the caller waited forever on the semaphore. Now a refused thread is retried, then tried with a
/// smaller stack, and as the last resort the body runs on the caller's own stack, as it did before the hop existed.
public enum BigStack {
    static let size = 64 << 20
    /// Test hook: this many of the next thread creations are treated as refused.
    nonisolated(unsafe) static var simulatedRefusals = 0
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

    /// The same for a body that throws.
    public static func run<T>(_ body: @escaping () throws -> T) throws -> T {
        try run { Result { try body() } }.get()
    }

    #if !(arch(wasm32) || !(canImport(Darwin) || canImport(Glibc)))
    private final class Job {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

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
    private static func _create(_ job: Job, stack: Int) -> Bool {
        if _refused() { return false }
        var attr = pthread_attr_t()
        guard pthread_attr_init(&attr) == 0 else { return false }
        defer { pthread_attr_destroy(&attr) }
        pthread_attr_setstacksize(&attr, stack)
        pthread_attr_setdetachstate(&attr, Int32(PTHREAD_CREATE_DETACHED))
        let ref = Unmanaged.passRetained(job)
        #if canImport(Darwin)
        var tid: pthread_t? = nil
        let rc = pthread_create(&tid, &attr, { raw in
            Unmanaged<Job>.fromOpaque(raw).takeRetainedValue().run()
            return nil
        }, ref.toOpaque())
        #else
        var tid = pthread_t()
        let rc = pthread_create(&tid, &attr, { raw in
            Unmanaged<Job>.fromOpaque(raw!).takeRetainedValue().run()
            return nil
        }, ref.toOpaque())
        #endif
        if rc != 0 { ref.release(); return false }
        return true
    }

    nonisolated(unsafe) private static var _reported = false

    /// Tries the full stack a few times (a refusal under load is usually brief), then smaller ones.
    private static func _spawn(_ run: @escaping () -> Void) -> Bool {
        let job = Job(run)
        for stack in [size, size / 2, size / 4, size / 8] {
            for attempt in 0..<3 {
                if _create(job, stack: stack) { return true }
                usleep(UInt32(2_000 << attempt))
            }
        }
        refusalLock.lock()
        let first = !_reported
        _reported = true
        refusalLock.unlock()
        if first { fputs("BigStack: no thread could be created; running on the caller's stack\n", stderr) }
        return false
    }
    #endif
}
