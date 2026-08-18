// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The workspace client, against a real daemon — milestone 3 of
// docs/plans/remote-workspace.md.
//
//   swiftc -O workspace-test.swift \
//       ../../sdk/Sources/Flutter/Terminal/TermdLink.swift \
//       ../../sdk/Sources/Flutter/Terminal/RemoteWorkspace.swift \
//       ../../apps/TerminalApp/Sources/TerminalApp/PaneLayout.swift
//   STARLING_TERMD_SOCKET=<private> ./workspace-test <path to starling-termd>
//
// test/run.sh does exactly that. termd/test-termd.py already proves the
// daemon's half over a socketpair; this proves OUR half, and it proves it the
// only way that means anything — by spawning `starling-termd --stdio` the way
// ssh would, so the framing, the child transport and the daemon all have to
// agree at once.
//
// What is actually under test is the promise the whole plan rests on: an
// arrangement written by one connection is handed back, byte for byte, to a
// different connection later. Every check below is a way that could fail.
//
// The socket is required to come from the environment so a test run can never
// reach the daemon a person is using.

import Foundation

var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("  ok    \(name)")
    } else {
        print("  FAIL  \(name)\(detail().isEmpty ? "" : "  — " + detail())")
        failures.append(name)
    }
}

/// Callbacks arrive on the link's own thread; this is the handoff.
final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var _blob: [UInt8]?
    var blob: [UInt8]? {
        get { lock.lock(); defer { lock.unlock() }; return _blob }
        set { lock.lock(); _blob = newValue; lock.unlock() }
    }
}

