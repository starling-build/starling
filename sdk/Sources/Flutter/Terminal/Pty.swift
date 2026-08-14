// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import CTerminalCore
import Foundation
#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// `write(2)`, spelled out with its defining module.
///
/// `Pty.write(_:)` shadows the C function inside the class, so the call has to
/// name the module — and the module's name is the one thing that differs by
/// platform. Guarded like the POSIX `Pty` below rather than left at file
/// scope: Windows has neither module, and its own PTY lives in
/// PtyWindows.swift.
#if !os(Windows)
@inline(__always)
private func _sysWrite(_ fd: Int32, _ buf: UnsafeRawPointer?, _ count: Int) -> Int {
    #if os(Linux)
    return Glibc.write(fd, buf, count)
    #else
    return Darwin.write(fd, buf, count)
    #endif
}
#endif

/// A bounded ring of fixed-size buffers handed from the PTY reader thread to
/// the parser thread.
///
/// Blocking in both directions: the reader waits for a free slot and the parser
/// waits for a filled one, so a flood still applies backpressure to the shell
/// exactly as the old single-threaded read loop did — it just stops making the
/// shell wait for the *parser* as well as for the read.
///
/// Slots are allocated once. The reader owns a slot until it publishes it and
/// the parser owns it until it releases it, so no slot is ever aliased and the
/// bytes need no copy on either side.
final class ChunkRing: @unchecked Sendable {

    /// A read never returns more than the PTY line discipline has buffered
    /// (4 KB in practice on Linux), but bursts do occasionally fill this.
    /// Darwin is different: its pty hands back ~1 KB per read no matter the
    /// buffer, and the reader's linger (see startReader) keeps one slot
    /// filling across those, so slots there routinely fill to the brim —
    /// bigger ones mean fewer ring passes. 256 KB is the knee (ptyread
    /// mode 9 on `cat 03_sgr_fg`: 64 KB 0.528 s, 256 KB 0.506, 512 KB
    /// 0.504); fewer, larger slots keep the ring's footprint at 1 MB.
    #if canImport(Darwin)
    static let slotCapacity = 262144
    private static let slotCount = 4
    #else
    static let slotCapacity = 65536
    private static let slotCount = 8
    #endif

    struct Slot {
        let index: Int
        let base: UnsafeMutablePointer<UInt8>
        let count: Int
    }

    private let storage: UnsafeMutablePointer<UInt8>
    private var lengths = [Int](repeating: 0, count: ChunkRing.slotCount)
    private var head = 0          // parser reads here
    private var tail = 0          // reader writes here
    private var filled = 0
    private var closed = false
    private let cond = NSCondition()
    // Wake discipline: strace during `cat 02_dense_cells` put us at 2.5x
    // ghostty's futex traffic (11.4k vs 4.5k calls per five cats), and the
    // surplus was this ring — a broadcast on every publish AND every release,
    // waking a thread that then re-checks a predicate it usually already
    // knew. Each needless futex round trip is a scheduler pass that competes
    // with the writer->kworker->reader pipeline the pty's throughput hangs
    // on. So: wake only a side that is actually waiting (signal, not
    // broadcast — one reader, one parser), and note there is no lost-wakeup
    // race because the flags are read and the signal sent under the same
    // lock the waiter holds around its predicate check.
    private var parserWaiting = false
    private var readerWaiting = false

    init() {
        storage = UnsafeMutablePointer<UInt8>.allocate(
            capacity: ChunkRing.slotCapacity * ChunkRing.slotCount)
    }

    deinit { storage.deallocate() }

    private func base(_ index: Int) -> UnsafeMutablePointer<UInt8> {
        storage + index * ChunkRing.slotCapacity
    }

    /// Reader side: claim the next free slot, blocking while the ring is full.
    /// `nil` once the ring is closed.
    func acquireForWrite() -> Slot? {
        cond.lock()
        while filled == ChunkRing.slotCount && !closed {
            readerWaiting = true
            cond.wait()
            readerWaiting = false
        }
        if closed { cond.unlock(); return nil }
        let index = tail
        cond.unlock()
        return Slot(index: index, base: base(index), count: 0)
    }

