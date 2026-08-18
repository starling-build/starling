// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// What N panes cost over a REAL ssh link — the two numbers milestone 4 of
// docs/plans/remote-workspace.md left open, because they cannot be had from a
// machine with no key-based ssh to anywhere.
//
//   swiftc -O -o link-bench link-bench.swift \
//       ../../sdk/Sources/Flutter/Terminal/TermdLink.swift \
//       ../../sdk/Sources/Flutter/Terminal/RemoteTerminal.swift
//   ./link-bench <host> [panes...]        # e.g. ./link-bench starling@lenovo 1 3 6 12
//
// This is a BENCHMARK, not a test: it needs a host you can reach without a
// password and it is not run by test/run.sh. `workspace-test.swift` next door
// is the test, and it deliberately needs no network at all.
//
// The thing under measurement is the real client. `RemoteTerminal.swift` is
// compiled in as itself — its spawn, its framing, its backoff, its reconnect
// loop — so what comes out is what a pane actually pays. The ONE substitution
// is the emulator: a pane feeds bytes into a `TerminalSession` that parses and
// lays out a grid, and none of that is in the path of opening an ssh channel.
// `BenchSession` below stands in for it and counts bytes instead, which keeps
// the numbers about the transport rather than about the parser.
//
// Two questions, and they are not the same question:
//
//   setup     — what does the Nth pane pay to come up? N panes each spawn
//               their own `ssh`, so this is N handshakes unless something
//               multiplexes them. The plan assumed it was already there; it
//               is not, and the difference it makes is measured by pointing
//               STARLING_SSH at a wrapper that turns it on:
//
//                   #!/bin/sh
//                   exec /usr/bin/ssh -o ControlMaster=auto \
//                       -o ControlPath=/tmp/starling-cm-%r@%h:%p \
//                       -o ControlPersist=60 "$@"
//   reconnect — a tunnel bounces and every pane notices at once. This kills
//               the harness's own ssh children and measures how long until
//               all N are live again, watching for new pids throughout so the
//               herd is counted rather than guessed at.
//
// The herd is counted as "busiest": the most dials STARTED inside one 250 ms
// window, which is what sshd's MaxStartups is compared against. Counting live
// ssh processes instead is the obvious thing and it is useless — a link's ssh
// stays up as long as its pane does, so the answer is N whether they dialed
// together or a minute apart. That mistake was made here first.

import Foundation

// MARK: - The stand-in emulator

/// What `RemoteTerminal` feeds. The real one parses; this one counts, because
/// the parser is not what an ssh handshake is waiting for.
public final class TerminalSession: @unchecked Sendable {
    private let lock = NSLock()
    private var _bytes = 0
    public var bytesFed: Int { lock.lock(); defer { lock.unlock() }; return _bytes }

    public var onOutput: ((String) -> Void)?
    public var onResize: ((Int, Int) -> Void)?

    public init() {}
    public func feed(_ bytes: [UInt8]) {
        lock.lock(); _bytes += bytes.count; lock.unlock()
    }
}

// MARK: - Timing helpers

func now() -> Double { Date().timeIntervalSince1970 }

/// Milliseconds, to the tenth — anything finer is noise on a network.
func ms(_ seconds: Double) -> String { String(format: "%.1f", seconds * 1000) + " ms" }

/// Right-align in a fixed column. `String(format: "%8s")` takes a C string and
/// bridging a Swift one through CVarArg to get there is a lie that compiles.
func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}

func pct(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let i = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
    return sorted[i]
}

/// Direct children of this process — every one of them a link's `ssh` (or, on
/// `local`, its daemon bridge). This is both how a tunnel is bounced (kill
/// them) and how the herd is seen (count them).
///
/// ZOMBIES ARE EXCLUDED, and that is the whole reason this is `ps` and not
/// `pgrep`. A killed ssh stays in the process table until its link's
/// `waitpid` reaps it, and `pgrep` lists it the entire time — so the moment
/// after a bounce reads as N+1 children when there are N. Counting only
/// processes that are not `Z` makes "peak" the number of links actually
/// dialing out, which is the number the herd question is about.
func sshChildren() -> [Int32] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    // And only children that are actually LINKS. The sampler thread and the
    // wait loop both call this, so two `sh` of our own can be alive at once
    // and would be counted as links — which is how a 6-pane bounce reported a
    // peak of 8.
    p.arguments = ["-c",
        "ps -o pid=,ppid=,stat=,comm= -ax | awk -v p=\(getpid()) "
        + "'$2==p && $3 !~ /Z/ && $4 ~ /ssh|termd/ {print $1}' || true"]
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    let mine = p.processIdentifier
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\n")
        .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        .filter { $0 != mine }
}

