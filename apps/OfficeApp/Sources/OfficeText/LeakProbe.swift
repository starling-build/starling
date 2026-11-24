// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// Counts live instances of the classes that hold a document (a leak hunt: OFFICE_WINDOW_CYCLES prints them).
public final class LeakProbe {
    public nonisolated(unsafe) static var live: [String: Int] = [:]
    /// Address of every live RichDocumentController, by creation order: what a retainer scan looks for.
    public nonisolated(unsafe) static var controllers: [(seq: Int, address: UInt)] = []
    nonisolated(unsafe) private static var nextSeq = 0
    public static func register(controller: AnyObject) {
        nextSeq += 1
        controllers.append((nextSeq, UInt(bitPattern: Unmanaged.passUnretained(controller).toOpaque())))
    }
    public static func unregister(controller: AnyObject) {
        let a = UInt(bitPattern: Unmanaged.passUnretained(controller).toOpaque())
        controllers.removeAll { $0.address == a }
    }
    private let name: String
    public init(_ name: String) {
        self.name = name; Self.live[name, default: 0] += 1
    }
    deinit { Self.live[name, default: 0] -= 1 }
}