    /// Reader side: hand a filled slot to the parser.
    func publish(_ slot: Slot, count: Int) {
        cond.lock()
        lengths[slot.index] = count
        tail = (tail + 1) % ChunkRing.slotCount
        filled += 1
        let wake = parserWaiting
        cond.unlock()
        // Signal AFTER unlock: glibc has no wait morphing, so signalling with
        // the mutex held wakes the parser straight into a mutex it cannot
        // take — two extra futex round trips per handoff ("hurry up and
        // wait"). Signalling outside is safe: the predicate (`filled`) was
        // updated under the lock, and a signal to a non-waiter is a no-op.
        if wake { cond.signal() }
    }

    /// Reader side: give a claimed slot back unfilled (EINTR, or shutting down).
    /// Nothing was published, so this only has to not advance `tail`.
    func abandon(_ slot: Slot) {}

    func close() {
        cond.lock()
        closed = true
        cond.broadcast()
        cond.unlock()
    }

    /// Parser side: the next filled slot, blocking. `nil` once the ring is both
    /// drained and closed — never before, so no output is dropped on exit.
    func nextForRead() -> Slot? {
        // (A bounded nap-poll before the wait was tried here and measured
        // WORSE on `cat 02_dense_cells` — a 50us nanosleep is the same
        // scheduler round trip as the futex wake it replaces, fired on a
        // timer instead of on data. Wake on publish, once, is right.)
        cond.lock()
        while filled == 0 && !closed {
            parserWaiting = true
            cond.wait()
            parserWaiting = false
        }
        if filled == 0 { cond.unlock(); return nil }
        let index = head
        let count = lengths[index]
        cond.unlock()
        return Slot(index: index, base: base(index), count: count)
    }

    /// Parser side: done with a slot; the reader may fill it again.
    func release(_ slot: Slot) {
        cond.lock()
        head = (head + 1) % ChunkRing.slotCount
        filled -= 1
        let wake = readerWaiting
        cond.unlock()
        if wake { cond.signal() }
    }
}

// The POSIX implementation. PtyWindows.swift provides the same type, with the
// same surface, over ConPTY — Windows has no forkpty and no SIGWINCH.
#if !os(Windows)

/// A pseudo-terminal running a shell process.
///
/// Opens the PTY master, forks, and execs the shell on the slave side with
/// TERM=xterm-256color. A dedicated reader thread delivers master output via
/// `onData`; `write` sends keyboard bytes; `resize` updates the kernel window
/// size (which delivers SIGWINCH to the foreground process group).
final class Pty: @unchecked Sendable {

    // ioctl request numbers (linux, generic): these are macros in C headers
    // that Swift's Glibc module does not export. Linux-only: the values are
    // BSD `_IOW`-encoded and entirely different on Darwin (TIOCSWINSZ is
    // 0x80087467 there, not 0x5414), and Darwin's overlay does export its
    // own — so hardcoding these for both platforms would silently address
    // the wrong ioctl. The Darwin branch of `init` needs neither.
    #if os(Linux)
    private static let TIOCSCTTY: UInt = 0x540E
    private static let TIOCSWINSZ: UInt = 0x5414
    #endif

    /// Markers a terminal multiplexer leaves behind, which the shell we spawn
    /// would otherwise inherit and BELIEVE. We are the terminal here: whatever
    /// launched this app — a tmux pane, a screen session — is not what the
    /// child is talking to, and a program that adapts its drawing to its host
    /// (Claude Code underlines every line under tmux) then draws for the wrong
    /// one. Setting TERM is not enough; these are read independently of it.
    /// Same list as build/run-desktop.sh, build/session/starling-session and
    /// termd's scrub_multiplexer_env — a terminal that forwards them is a
    /// terminal lying about itself.
    static let multiplexerMarkers: Set<String> = [
        "TMUX", "TMUX_PANE", "TERM_PROGRAM", "TERM_PROGRAM_VERSION",
        "STY", "WINDOW",
    ]

    let masterFd: Int32
    let childPid: pid_t

    /// Called on the PARSER thread with each chunk read from the master. The
    /// buffer is owned by the PTY and is valid only for the duration of the
    /// call — copy anything that has to outlive it.
    var onData: ((UnsafePointer<UInt8>, Int) -> Void)?

    /// Called on the parser thread once every queued chunk has been delivered
    /// and the child has exited / the PTY has closed.
    var onExit: (() -> Void)?

    private var readerThread: Thread?
    private var parserThread: Thread?
    private let ring = ChunkRing()

