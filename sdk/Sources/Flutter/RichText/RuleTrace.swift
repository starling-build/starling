// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if os(Linux)
import Glibc
#elseif os(macOS) || os(iOS)
import Darwin
#endif

/// Which documents reach a rule. A fix puts `RuleTrace.hit("name")` on the
/// branch it changed; with `OFFICE_RULE_TRACE=<file>` set, a run of the
/// candidate over the corpus appends "document<TAB>name" to that file the
/// first time each document reaches the branch, and the documents named
/// are the ones the fix can move (`OfficeApp --trace-rules <docx>` lays a
/// document out without writing its PDF, for a quick pass over all of them;
/// `test/tools/docx-sweep.sh --trace`).
///
/// With the variable unset it does nothing: one test of a constant, no
/// state kept and nothing written, so no score can depend on it. Never
/// branch on it, and name the rule for the document that fires it
/// ("t238-own-break-lead"), not for the file.
public enum RuleTrace {
    #if os(Linux) || os(macOS) || os(iOS)
    private static let path: String? = {
        guard let p = ProcessInfo.processInfo.environment["OFFICE_RULE_TRACE"], !p.isEmpty else { return nil }
        return p
    }()
    private nonisolated(unsafe) static var seen = Set<String>()
    private static let lock = NSLock()
    #endif

    /// The document being laid out, as the trace names it (its file name
    /// without the extension); the app sets it when it opens one.
    public nonisolated(unsafe) static var document = ""

    /// Whether a trace is being written.
    public static var isOn: Bool {
        #if os(Linux) || os(macOS) || os(iOS)
        return path != nil
        #else
        return false
        #endif
    }

    /// This document has reached the rule `name`.
    public static func hit(_ name: StaticString) {
        #if os(Linux) || os(macOS) || os(iOS)
        guard let path else { return }
        let rule = name.description
        lock.lock()
        defer { lock.unlock() }
        guard seen.insert(document + "\t" + rule).inserted else { return }
        // (One write to a file opened for appending: whole lines, however
        // many documents are being traced at once.)
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        let line = Array((document + "\t" + rule + "\n").utf8)
        _ = line.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        close(fd)
        #endif
    }
}
