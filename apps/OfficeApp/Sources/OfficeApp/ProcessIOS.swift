// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// iOS has no Foundation.Process: an app cannot spawn another program. The
// Site publisher (git), the update check (curl) and "open in browser"
// (open/xdg-open) are written against it for the desktop, so on iOS they get
// this stand-in whose run() always fails, and every one of them already treats
// a failed launch as "not available here". It exists so the shared sources
// compile unchanged; nothing on iOS is meant to reach it.

#if os(iOS)
import Foundation

final class Process {
    struct Unavailable: Error, CustomStringConvertible {
        var description: String { "this platform cannot run other programs" }
    }
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardInput: Any?
    var standardOutput: Any?
    var standardError: Any?
    private(set) var terminationStatus: Int32 = 127
    func run() throws { throw Unavailable() }
    func waitUntilExit() {}
}
#endif
