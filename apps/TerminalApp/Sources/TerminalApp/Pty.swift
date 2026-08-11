// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter   // realUserHomeDirectory()
import Foundation
#if os(Linux)
import Glibc
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
    /// (4 KB in practice), but bursts do occasionally fill this.
    static let slotCapacity = 65536
    private static let slotCount = 8

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
        while filled == ChunkRing.slotCount && !closed { cond.wait() }
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
        cond.broadcast()
        cond.unlock()
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
        cond.lock()
        while filled == 0 && !closed { cond.wait() }
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
        cond.broadcast()
        cond.unlock()
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
    // that Swift's Glibc module does not export.
    private static let TIOCSCTTY: UInt = 0x540E
    private static let TIOCSWINSZ: UInt = 0x5414

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

    init?(cols: Int, rows: Int) {
        // ── Master side ─────────────────────────────────────────────────
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

        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols),
                         ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, Pty.TIOCSWINSZ, &ws)

        // ── Prepare exec arguments BEFORE fork (no allocation after) ────
        let shellPath = Pty._shellPath()
        let home = Pty._homeDir()
        var argv: [UnsafeMutablePointer<CChar>?] = [
            strdup((shellPath as NSString).lastPathComponent),
            nil,
        ]
        var envp: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in ProcessInfo.processInfo.environment {
            if key == "TERM" || key == "HOME" { continue }
            envp.append(strdup("\(key)=\(value)"))
        }
        envp.append(strdup("TERM=xterm-256color"))
        envp.append(strdup("COLORTERM=truecolor"))
        envp.append(strdup("HOME=\(home)"))
        envp.append(nil)
        let shellPathC = strdup(shellPath)
        let homeC = strdup(home)

        // ── Fork + exec ─────────────────────────────────────────────────
        let pid = fork()
        if pid < 0 {
            close(master)
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
            if let homeC = homeC { _ = chdir(homeC) }
            if let path = shellPathC {
                execve(path, &argv, &envp)
            }
            _exit(127)
        }

        // Parent
        self.masterFd = master
        self.childPid = pid
        argv.forEach { free($0) }
        envp.forEach { free($0) }
        free(shellPathC)
        free(homeC)
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
        let reader = Thread { [weak self] in
            var pfd = pollfd(fd: -1, events: Int16(POLLIN), revents: 0)
            while true {
                guard let self = self else { return }
                // The slot is ours until we publish it, so reads land
                // straight in the ring — no chunk allocation, no copy.
                guard let slot = self.ring.acquireForWrite() else { return }
                pfd.fd = self.masterFd
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
                        if got > 0 { break }   // publish what is queued
                        pfd.revents = 0
                        let p = poll(&pfd, 1, -1)
                        if p < 0 && errno != EINTR {
                            self.ring.abandon(slot)
                            self.ring.close()
                            return
                        }
                        // POLLHUP with nothing readable = child side closed.
                        if pfd.revents & Int16(POLLHUP) != 0
                            && pfd.revents & Int16(POLLIN) == 0 {
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
                Glibc.write(masterFd, ptr.baseAddress, ptr.count)
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
        _ = ioctl(masterFd, Pty.TIOCSWINSZ, &ws)
    }

    func terminate() {
        kill(childPid, SIGHUP)
        close(masterFd)
    }
}

#endif  // !os(Windows)