func waitUntil(_ timeout: TimeInterval = 8, _ cond: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if cond() { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return cond()
}

/// Connect, and wait for the workspace to be resolved and its blob read back.
/// Returns the link and what the daemon was holding, or nil on a timeout.
func attach(_ name: String, _ termd: String) -> (RemoteWorkspace, [UInt8])? {
    let box = Box()
    let ws = RemoteWorkspace(name: name, host: "local", serverPath: termd)
    ws.onRestore = { blob in box.blob = blob }
    ws.start()
    guard waitUntil(8, { box.blob != nil && ws.workspaceId != nil }) else {
        ws.stop()
        return nil
    }
    return (ws, box.blob ?? [])
}

@main
struct WorkspaceTest {
  static func main() {
    guard CommandLine.arguments.count > 1 else {
        print("usage: workspace-test <path to starling-termd>")
        exit(2)
    }
    let termd = CommandLine.arguments[1]
    guard let socket = ProcessInfo.processInfo.environment["STARLING_TERMD_SOCKET"],
          !socket.isEmpty else {
        print("STARLING_TERMD_SOCKET must be set — a test must never reach a "
              + "daemon someone is using")
        exit(2)
    }

    // Our own daemon on that private socket, rather than the one a --stdio
    // bridge would start for itself: this way the test owns its lifetime and
    // SIGTERMs it on the way out instead of leaving an hour-long idle timer
    // behind. ChildLink is the same spawn the client uses.
    guard let daemon = ChildLink.spawn([termd, "--serve", "--idle-exit", "60"])
    else {
        print("could not start \(termd) --serve")
        exit(2)
    }
    // Closed on every path out, by hand: `exit` does not run a `defer`, and a
    // test that leaves a daemon behind is a test that poisons the next run.
    func finish(_ code: Int32) -> Never {
        daemon.close()
        exit(code)
    }
    // The socket appears a moment after the process does; every connection
    // below would otherwise race the first one into starting a SECOND daemon.
    _ = waitUntil(5) { FileManager.default.fileExists(atPath: socket) }

    // The arrangement under test: two panes side by side, the right one split
    // again, uneven ratios, and the focus on the last pane — a tree a person
    // could actually have made, rather than one contrived for the codec.
    let arrangement = PaneLayout(
        root: .split(axis: .row, ratio: 0.42,
                     first: .leaf(session: 7),
                     second: .split(axis: .column, ratio: 0.66,
                                    first: .leaf(session: 8),
                                    second: .leaf(session: 9))),
        activeLeaf: 2)
    let layoutA = arrangement.encoded()

    // --- a new workspace ------------------------------------------------
    guard let (ws1, blob1) = attach("wstest", termd) else {
        print("  FAIL  a workspace connection reaches the daemon")
        print("FAILED: no link")
        finish(1)
    }
    let id1 = ws1.workspaceId ?? 0
    check("a new workspace gets an id", id1 != 0)
    check("a new workspace restores nothing", blob1.isEmpty, "\(blob1.count) bytes")
    check("the link reports itself live", ws1.link == .live(workspace: id1),
          "\(ws1.link)")

    // stop() flushes: closing the window right after a split is the common
    // way to leave, and the split must not be the one thing that is lost.
    ws1.setLayout(layoutA)
    ws1.stop()

    // --- a different connection, later ----------------------------------
    guard let (ws2, blob2) = attach("wstest", termd) else {
        print("  FAIL  a second connection reaches the daemon")
        print("FAILED: no second link")
        finish(1)
    }
    check("the workspace is found again by name, with the same id",
          ws2.workspaceId == id1, "\(String(describing: ws2.workspaceId)) vs \(id1)")
    check("the layout survives the connection that wrote it",
          blob2 == layoutA, "\(blob2.count) bytes vs \(layoutA.count)")
    check("what comes back is the arrangement that went in",
          PaneLayout.decode(blob2) == arrangement)

    // --- the debounced write, without a flush behind it -----------------
    let moved = PaneLayout(
        root: .split(axis: .row, ratio: 0.75,
                     first: .leaf(session: 7),
                     second: .leaf(session: 8)),
        activeLeaf: 0)
    ws2.setLayout(moved.encoded())
    // Longer than RemoteWorkspace's debounce, and nothing is flushed: the
    // write has to happen on the link's own tick.
    Thread.sleep(forTimeInterval: 1.0)

    guard let (ws3, blob3) = attach("wstest", termd) else {
        print("FAILED: no third link"); finish(1)
    }
    check("a layout change lands without anyone closing the workspace",
          blob3 == moved.encoded(), "\(blob3.count) bytes")
    ws2.stop()

    // --- a blob this client would not understand ------------------------
    // Decision 5 of the plan: the daemon stores bytes, so a newer client's
    // layout must come back untouched and be REFUSED by the decoder rather
    // than half-read. Both halves are checked, because passing only the
    // second one is what "the daemon quietly rewrote it" looks like.
    var future = layoutA
    future[2] = 99
    ws3.setLayout(future)
    ws3.stop()

    guard let (ws4, blob4) = attach("wstest", termd) else {
        print("FAILED: no fourth link"); finish(1)
    }
    check("a blob from a newer client is stored verbatim", blob4 == future)
    check("...and this client degrades rather than misreading it",
          PaneLayout.decode(blob4) == nil)

    // --- the cap ---------------------------------------------------------
    // TERMD_MAX_BLOB. The daemon refuses an oversized write with an ERROR,
    // which would take the control link down; the client must not send it at
    // all. What proves that is the stored blob being untouched.
    ws4.setLayout([UInt8](repeating: 0x41, count: 17 * 1024))
    ws4.stop()

    guard let (ws5, blob5) = attach("wstest", termd) else {
        print("FAILED: no fifth link"); finish(1)
    }
    check("an oversized layout is refused by the client, not the daemon",
          blob5 == future, "\(blob5.count) bytes")

    // --- two clients on one workspace ------------------------------------
    // Milestone 6: last writer wins, and the loser is told. Without the
    // telling, the second client keeps its own tree and writes it back over
    // the first's on its next change — which is the flap this exists to stop.
    let watcher = Box()
    let ws6 = RemoteWorkspace(name: "wstest", host: "local", serverPath: termd)
    ws6.onRestore = { _ in }
    ws6.onLayoutChanged = { blob in watcher.blob = blob }
    ws6.start()
    _ = waitUntil(8, { ws6.workspaceId != nil })

    let theirs = PaneLayout(root: .split(axis: .column, ratio: 0.25,
                                         first: .leaf(session: 21),
                                         second: .leaf(session: 22)),
                            activeLeaf: 1).encoded()
    ws5.setLayout(theirs)
    ws5.flush()
    check("a second client is told when the first rearranges",
          waitUntil(5, { watcher.blob == theirs }),
          "\(watcher.blob?.count ?? -1) bytes")

    // And it ADOPTS: the arrangement it was told about is now what it would
    // write itself, so nobody trades the same tree back and forth.
    watcher.blob = nil
    ws6.setLayout(theirs)
    ws6.flush()
    check("adopting means not writing it straight back",
          watcher.blob == nil, "\(watcher.blob?.count ?? -1) bytes")
    ws6.stop()

    // --- a session that is not there -------------------------------------
    // A pane can exit between its ATTACHED and the WS_ADD that joins it. That
    // is ordinary, and it must not take the workspace's link down with it.
    ws5.add(session: 999_999)
    Thread.sleep(forTimeInterval: 0.5)
    check("a WS_ADD for a dead session leaves the link up",
          ws5.link == .live(workspace: id1), "\(ws5.link)")
    ws5.stop()

    print("")
    if failures.isEmpty {
        print("all workspace checks passed")
        finish(0)
    } else {
        print("FAILED: \(failures.joined(separator: ", "))")
        finish(1)
    }
  }
}
