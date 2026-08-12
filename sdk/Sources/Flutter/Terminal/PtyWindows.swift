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

    /// Called on the reader thread with each chunk read from the console.
    var onData: (([UInt8]) -> Void)?

    /// Called on the reader thread when the child exits / the console closes.
    var onExit: (() -> Void)?

    private var readerThread: Thread?

    init?(cols: Int, rows: Int) {
        let command = Pty._shellCommand()
        let home = realUserHomeDirectory()
        guard let h = command.withCString({ cmd in
            home.withCString { cwd in
                starling_conpty_open(Int32(cols), Int32(rows), cmd, cwd)
            }
        }) else { return nil }
        handle = h
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

    /// Starts the reader loop on a background thread.
    func startReader() {
        let thread = Thread { [weak self] in
            // 64K for the same reason the POSIX side uses it: every read costs
            // an allocation, a feed and a repaint request, and a flooded
            // terminal fills the buffer every time.
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                guard let self = self else { return }
                // Take the handle under the lock so terminate() cannot free it
                // between the check and the call.
                self.handleLock.lock()
                guard let h = self.handle else {
                    self.handleLock.unlock()
                    return
                }
                self.handleLock.unlock()

                let n = buf.withUnsafeMutableBufferPointer { ptr in
                    starling_conpty_read(h, ptr.baseAddress, Int32(ptr.count))
                }
                if n > 0 {
                    self.onData?(Array(buf[0..<Int(n)]))
                } else {
                    self.onExit?()
                    return
                }
            }
        }
        thread.name = "pty-reader"
        thread.start()
        readerThread = thread
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

        // Join before freeing. Without this the reader could be dereferencing
        // the struct as it is released.
        if let t = readerThread, !t.isFinished {
            while !t.isFinished { Thread.sleep(forTimeInterval: 0.002) }
        }
        readerThread = nil

        handleLock.lock()
        handle = nil
        handleLock.unlock()
        starling_conpty_free(h)
    }
}
#endif  // os(Windows)
