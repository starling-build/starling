// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A terminal: the emulator plus, optionally, a child process on a PTY.
///
/// The controller half of the terminal widget (docs/plans/terminal-widget.md).
/// Two ways to use it:
///
///   - `startShell()` spawns the user's shell on a PTY sized to the grid;
///     output feeds the emulator, `write(_:)` reaches the child, and
///     `onExit` fires when it dies. `startCommand(_:)` runs one program
///     instead — a log tail, a build, an agent — on the same PTY.
///   - Headless: skip `startShell()` and own the byte streams yourself —
///     `feed(_:)` is terminal input (an SSH channel, a replay file, a remote
///     agent's pty) and `onOutput` carries what the terminal sends back
///     (query responses and, via `write(_:)`, the user's keystrokes).
///
/// Threading: the PTY reader feeds the emulator under `lock`; any read of
/// the emulator's grid or state must hold `lock` too. `onActivity` fires on
/// the reader thread after new output lands — throttle repaints there, do
/// not read the grid inside it without taking the lock.
public final class TerminalSession {

    /// The emulator: grid, scrollback, modes, responses. Reads require `lock`.
    public let emulator: TerminalEmulator

    /// Guards `emulator`. The session's feed paths take it themselves.
    public let lock = NSLock()

    /// True after the child process exits (cleared by `startShell()`).
    public private(set) var processExited = false

    /// New output landed (or the child exited) — repaint when convenient.
    /// Fires on the reader thread.
    public var onActivity: (() -> Void)?

    /// The child process exited. Fires on the reader thread, after the
    /// exit message has been fed to the grid.
    public var onExit: (() -> Void)?

    /// Headless only: bytes the terminal emits — query responses, and
    /// whatever `write(_:)` is given. Unused while a PTY is attached.
    public var onOutput: ((String) -> Void)?

    var pty: Pty?

    public init(cols: Int = 80, rows: Int = 24) {
        emulator = TerminalEmulator(cols: cols, rows: rows)
        emulator.onResponse = { [weak self] text in
            guard let self = self else { return }
            if let pty = self.pty { pty.write(text) } else { self.onOutput?(text) }
        }
    }

    /// What this session runs: nil for the user's interactive shell, else the
    /// command line given to `startCommand(_:)`. `restart()` repeats it.
    public private(set) var command: String? = nil

    /// Spawn the user's shell on a PTY sized to the current grid. On failure
    /// a message is fed to the grid and `false` returned.
    @discardableResult
    public func startShell() -> Bool { _start(nil) }

    /// Run one command on a PTY instead of an interactive shell — a log tail,
    /// a build, an agent. The command line goes through the user's shell
    /// (`sh -c` and its per-platform equivalent), so PATH lookup, pipelines
    /// and redirection work exactly as they would when typed.
    ///
    /// Everything else is unchanged: output feeds the emulator, `write(_:)`
    /// reaches the child's stdin, and `onExit` fires when it finishes.
    @discardableResult
    public func startCommand(_ command: String) -> Bool { _start(command) }

    /// Run again whatever this session ran last — the shell, or the command.
    /// This is what a view offers after the child exits; restarting a
    /// dashboard pane as an interactive shell would not be the same terminal.
    @discardableResult
    public func restart() -> Bool { _start(command) }

    private func _start(_ command: String?) -> Bool {
        self.command = command
        processExited = false
        let (cols, rows) = (emulator.cols, emulator.rows)
        guard let pty = Pty(cols: cols, rows: rows, command: command) else {
            lock.lock()
            emulator.feed(Array("failed to start \(command ?? "shell")\r\n".utf8))
            lock.unlock()
            onActivity?()
            return false
        }
        self.pty = pty
        pty.onData = { [weak self] bytes, count in
            guard let self = self else { return }
            self.lock.lock()
            self.emulator.feed(bytes, count: count)
            self.lock.unlock()
            self.onActivity?()
        }
        pty.onExit = { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.processExited = true
            self.emulator.feed(Array("\r\n[process exited — press Enter to restart]\r\n".utf8))
            self.lock.unlock()
            self.onExit?()
            self.onActivity?()
        }
        pty.startReader()
        return true
    }

    /// Headless terminal input (PTY sessions feed themselves).
    public func feed(_ bytes: [UInt8]) {
        lock.lock()
        emulator.feed(bytes)
        lock.unlock()
        onActivity?()
    }

    /// User input: to the child process, or headless to `onOutput`.
    public func write(_ text: String) {
        if let pty = pty { pty.write(text) } else { onOutput?(text) }
    }
    public func write(_ bytes: [UInt8]) {
        if let pty = pty { pty.write(bytes) }
        else { onOutput?(String(decoding: bytes, as: UTF8.self)) }
    }

    /// Resize the child process's window. The emulator's own resize is the
    /// caller's, under `lock` — views resize the grid from layout, then tell
    /// the process (see TerminalApp's build), so the two calls cannot be
    /// fused here without taking `lock` recursively.
    public func resizeProcess(cols: Int, rows: Int) {
        pty?.resize(cols: cols, rows: rows)
    }

    /// Terminate the child process, if any.
    public func terminate() {
        pty?.terminate()
        pty = nil
    }
}