// MARK: - A pane under measurement

/// One pane: a `RemoteTerminal` plus the timestamps its link transitions
/// happened at. The callback fires on the link's own thread, hence the lock.
final class Pane: @unchecked Sendable {
    let index: Int
    let session = TerminalSession()
    let remote: RemoteTerminal

    private let lock = NSLock()
    private var _liveAt: Double?
    private var _lostAt: Double?
    private var _liveCount = 0

    /// When this pane most recently reached `.live`, and how many times it has.
    var liveAt: Double? { lock.lock(); defer { lock.unlock() }; return _liveAt }
    var lostAt: Double? { lock.lock(); defer { lock.unlock() }; return _lostAt }
    var liveCount: Int { lock.lock(); defer { lock.unlock() }; return _liveCount }

    init(index: Int, host: String, workspace: String) {
        self.index = index
        // Named, so a rerun reattaches instead of leaving a fresh shell behind
        // on the far machine every time this is run.
        self.remote = RemoteTerminal(session: session,
                                     host: host,
                                     name: "\(workspace)-\(index)")
        // A workspace pane's setting: the arrangement is the promise, so a
        // pane whose session went away opens a new one rather than dying.
        remote.reopenIfSessionGone = true
        // And a workspace pane's replay cap — 64 KB, what TerminalWorkspace
        // asks for. Without it the first attach of a busy session drags its
        // whole ring across the link and the number is about the backlog.
        remote.maxReplayBytes = 64 * 1024
        remote.onLink = { [weak self] link in
            guard let self = self else { return }
            self.lock.lock()
            switch link {
            case .live:
                self._liveAt = now()
                self._liveCount += 1
            case .reconnecting:
                if self._lostAt == nil { self._lostAt = now() }
            default:
                break
            }
            self.lock.unlock()
        }
    }

    /// Forget the last loss, so a second bounce measures itself.
    func armForBounce() { lock.lock(); _lostAt = nil; lock.unlock() }
}

