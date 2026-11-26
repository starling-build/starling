// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Counts live instances of the classes that hold a document (a leak hunt: OFFICE_WINDOW_CYCLES prints them).
///
/// Off unless `STARLING_LEAK_PROBE` or `OFFICE_WINDOW_CYCLES` is set: a leak counter must not cost every
/// RichLayout made or released a change to a global table, and it must not be a way to corrupt one. It did both:
/// the tables are global, a RichLayout is made on one thread and released on another (a conversion lays out on
/// the BigStack thread; a decode task can hold the last reference), and a Dictionary changed from two threads
/// corrupts its storage. The crash was in `Dictionary.subscript.modify` (`LeakProbe.deinit` under
/// `RichLayout.deinit`): one run in two on a Mac for a 700 KB deck once layout ran off the main thread, 17 in 1500
/// parallel renders on Linux. With the probe on, every change is under a lock.
public final class LeakProbe {
    public static let enabled = getenv("STARLING_LEAK_PROBE") != nil || getenv("OFFICE_WINDOW_CYCLES") != nil
    private static let lock = OfficeLock()
    public nonisolated(unsafe) static var live: [String: Int] = [:]
    /// Address of every live RichDocumentController, by creation order: what a retainer scan looks for.
    public nonisolated(unsafe) static var controllers: [(seq: Int, address: UInt)] = []
    nonisolated(unsafe) private static var nextSeq = 0
    public static func register(controller: AnyObject) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        nextSeq += 1
        controllers.append((nextSeq, UInt(bitPattern: Unmanaged.passUnretained(controller).toOpaque())))
    }
    public static func unregister(controller: AnyObject) {
        guard enabled else { return }
        let a = UInt(bitPattern: Unmanaged.passUnretained(controller).toOpaque())
        lock.lock(); defer { lock.unlock() }
        controllers.removeAll { $0.address == a }
    }
    private static func count(_ name: String, by delta: Int) {
        lock.lock(); defer { lock.unlock() }
        live[name, default: 0] += delta
    }
    private let name: String
    public init(_ name: String) {
        self.name = name
        if Self.enabled { Self.count(name, by: 1) }
    }
    deinit { if Self.enabled { Self.count(name, by: -1) } }
}
