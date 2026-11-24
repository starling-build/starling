// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// Counts live instances of the classes that hold a document (a leak hunt: OFFICE_WINDOW_CYCLES prints them).
public final class LeakProbe {
    public nonisolated(unsafe) static var live: [String: Int] = [:]
    private let name: String
    public init(_ name: String) {
        self.name = name; Self.live[name, default: 0] += 1
    }
    deinit { Self.live[name, default: 0] -= 1 }
}
