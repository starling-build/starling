// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Windows half of Pty. Same type, same surface as the POSIX one in
// Pty.swift — TerminalApp.swift does not know which it is talking to.
//
// The mechanism underneath is quite different: ConPTY rather than forkpty, a
// command line rather than an argv, and no SIGWINCH (ResizePseudoConsole
// notifies the attached application itself). All of that lives in the C shim;
// what is left here is the reader thread and the shutdown ordering.

#if os(Windows)
import CStarlingConPTY
import Foundation

/// A pseudo-terminal running a shell process.
///
/// Opens a pseudoconsole and starts the shell attached to it. A dedicated
/// reader thread delivers output via `onData`; `write` sends keyboard bytes;
/// `resize` updates the console size.
final class Pty: @unchecked Sendable {

    /// The C shim's `StarlingConPty*`. Freed in `terminate()`, and only after
    /// the reader thread has been joined — the shim deliberately splits
    /// shutdown from free so an in-flight read stays valid while being woken.
    private var handle: OpaquePointer?
    private let handleLock = NSLock()

    /// Called on the PARSER thread with each chunk read from the console. The
    /// buffer is owned by the PTY and is valid only for the duration of the
    /// call — copy anything that has to outlive it. (Same zero-copy contract
    /// as the POSIX side, which moved to pointer+count with the read-path
    /// split; this side follows so TerminalApp.swift stays host-neutral.)
    var onData: ((UnsafePointer<UInt8>, Int) -> Void)?

    /// Called on the parser thread once every queued chunk has been delivered
    /// and the child has exited / the console has closed.
    var onExit: (() -> Void)?

    private var readerThread: Thread?
    private var parserThread: Thread?
    private let ring = ChunkRing()

    // Diagnostic only: total bytes handed to the emulator, reported on stderr
    // at exit when STARLING_PTY_BYTES is set. Used to compare what different
    // console hosts actually emit for the same input.
    fileprivate static let _countBytes =
        ProcessInfo.processInfo.environment["STARLING_PTY_BYTES"] != nil
    fileprivate static var _bytesSeen = 0
    fileprivate static var _bytesReported = 0
    fileprivate static var _chunks = 0

    /// `command` nil runs the shell interactively; a command line runs
    /// through it, with the flag that shell spells "run this and exit".
    init?(cols: Int, rows: Int, command: String? = nil) {
        Pty._scrubMultiplexerEnv()
        let shell = Pty._shellCommand()
        let line = command.map { Pty._commandLine(shell: shell, running: $0) } ?? shell
        let home = realUserHomeDirectory()
        guard let h = line.withCString({ cmd in
            home.withCString { cwd in
                starling_conpty_open(Int32(cols), Int32(rows), cmd, cwd)
            }
        }) else { return nil }
        handle = h
    }

    /// Drop the multiplexer markers (see `Pty.multiplexerMarkers`) from THIS
    /// process, because that is the only lever here: `starling_conpty_open`
    /// takes no environment block, so CreateProcessW copies ours wholesale and
    /// a per-spawn filter — what the POSIX side does — has nowhere to live.
    /// Mutating our own environment is safe in the way that matters: nothing
    /// in an app hosting a terminal reads these, and a terminal that forwards
    /// them tells every child it is running under a multiplexer it is not.
    static func _scrubMultiplexerEnv() {
        for key in Pty.multiplexerMarkers where getenv(key) != nil {
            _ = key.withCString { unsetenv($0) }
        }
    }

    /// The shell to run: `STARLING_DEV_SHELL` when set (same override the
    /// POSIX side honours), else `$SHELL`, else PowerShell, else `%COMSPEC%`.
    ///
    /// PowerShell ahead of cmd.exe because it drives the emulator far harder —
    /// colour, cursor positioning and line editing all go through the escape
    /// sequences this app exists to render — and it is present on every
    /// supported Windows. cmd.exe remains the guaranteed fallback.
    ///
    /// This is a command line, not a path: CreateProcessW parses it, so a
    /// shell needing arguments can be given them through STARLING_DEV_SHELL.
    private static func _shellCommand() -> String {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        if let dev = env["STARLING_DEV_SHELL"], !dev.isEmpty { return dev }
        if let shell = env["SHELL"], fm.isExecutableFile(atPath: shell) { return shell }

        let root = env["SystemRoot"] ?? "C:\\Windows"
        let powershell = root + "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
        if fm.fileExists(atPath: powershell) { return powershell }
        if let comspec = env["COMSPEC"], fm.fileExists(atPath: comspec) { return comspec }
        return root + "\\System32\\cmd.exe"
    }

    /// The command line that runs `command` under `shell` and exits. Each
    /// shell spells that differently, and the shell here is a command line
    /// rather than a path (STARLING_DEV_SHELL may carry arguments), so the
    /// switch is on what the executable is named.
    private static func _commandLine(shell: String, running command: String) -> String {
        let lower = shell.lowercased()
        if lower.contains("powershell") || lower.contains("pwsh") {
            return "\(shell) -NoLogo -Command \(command)"
        }
        if lower.contains("cmd.exe") {
            return "\(shell) /c \(command)"
        }
        return "\(shell) -c \"\(command)\""   // bash/zsh from an MSYS-style install
    }