func waitUntil(_ timeout: Double, _ cond: () -> Bool) -> Bool {
    let deadline = now() + timeout
    while now() < deadline {
        if cond() { return true }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return cond()
}

// MARK: - The two measurements

struct Setup {
    let wall: Double            // first start() to last .live
    let each: [Double]          // per pane, start() to its own .live
    let trace: DialTrace
}

/// Every pane started at once, the way opening a workspace starts them.
func measureSetup(_ panes: [Pane]) -> Setup? {
    let t0 = now()
    let watcher = DialWatcher(t0: t0, ignoring: sshChildren())
    for p in panes { p.remote.start() }
    let ok = waitUntil(120, { panes.allSatisfy { $0.liveAt != nil } })
    let trace = watcher.stop()
    guard ok else { return nil }
    let each = panes.compactMap { $0.liveAt }.map { $0 - t0 }
    return Setup(wall: (panes.compactMap { $0.liveAt }.max() ?? t0) - t0,
                 each: each, trace: trace)
}

/// When each link's `ssh` was STARTED, which is the only thing sshd's
/// `MaxStartups` counts.
///
/// The obvious metric — how many ssh processes are alive at once — answers a
/// different question and always answers it "N": a link's ssh stays up for as
/// long as the pane does, so twelve panes are twelve processes whether they
/// dialed together or a minute apart. What makes a storm a storm is how many
/// were in the HANDSHAKE at the same moment, so this watches for pids
/// appearing and records when each one did.
struct DialTrace {
    let appearedAt: [Double]    // seconds after t0, one per new child

    /// The most dials started inside any one window. `MaxStartups` counts
    /// connections that have not finished authenticating, so the window is
    /// about the length of one handshake — measured at ~250 ms to this host.
    func busiest(window: Double = 0.25) -> Int {
        var best = 0
        for start in appearedAt {
            let n = appearedAt.filter { $0 >= start && $0 < start + window }.count
            best = max(best, n)
        }
        return best
    }

    /// First dial to last — how far apart the pacer pulled them.
    var spread: Double { (appearedAt.max() ?? 0) - (appearedAt.min() ?? 0) }
}

/// Watches for new direct children and records when each appeared. Runs on its
/// own thread; `stop()` returns what it saw.
final class DialWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<Int32>()
    private var appeared: [Double] = []
    private var running = true
    private let t0: Double

    init(t0: Double, ignoring: [Int32]) {
        self.t0 = t0
        self.seen = Set(ignoring)
        Thread { [weak self] in
            while true {
                guard let self = self else { return }
                self.lock.lock()
                let go = self.running
                self.lock.unlock()
                if !go { return }
                let kids = sshChildren()
                self.lock.lock()
                for pid in kids where !self.seen.contains(pid) {
                    self.seen.insert(pid)
                    self.appeared.append(now() - self.t0)
                }
                self.lock.unlock()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }.start()
    }

    func stop() -> DialTrace {
        lock.lock(); running = false; let a = appeared; lock.unlock()
        return DialTrace(appearedAt: a.sorted())
    }
}

struct Bounce {
    let wall: Double            // kill to last pane live again
    let each: [Double]          // per pane, its own loss to its own recovery
    let trace: DialTrace
}

/// Kill every ssh and watch them all come back. The sessions on the far side
/// are untouched — that is the whole design — so this measures the client's
/// reconnect path and nothing else.
func measureBounce(_ panes: [Pane]) -> Bounce? {
    for p in panes { p.armForBounce() }
    let before = panes.map { $0.liveCount }

    let kill = sshChildren()
    let t0 = now()
    // The dying children are ignored by pid, so the watcher counts only the
    // ssh's that the RECONNECT starts.
    let watcher = DialWatcher(t0: t0, ignoring: kill)
    for pid in kill { Foundation.kill(pid, SIGKILL) }

    let ok = waitUntil(60, {
        zip(panes, before).allSatisfy { $0.0.liveCount > $0.1 }
    })
    let t1 = now()
    let trace = watcher.stop()
    guard ok else { return nil }

    let each = panes.compactMap { p -> Double? in
        guard let live = p.liveAt else { return nil }
        return live - (p.lostAt ?? t0)
    }
    return Bounce(wall: t1 - t0, each: each, trace: trace)
}

// MARK: - Driver

// `@main` rather than top-level code, for the same reason as
// workspace-test.swift next door: with more than one file on the swiftc
// command line, only a `main.swift` may hold statements.
@main
struct LinkBench {
  static func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        FileHandle.standardError.write(Data("""
        usage: link-bench <host> [panes...]
          host    an ssh destination reachable with no password (BatchMode=yes),
                  or "local" to spawn the daemon directly and see the floor.
          panes   pane counts to measure, default "1 3 6 12".

        env: STARLING_SSH     the ssh binary, or a wrapper adding ControlMaster
             STARLING_TERMD   the daemon's path on the far side

        """.utf8))
        exit(2)
    }

    let host = args[1]
    let counts = args.count > 2 ? args[2...].compactMap { Int($0) } : [1, 3, 6, 12]
    let label = ProcessInfo.processInfo.environment["STARLING_SSH"].map {
        " (STARLING_SSH=\(($0 as NSString).lastPathComponent))"
    } ?? ""

    print("link-bench — \(host)\(label)")
    print("")
    // "busiest" is the number sshd's MaxStartups is compared against: how many
    // dials landed inside one handshake's width. Ten is where a stock sshd
    // starts refusing them.
    print("  panes   setup wall   setup p50   bounce wall   bounce p50   busiest   spread")
    print("  -----   ----------   ---------   -----------   ----------   -------   ------")

    for n in counts {
        let ws = "bench\(n)"
        let panes = (0..<n).map { Pane(index: $0, host: host, workspace: ws) }

        guard let setup = measureSetup(panes) else {
            print("  \(n)  — TIMED OUT coming up; is \(host) reachable with BatchMode=yes?")
            for p in panes { p.remote.stop() }
            exit(1)
        }
        let sortedSetup = setup.each.sorted()

        // Let the links settle before knocking them down, so the bounce
        // measures a reconnect and not the tail of the first connect.
        Thread.sleep(forTimeInterval: 1.0)

        guard let bounce = measureBounce(panes) else {
            print("  \(n)  — TIMED OUT reconnecting")
            for p in panes { p.remote.stop() }
            exit(1)
        }
        let sortedBounce = bounce.each.sorted()

        print("  " + pad("\(n)", 5) + "   "
            + pad(ms(setup.wall), 10) + "   "
            + pad(ms(pct(sortedSetup, 0.5)), 9) + "   "
            + pad(ms(bounce.wall), 11) + "   "
            + pad(ms(pct(sortedBounce, 0.5)), 10) + "   "
            + pad("\(bounce.trace.busiest())/\(n)", 7) + "   "
            + pad(ms(bounce.trace.spread), 6))

        // Both phases dial, so both can storm. Worth seeing separately: a
        // first connect and a reconnect reach the pacer differently.
        if n > 1 {
            print("          on first connect: busiest "
                + "\(setup.trace.busiest())/\(n) in 250 ms, "
                + "spread \(ms(setup.trace.spread))")
        }

        for p in panes { p.remote.stop() }
        Thread.sleep(forTimeInterval: 0.5)
    }

    print("")
    print("done.")
  }
}
