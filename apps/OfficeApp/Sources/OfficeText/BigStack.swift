import Foundation

/// Runs a body on a thread with a large stack.
///
/// Word layout recurses (table inside table, footnote inside a table cell, a text box inside a header) and its
/// frames are big: in the release build `_StyledFrame.go` alone reserves ~565 KB, `flush` 86 KB, `_blk7` 53 KB.
/// An ordinary document needs 2-3 MB of stack and a nested table 4-6 MB (`--convert` under `ulimit -s`, 130
/// documents), against 8 MB for a Mac main thread and **1 MB for an iPad's** (512 KB on any other thread). A
/// debug build's frames are larger still, which is why four unit tests died with signal 11 on a Mac.
/// The browser build sets its stack at link time (16 MB), so it needs no hop.
public enum BigStack {
    static let size = 64 << 20
    private static let key = "starling.bigstack"

    private final class Box<T>: @unchecked Sendable {
        var value: T?
    }

    public static func run<T>(_ body: @escaping () -> T) -> T {
        #if arch(wasm32)
        return body()
        #else
        if Thread.current.threadDictionary[key] != nil { return body() }
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        let worker = Thread {
            Thread.current.threadDictionary[key] = true
            box.value = body()
            done.signal()
        }
        worker.stackSize = size
        worker.start()
        done.wait()
        return box.value!
        #endif
    }

    /// The same for a body that throws.
    public static func run<T>(_ body: @escaping () throws -> T) throws -> T {
        try run { Result { try body() } }.get()
    }
}