    /// Starts the reader and parser threads.
    ///
    /// They are separate for the same reason as on POSIX (see the long note in
    /// Pty.swift): a single thread that reads then parses stops draining the
    /// console while it parses, so the shell blocks on a full pipe and the wall
    /// time becomes transport PLUS parse instead of max(transport, parse).
    /// This side kept the serial loop long after Linux was split, and the
    /// Windows benchmark showed exactly the shape that predicts —
    /// `01_light_cells`, the workload with the least escape processing and the
    /// most raw line traffic, was 2.24x Windows Terminal while the
    /// escape-heavy workloads were already at or ahead of parity.
    func startReader() {
        let reader = Thread { [weak self] in
            while true {
                guard let self = self else { return }
                // The slot is ours until we publish it, so ConPTY reads land
                // straight in the ring — no per-chunk buffer, no copy.
                guard let slot = self.ring.acquireForWrite() else { return }

                // Take the handle under the lock so terminate() cannot free it
                // between the check and the call.
                self.handleLock.lock()
                guard let h = self.handle else {
                    self.handleLock.unlock()
                    self.ring.abandon(slot)
                    self.ring.close()
                    return
                }
                self.handleLock.unlock()

                var got = 0
                while true {
                    let n = starling_conpty_read(
                        h, slot.base + got, Int32(ChunkRing.slotCapacity - got))
                    if n > 0 {
                        got += Int(n)
                        if got == ChunkRing.slotCapacity { break }
                        // Drain what is ALREADY queued into the same slot, and
                        // stop the moment the pipe is dry. ConPTY hands back
                        // small reads even mid-flood, and each publish costs a
                        // ring pass plus an emulator lock and a repaint
                        // schedule. Peeking coalesces only bytes the pipe had
                        // waiting, so a lone keystroke echo still publishes
                        // immediately — batching buys throughput without
                        // costing latency.
                        if starling_conpty_avail(h) <= 0 { break }
                        continue
                    }
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
                    if Pty._countBytes {
                        let avg = Pty._bytesSeen / max(1, Pty._chunks)
                        let msg = "PTYBYTES \(Pty._bytesSeen) chunks \(Pty._chunks) avg \(avg)\n"
                        FileHandle.standardError.write(Data(msg.utf8))
                    }
                    self.onExit?()
                    return
                }
                if Pty._countBytes {
                    Pty._bytesSeen += chunk.count
                    Pty._chunks += 1
                    // Report as we go, not at EOF: with ConPTY the console
                    // holds the pipe open after the shell exits, so an
                    // end-of-stream report may never arrive.
                    if Pty._bytesSeen - Pty._bytesReported >= 8 << 20 {
                        Pty._bytesReported = Pty._bytesSeen
                        let avg = Pty._bytesSeen / max(1, Pty._chunks)
                        let msg = "PTYBYTES \(Pty._bytesSeen) chunks \(Pty._chunks) avg \(avg)\n"
                        FileHandle.standardError.write(Data(msg.utf8))
                    }
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
    func write(_ bytes: [UInt8]) {
        handleLock.lock()
        guard let h = handle else { handleLock.unlock(); return }
        handleLock.unlock()

        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBufferPointer { ptr -> Int32 in
                starling_conpty_write(h, ptr.baseAddress! + offset,
                                      Int32(bytes.count - offset))
            }
            if n <= 0 { return }
            offset += Int(n)
        }
    }

    func write(_ text: String) {
        write(Array(text.utf8))
    }

    /// Updates the console size. ConPTY tells the attached application; there
    /// is no signal to deliver.
    func resize(cols: Int, rows: Int) {
        handleLock.lock()
        defer { handleLock.unlock() }
        guard let h = handle else { return }
        starling_conpty_resize(h, Int32(cols), Int32(rows))
    }

    func terminate() {
        handleLock.lock()
        guard let h = handle else { handleLock.unlock(); return }
        handleLock.unlock()

        // Shut down first: that closes the console and wakes the reader, which
        // is still allowed to be inside starling_conpty_read on `h`.
        starling_conpty_shutdown(h)

        // Shutdown only wakes a reader parked in ReadFile. With the ring in
        // front of the parser the reader can instead be parked in
        // acquireForWrite waiting for a free slot, which no console close
        // reaches — so close the ring too. This also releases the parser once
        // it has drained, which is what lets both threads below finish.
        ring.close()

        // Join before freeing. Without this the reader could be dereferencing
        // the struct as it is released.
        for t in [readerThread, parserThread] {
            guard let t = t else { continue }
            while !t.isFinished { Thread.sleep(forTimeInterval: 0.002) }
        }
        readerThread = nil
        parserThread = nil

        handleLock.lock()
        handle = nil
        handleLock.unlock()
        starling_conpty_free(h)
    }
}
#endif  // os(Windows)