    /// A pipe the reader polls alongside the master, so `terminate()` can wake
    /// it deterministically. Closing the master under a blocked `poll()` is
    /// not specified to wake anything, and a reader left polling a closed fd
    /// is worse than a leak: the number gets reused and the thread starts
    /// reading whatever lands on it next.
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1
    /// Set before the wake, read by the reader once it is out of poll().
    private var terminating = false

    /// `command` nil runs the shell interactively; a command line runs
    /// through it (`-c`), so PATH and pipelines behave as when typed.
    init?(cols: Int, rows: Int, command: String? = nil) {
        // Declared before the platform split because Darwin needs it there:
        // forkpty applies the window size in the same call that opens the
        // master, while Linux ioctls it onto the master further down.
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols),
                         ws_xpixel: 0, ws_ypixel: 0)

        // ── Master side ─────────────────────────────────────────────────
        // Linux only: Darwin opens the master inside forkpty (see below), so
        // there is nothing to do here on that platform.
        #if os(Linux)
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { return nil }
        guard grantpt(master) == 0, unlockpt(master) == 0 else {
            close(master)
            return nil
        }
        var nameBuf = [CChar](repeating: 0, count: 256)
        guard ptsname_r(master, &nameBuf, nameBuf.count) == 0 else {
            close(master)
            return nil
        }
        let slavePath = String(cString: nameBuf)

        _ = ioctl(master, Pty.TIOCSWINSZ, &ws)
        #endif

        // ── Prepare exec arguments BEFORE fork (no allocation after) ────
        let shellPath = Pty._shellPath()
        let home = Pty._homeDir()
        var argv: [UnsafeMutablePointer<CChar>?] = [
            strdup((shellPath as NSString).lastPathComponent),
        ]
        if let command = command {
            argv.append(strdup("-c"))
            argv.append(strdup(command))
        }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in ProcessInfo.processInfo.environment {
            if key == "TERM" || key == "HOME" { continue }
            if Pty.multiplexerMarkers.contains(key) { continue }
            envp.append(strdup("\(key)=\(value)"))
        }
        envp.append(strdup("TERM=xterm-256color"))
        envp.append(strdup("COLORTERM=truecolor"))
        envp.append(strdup("HOME=\(home)"))
        envp.append(nil)
        let shellPathC = strdup(shellPath)
        let homeC = strdup(home)

        // Releases everything strdup'd above. The child never reaches it (it
        // execs or _exits), so this runs on the parent and on the failure
        // paths below.
        func freeExecArgs() {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
            free(shellPathC)
            free(homeC)
        }

        // ── Fork + exec ─────────────────────────────────────────────────
        #if os(Linux)
        let pid = fork()
        if pid < 0 {
            close(master)
            freeExecArgs()
            return nil
        }
        if pid == 0 {
            // Child: only async-signal-safe calls from here.
            setsid()
            let slave = slavePath.withCString { open($0, O_RDWR) }
            if slave < 0 { _exit(127) }
            _ = ioctl(slave, Pty.TIOCSCTTY, 0)
            dup2(slave, 0)
            dup2(slave, 1)
            dup2(slave, 2)
            if slave > 2 { close(slave) }
            close(master)
            // Everything else in this fd table belongs to the app, not the
            // shell it is about to become — and one `nohup`ed descendant
            // holding a stray copy keeps the desktop from ever seeing the
            // app die (see the header comment on this function).
            starling_close_extra_fds()
            if let homeC = homeC { _ = chdir(homeC) }
            if let path = shellPathC {
                execve(path, &argv, &envp)
            }
            _exit(127)
        }
        #else
        // Darwin: Swift's overlay marks `fork()` unavailable outright, and
        // forkpty is the BSD call that does precisely what the Linux branch
        // hand-rolls — open the master, fork, setsid, make the slave the
        // child's controlling terminal, and dup it onto 0/1/2 — applying the
        // window size in the same step. So the child here only has to chdir
        // and exec, and neither TIOCSCTTY nor TIOCSWINSZ is needed.
        var master: Int32 = -1
        let pid = forkpty(&master, nil, nil, &ws)
        if pid < 0 {
            freeExecArgs()
            return nil
        }
        if pid == 0 {
            // Child: only async-signal-safe calls from here. forkpty has
            // already put the slave on 0/1/2; drop every other inherited fd
            // (see the Linux branch).
            starling_close_extra_fds()
            if let homeC = homeC { _ = chdir(homeC) }
            if let path = shellPathC {
                execve(path, &argv, &envp)
            }
            _exit(127)
        }
        #endif

        // Parent. CLOEXEC on the master: a copy that leaks through some
        // other fork site would keep this pty open after the terminal dies,
        // and the shell inside it would never get its hangup.
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        self.masterFd = master
        self.childPid = pid
        freeExecArgs()
    }

    /// The shell to run: the Starling devbox when configured (terminal
    /// sessions live in the developer toolbox — a persistent, mutable
    /// container over the sealed base; see starling-os tools/dev-shell.sh),
    /// else $SHELL, else bash/sh.
    private static func _shellPath() -> String {
        let fm = FileManager.default
        if let dev = ProcessInfo.processInfo.environment["STARLING_DEV_SHELL"],
           fm.isExecutableFile(atPath: dev) {
            return dev
        }
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           fm.isExecutableFile(atPath: shell) {
            return shell
        }
        for candidate in ["/bin/bash", "/usr/bin/bash", "/bin/sh"] {
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/bin/sh"
    }

    /// The home directory for the shell. In dev mode the shell runs under
    /// sudo, so HOME is /root — realUserHomeDirectory() resolves the invoking
    /// account instead.
    private static func _homeDir() -> String { realUserHomeDirectory() }

    /// Starts the reader and parser threads.
    ///
    /// They are separate on purpose. A single thread that reads then parses
    /// stops draining the PTY while it parses, so the shell blocks on a full
    /// buffer and the wall time becomes transport PLUS parse. Splitting them
    /// makes it max(transport, parse): measured against a real PTY and the real
    /// core, `alt_screen` 0.101 -> 0.078 s, `sgr_truecolor` 0.463 -> 0.317,
    /// `sgr_fg` 0.336 -> 0.241, and no workload got slower (test/bench/core,
    /// `ptyread.c` modes 0 and 3). Ghostty sits exactly on the transport floor
    /// on the workloads where we did not; this is why.
    func startReader() {
        #if canImport(Darwin)
        // The paced reader is the DEFAULT since 2026-08-14: suite wall -10%,
        // unicode cat -29%, 07_alt_screen -23% against inline, at +33% CPU
        // while streaming (see _startReaderPaced for the mechanism).
        // STARLING_TERM_READER=inline opts back into the single-thread
        // baseline, kept in-tree unchanged as the comparison point.
        if ProcessInfo.processInfo.environment["STARLING_TERM_READER"] == "inline" {
            _startReaderInline()
        } else {
            _startReaderPaced()
        }
        return
        #else
        _startReaderRing()
        #endif
    }

    #if canImport(Darwin)
    /// The pthread behind `readerThread`, so `terminate()` can interrupt a
    /// blocking read (see `_readerWakeSignal`).
    private var readerPthread: pthread_t?

    /// A signal whose handler does nothing and which is installed WITHOUT
    /// SA_RESTART, so delivering it makes an in-flight `read(2)` return
    /// EINTR. `signal(2)` cannot be used: on Darwin it installs BSD-style
    /// handlers with SA_RESTART set, so read would resume and never notice
    /// that the terminal is shutting down.
    private static let _readerWakeSignal: Int32 = SIGUSR2
    private static let _installReaderWake: Bool = {
        var sa = sigaction()
        sa.__sigaction_u.__sa_handler = { _ in }
        sa.sa_flags = 0
        sigemptyset(&sa.sa_mask)
        return sigaction(Pty._readerWakeSignal, &sa, nil) == 0
    }()

    /// Darwin: ONE thread, blocking reads, parse inline — no ring, no parser
    /// thread.
    ///
    /// The split exists to overlap transport with parse, and on this platform
    /// it is a net loss: the pty hands back ~1 KB per read regardless of
    /// buffer size, so the ring pays a condition-variable round trip to
    /// parallelise a kilobyte of parse work — microseconds of parse behind
    /// tens of microseconds of handoff. Worse, non-blocking reads see an
    /// EAGAIN between every pair, so each kilobyte costs two syscalls plus a
    /// poll; blocking reads cost one.
    ///
    /// `test/bench/core/ptyread.c`, best of 2 at 201x47, wall in seconds:
    ///
    ///     workload          mode 0 (this)  mode 9 (the ring + linger)
    ///     02_dense_cells        0.114          0.169
    ///     03_sgr_fg             0.402          0.552
    ///     08_scroll_region      0.159          0.242
    ///     01_light_cells        0.127          0.099
    ///     05_unicode            0.372          0.316
    ///
    /// It loses exactly where the CORE is slowest per byte — light_cells at
    /// 81 MB/s and unicode at 336, against 500-750 for the three it wins —
    /// because that is where there is enough parse work to be worth
    /// overlapping. Net over the ten-workload suite: 2.345 s against 2.901,
    /// -19%.
    ///
    /// Mode 10 in that harness is the obvious "best of both" — parse inline
    /// while the parser keeps up, hand to the ring when it does not — and it
    /// measured WORSE THAN EITHER on every one of the five (0.126 / 0.431 /
    /// 0.176 / 0.157 / 0.476). It pays the ring's bookkeeping and loses the
    /// single-thread locality without buying back the overlap. Do not retry
    /// that shape without a different mechanism.
    // SWITCHING BETWEEN THE TWO AT RUNTIME: TRIED, AND THE SIGNAL IS NOT
    // THERE.
    //
    // Inline loses two of the ten workloads, so an adaptive reader — inline
    // until the parse becomes the bottleneck, then hand the fd to the ring —
    // looks obvious. Two shapes were built and measured, and both are worse
    // than simply picking one:
    //
    //   * `ptyread` mode 10 flips per slot when the drain ends dry and the
    //     ring is empty. It measured WORSE THAN EITHER fixed choice on all
    //     five workloads tried (e.g. 03_sgr_fg 0.431 against inline's 0.402
    //     and the ring's 0.552).
    //   * A hysteretic one-way handover on measured cost: time the read and
    //     the feed, hand over once a 512 KB window says the parse is the
    //     larger term. Live, it collapsed onto the ring's numbers (suite
    //     2.878 s against the ring's 2.931 and inline's 2.514) because with
    //     data always queued a read returns instantly and the parse ALWAYS
    //     looks dominant.
    //
    // The measured parse/read ratio does not predict the winner at all.
    // Median over 512 KB windows, against which design actually wins:
    //
    //     03_sgr_fg        1.81   inline wins by 28%
    //     01_light_cells   1.47   ring wins by 37%
    //     05_unicode       1.00   ring wins by 21%
    //     08_scroll_region 0.95   inline wins by 29%
    //     02_dense_cells   0.86   inline wins by 28%
    //
    // The workload with the HIGHEST parse share is one inline wins outright.
    // Whatever separates these two groups, it is not the balance between
    // reading and parsing, so do not rebuild this switch on that signal.

    private func _startReaderInline() {
        _ = Pty._installReaderWake
        let reader = Thread { [weak self] in
            guard let self = self else { return }
            self.readerPthread = pthread_self()
            let cap = ChunkRing.slotCapacity
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
            defer { buf.deallocate() }

            // Which of the two halves is actually the bottleneck, measured
            // rather than assumed — this is what the two workloads inline
            // reading LOSES have in common, and the reason the switch is not
            // a platform #if.
            //
            // Inline wins whenever the parse is cheap next to the transport,
            // which is most content: 02_dense_cells, 03_sgr_fg,
            // 08_scroll_region and 09_long_lines each come in 28% faster.
            // 01_light_cells (+37%) and 05_unicode (+21%) go the other way,
            // and they are precisely the streams the core is slowest on — 81
            // and 336 MB/s against 500-750 for the rest. There, parsing while
            // nobody drains the pty stalls the writer, and the ring's second
            // thread pays for itself.
            //
            // So: time both halves, and once a window's worth of bytes says
            // the parse is the larger term, hand the fd to the ring reader and
            // retire this thread. One-way and hysteretic on purpose — mode 10
            // in `ptyread` flips per slot on a cheaper proxy (is the ring
            // empty) and lands worse than either fixed choice.
            while true {
                if self.terminating { break }
                let n = read(self.masterFd, buf, cap)
                if n > 0 {
                    // Straight into the emulator on this thread. The buffer is
                    // ours until the call returns, which is the same contract
                    // the ring gave the parser thread.
                    self.onData?(UnsafePointer(buf), n)
                    continue
                }
                if n < 0 && errno == EINTR { continue }
                break   // EOF (the child closed its side) or a hard error
            }
            // Every byte read has been parsed by the time this runs, so the
            // exit message cannot overtake the output that preceded it —
            // the property the ring's drain-then-close gave us.
            self.onExit?()
        }
        reader.name = "pty-reader"
        readerThread = reader
        reader.start()
    }

    /// Darwin: TWO threads — a ~1us-paced reader and a batch parser — the
    /// design that finally overlaps transport with parse on this platform.
    ///
    /// Every earlier ring lost to inline because its reader was EAGER: re-arm
    /// read(2) immediately and you catch the tty queue empty, sleeping a full
    /// writer-wake round trip per kilobyte (~242 MB/s ceiling, measured with
    /// a read-and-discard probe). The inline reader's parse accidentally
    /// paced it into lockstep (~282 MB/s on ascii) — but on escape-dense
    /// content the parse overshoots the refill window and the same mechanism
    /// collapses (07_alt_screen at 209, 40% behind ghostty live). A fixed
    /// ~1us busy pace after each read keeps the lockstep on EVERY content
    /// shape: the probe (scratch ptyread_mac mode 13, 2026-08-14) holds
    /// ~290 MB/s on ascii, alt_screen and unicode alike, against inline's
    /// 282/209/229. The pace value is flat across 0.8-1.6us and collapses
    /// past ~3us; mach_wait_until cannot replace the busy wait (the kernel
    /// stretches 1us sleeps ~5x and the pipeline falls to the eager floor).
    ///
    /// The consumer polls the ring with a 500us sleep when empty — an eager
    /// consumer's wake storms cost ~8% of throughput, and 8 MB of ring is
    /// ~26 ms of slack at full rate. onExit fires from the PARSE thread after
    /// the drain, preserving inline's ordering property (every byte parsed
    /// before the exit message).
    private func _startReaderPaced() {
        _ = Pty._installReaderWake
        let paceNs = UInt64(ProcessInfo.processInfo.environment["STARLING_TERM_PACE_NS"] ?? "") ?? 1000
        guard let ring = st_ring_new(8 << 20) else { _startReaderInline(); return }

        let reader = Thread { [weak self] in
            guard let self = self else { st_ring_close(ring); return }
            self.readerPthread = pthread_self()
            let cap = ChunkRing.slotCapacity
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
            defer {
                buf.deallocate()
                st_ring_close(ring)     // the producer's last touch; the parser frees
            }
            while true {
                if self.terminating { break }
                let n = read(self.masterFd, buf, cap)
                if n > 0 {
                    st_ring_write(ring, buf, n)
                    if paceNs > 0 { st_pace(paceNs) }
                    continue
                }
                if n < 0 && errno == EINTR { continue }
                break   // EOF or hard error
            }
        }
        let parser = Thread { [weak self] in
            var span: UnsafePointer<UInt8>? = nil
            while true {
                let n = st_ring_take(ring, &span)
                if n == 0 { break }
                if let self = self, let p = span { self.onData?(p, Int(n)) }
                st_ring_consume(ring, n)
            }
            st_ring_free(ring)
            self?.onExit?()
        }
        reader.name = "pty-reader"
        parser.name = "pty-parser"
        readerThread = reader
        parser.start()
        reader.start()
    }
    #endif

    private func _startReaderRing() {
        // Non-blocking + poll, so the reader can DRAIN into a slot: the pty
        // returns ~600-byte reads during a flood no matter how big the buffer
        // is, and publishing each one cost a ring pass — two NSCondition
        // lock/broadcast round-trips, an emulator-lock acquisition and a
        // repaint schedule — per ~700 bytes. strace during `cat 150mb_ascii`
        // showed 34k futex calls (50% of traced time) against ghostty's 6.5k.
        // Filling the slot from consecutive reads until it is full or the pty
        // is EMPTY collapses ~200k ring passes into ~2.8k (mean batch ~54 KB,
        // measured in test/bench/core/ptyread.c mode 4) while coalescing only
        // bytes already queued in the kernel: a lone keystroke echo still
        // publishes the moment the pty runs dry, so latency is unchanged.
        let fl = fcntl(masterFd, F_GETFL, 0)
        _ = fcntl(masterFd, F_SETFL, fl | O_NONBLOCK)
        var wake = [Int32](repeating: -1, count: 2)
        if pipe(&wake) == 0 {
            // CLOEXEC: this pipe is reader-thread plumbing, and the same
            // object forks shells — without the flag every job the shell
            // starts inherits both ends.
            _ = fcntl(wake[0], F_SETFD, FD_CLOEXEC)
            _ = fcntl(wake[1], F_SETFD, FD_CLOEXEC)
            wakeRead = wake[0]
            wakeWrite = wake[1]
        }
        let reader = Thread { [weak self] in
            var pfds = [pollfd(fd: -1, events: Int16(POLLIN), revents: 0),
                        pollfd(fd: -1, events: Int16(POLLIN), revents: 0)]
            #if canImport(Darwin)
            // Darwin's pty returns ~1 KB per read no matter the buffer size,
            // with an EAGAIN between every pair — so "drain until empty"
            // degenerates to one ~1 KB publish per ring pass and the slot
            // never fills (ptyread mode 4: 71 762 feeds, 1013 B mean batch,
            // on a 72.7 MB cat). The fix is to wait out the gap: on EAGAIN
            // with data already in hand, linger briefly for the next burst
            // instead of publishing. The wait must be event-driven — the pty
            // queue is that same ~1 KB deep, the writer blocks until we
            // drain it, so a blind nanosleep gates the whole stream at one KB
            // per linger (measured: 46 s for the same cat). kevent gives a
            // wake-on-data wait with a sub-ms timeout (poll's is
            // ms-granular); mid-flood it returns in microseconds and only a
            // genuinely quiet pty pays the full window. 278 feeds, 261 KB
            // mean batch, 0.653 s -> 0.506 against a 0.474 read floor.
            let kq = kqueue()
            if kq >= 0, let self = self {
                var reg = kevent()
                reg.ident = UInt(self.masterFd)
                reg.filter = Int16(EVFILT_READ)
                reg.flags = UInt16(EV_ADD)
                _ = kevent(kq, &reg, 1, nil, 0, nil)
            }
            defer { if kq >= 0 { close(kq) } }
            #endif
            while true {
                guard let self = self else { return }
                if self.terminating { self.ring.close(); return }
                // The slot is ours until we publish it, so reads land
                // straight in the ring — no chunk allocation, no copy.
                guard let slot = self.ring.acquireForWrite() else { return }
                pfds[0].fd = self.masterFd
                pfds[1].fd = self.wakeRead
                var got = 0
                while true {
                    let n = read(self.masterFd, slot.base + got,
                                 ChunkRing.slotCapacity - got)
                    if n > 0 {
                        got += n
                        if got == ChunkRing.slotCapacity { break }
                        continue
                    }
                    if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                        if got > 0 {
                            #if canImport(Darwin)
                            // Mid-fill EAGAIN: linger (see above). Data
                            // within the window: keep filling this slot.
                            // Quiet for the whole window: genuine pause —
                            // publish, so a lone keystroke echo still goes
                            // out fast (the 400 us here is the only latency
                            // the linger ever adds, and only mid-burst; the
                            // first byte after idle still takes the blocking
                            // poll below). Window length is uncritical:
                            // 200 us / 400 us / 1 ms measured alike.
                            if kq >= 0 {
                                var timeout = timespec(tv_sec: 0, tv_nsec: 400_000)
                                var ev = kevent()
                                let kr = kevent(kq, nil, 0, &ev, 1, &timeout)
                                if kr > 0 { continue }
                                if kr < 0 && errno == EINTR { continue }
                            }
                            #endif
                            break   // publish what is queued
                        }
                        pfds[0].revents = 0
                        pfds[1].revents = 0
                        let count: nfds_t = self.wakeRead >= 0 ? 2 : 1
                        let p = poll(&pfds, count, -1)
                        if p < 0 && errno != EINTR {
                            self.ring.abandon(slot)
                            self.ring.close()
                            return
                        }
                        // terminate() woke us: stop before touching the master
                        // again, so the fd can be closed with no reader on it.
                        if self.terminating || pfds[1].revents != 0 {
                            self.ring.abandon(slot)
                            self.ring.close()
                            return
                        }
                        // POLLHUP with nothing readable = child side closed.
                        if pfds[0].revents & Int16(POLLHUP) != 0
                            && pfds[0].revents & Int16(POLLIN) == 0 {
                            self.ring.abandon(slot)
                            self.ring.close()
                            return
                        }
                        continue
                    }
                    if n < 0 && errno == EINTR { continue }
                    // EOF or hard error: hand over what we have, then close.
                    if got > 0 { self.ring.publish(slot, count: got) }
                    else { self.ring.abandon(slot) }
                    self.ring.close()
                    return
                }
                self.ring.publish(slot, count: got)
            }
        }
        reader.name = "pty-reader"

        let parser = Thread { [weak self] in
            while true {
                guard let self = self else { return }
                guard let chunk = self.ring.nextForRead() else {
                    // Drained and closed: every byte the shell wrote has been
                    // parsed before anyone is told it exited.
                    self.onExit?()
                    return
                }
                self.onData?(UnsafePointer(chunk.base), chunk.count)
                self.ring.release(chunk)
            }
        }
        parser.name = "pty-parser"

        readerThread = reader
        parserThread = parser
        reader.start()
        parser.start()
    }

    /// Writes bytes to the shell's input.
    ///
    /// The master fd is O_NONBLOCK (the reader drains it — see startReader),
    /// so a large paste can fill the kernel's input buffer mid-write. That
    /// surfaces as EAGAIN, not a short write; wait for writability and resume
    /// rather than silently dropping the tail of the paste.
    func write(_ bytes: [UInt8]) {
        var remaining = bytes[...]
        var pfd = pollfd(fd: masterFd, events: Int16(POLLOUT), revents: 0)
        while !remaining.isEmpty {
            let n = remaining.withUnsafeBytes { ptr -> Int in
                _sysWrite(masterFd, ptr.baseAddress, ptr.count)
            }
            if n > 0 {
                remaining = remaining.dropFirst(n)
                continue
            }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                pfd.revents = 0
                if poll(&pfd, 1, 1000) <= 0 { return }  // shell gone or wedged
                continue
            }
            if n < 0 && errno == EINTR { continue }
            return
        }
    }

    func write(_ text: String) {
        write(Array(text.utf8))
    }

    /// Updates the kernel's window size (SIGWINCH is delivered to the child).
    func resize(cols: Int, rows: Int) {
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols),
                         ws_xpixel: 0, ws_ypixel: 0)
        // Darwin exports the real request number to Swift; Glibc does not, so
        // Linux uses the transcribed constant above.
        #if os(Linux)
        _ = ioctl(masterFd, Pty.TIOCSWINSZ, &ws)
        #else
        _ = ioctl(masterFd, TIOCSWINSZ, &ws)
        #endif
    }

    /// Ends the child and stops the reader.
    ///
    /// The signal goes to the process GROUP, not the pid: the child called
    /// `setsid()` and leads its own group, and what is actually wedged is
    /// usually something it spawned — a dropped `ssh`, a build that stopped
    /// answering. Signalling only the shell leaves that orphan holding the
    /// far end of the PTY, so the next read never ends and a "restart" gets
    /// a terminal that is still stuck.
    ///
    /// SIGHUP is what a closing terminal sends; a process ignoring it (or
    /// blocked in uninterruptible I/O on a dead socket) gets SIGKILL a
    /// moment later. The wait reaps the child — without it every restart
    /// leaves a zombie.
    func terminate() {
        terminating = true
        #if canImport(Darwin)
        // The inline reader is parked in a BLOCKING read on the master, which
        // closing the fd is not specified to wake. Signal it instead: the
        // handler does nothing, but the delivery makes read return EINTR and
        // the loop then sees `terminating`.
        if let t = readerPthread { pthread_kill(t, Pty._readerWakeSignal) }
        #endif
        if wakeWrite >= 0 {
            var byte: UInt8 = 1
            // `_sysWrite`, not `Glibc.write`: that module does not exist on
            // Darwin, which is the whole reason the shim at the top of this
            // file is there.
            _ = _sysWrite(wakeWrite, &byte, 1)
        }
        kill(-childPid, SIGHUP)
        kill(childPid, SIGHUP)

        let pid = childPid
        let master = masterFd
        let wr = wakeWrite, rd = wakeRead
        DispatchQueue.global().async {
            var status: Int32 = 0
            // Give the group a moment to go on its own, then insist.
            for _ in 0 ..< 25 {
                if waitpid(pid, &status, WNOHANG) != 0 { break }
                usleep(10_000)
            }
            if waitpid(pid, &status, WNOHANG) == 0 {
                kill(-pid, SIGKILL)
                kill(pid, SIGKILL)
                _ = waitpid(pid, &status, 0)
            }
            // Only now is nobody polling the master.
            close(master)
            if wr >= 0 { close(wr) }
            if rd >= 0 { close(rd) }
        }
    }
}

#endif  // !os(Windows)
