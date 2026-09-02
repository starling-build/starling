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

    /// Who `onActivity` belongs to. A view installs its hook on mount and
    /// clears it on dispose — but element remount is the dominant update
    /// path in this framework, and the replacement is mounted BEFORE the old
    /// element is disposed. An unconditional `onActivity = nil` in dispose
    /// therefore wipes the hook the new view just installed, and the pane
    /// keeps its shell, its keyboard and its cursor while never painting
    /// again. Clear the hook only when you still own it.
    public weak var activityOwner: AnyObject?

    /// The child process exited. Fires on the reader thread, after the
    /// exit message has been fed to the grid.
    public var onExit: (() -> Void)?

    /// Headless only: bytes the terminal emits — query responses, and
    /// whatever `write(_:)` is given. Unused while a PTY is attached.
    public var onOutput: ((String) -> Void)?

    /// Headless only: the view resized the grid and there is no local PTY to
    /// tell. Whoever owns the byte stream owns the far end's window size —
    /// for a remote session that is a RESIZE frame.
    public var onResize: ((Int, Int) -> Void)?

    /// Rules that type an answer when a prompt they recognise is on screen,
    /// or nil — the default — for a terminal that answers nothing.
    ///
    /// See TerminalAutoAnswer: it is a blind pattern match, it fires only
    /// after output settles, and it belongs to exactly one session because the
    /// latch that stops a prompt being answered twice is per-screen.
    public var autoAnswer: TerminalAutoAnswer?

    /// A rule fired and its keys have been written. Main queue.
    ///
    /// Wire this to something the user can see. A machine typing into a
    /// terminal must be visible as a machine typing into a terminal — the view
    /// raises its badge, which is the whole reason this callback exists rather
    /// than the write just happening quietly.
    public var onAutoAnswer: ((TerminalAutoAnswer.Rule) -> Void)?

    /// Guarded by `lock`. `pending` is the debounce's "a check is already on
    /// the queue", `lastOutput` what it debounces against.
    private var _autoAnswerPending = false
    private var _autoAnswerLastOutput: TimeInterval = 0

    var pty: Pty?

    #if os(macOS)
    /// Anti-throttling assertion, held only while output streams.
    ///
    /// After ~15 s of sustained pty streaming macOS demotes the app's
    /// coalition (App Nap / timer coalescing) — and the CHILD shares the
    /// coalition, so both ends of the pty land on slow wakes and the
    /// pipeline collapses ~10-15x: DOOM-Fire's 3rd consecutive run fell
    /// from ~1080 fps to 100-200 with both processes asleep in read/write,
    /// while paints, priorities, tty modes and fd flags all measured
    /// normal. `beginActivity([.userInitiated, .latencyCritical])`
    /// eliminates it (4x6000-frame kill test, 2026-08-14). The display-off
    /// benchmark collapse in the -long round was the same demotion,
    /// triggered instantly by occlusion. Held per-session while bytes
    /// flow; dropped after 5 s of quiet so an idle terminal still naps.
    /// Fields are guarded by `lock`; the check runs on the main queue.
    private var _throttleToken: NSObjectProtocol?
    private var _lastOutput: TimeInterval = 0
    private var _throttleCheckPending = false
    private static let _throttleIdleQuiet: TimeInterval = 5

    func _noteOutputActivity() {
        lock.lock()
        _lastOutput = ProcessInfo.processInfo.systemUptime
        let needBegin = _throttleToken == nil
        if needBegin {
            _throttleToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "terminal output streaming")
        }
        let needCheck = !_throttleCheckPending
        if needCheck { _throttleCheckPending = true }
        lock.unlock()
        if needCheck { _scheduleThrottleCheck(after: Self._throttleIdleQuiet) }
    }

    private func _scheduleThrottleCheck(after s: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let idle = ProcessInfo.processInfo.systemUptime - self._lastOutput
            if idle >= Self._throttleIdleQuiet {
                self._throttleCheckPending = false
                let token = self._throttleToken
                self._throttleToken = nil
                self.lock.unlock()
                if let token { ProcessInfo.processInfo.endActivity(token) }
            } else {
                self.lock.unlock()
                self._scheduleThrottleCheck(after: Self._throttleIdleQuiet - idle)
            }
        }
    }

    func _endOutputActivity() {
        lock.lock()
        let token = _throttleToken
        _throttleToken = nil
        lock.unlock()
        if let token { ProcessInfo.processInfo.endActivity(token) }
    }
    #endif

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
    ///
    /// This is both what a view offers after the child exits and the way out
    /// of a terminal that is stuck rather than finished: an `ssh` whose
    /// connection died, a program that stopped reading its input. A live
    /// child is killed first (`terminate()` signals the whole process group,
    /// so the wedged thing on the far end goes too), the scrollback is kept,
    /// and a fresh PTY takes its place.
    @discardableResult
    public func restart() -> Bool { _start(command) }

    private func _start(_ command: String?) -> Bool {
        self.command = command
        autoAnswer?.reset()
        // Restarting over a live child would leave it holding the far end of
        // a PTY nobody reads any more.
        if pty != nil { terminate() }
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
        // Both handlers check that they still belong to the CURRENT pty. A
        // restart leaves the old one's parser thread draining whatever the
        // dead child had already written, and it ends by reporting an exit —
        // into a session that has since moved on. Unguarded, restarting a
        // stuck terminal prints "[process exited]" over the new shell's first
        // prompt and marks the fresh session as dead.
        pty.onData = { [weak self, weak pty] bytes, count in
            guard let self = self, self.pty === pty else { return }
            self.lock.lock()
            self.emulator.feed(bytes, count: count)
            self.lock.unlock()
            #if os(macOS)
            self._noteOutputActivity()
            #endif
            self._autoAnswerActivity()
            self.onActivity?()
        }
        pty.onExit = { [weak self, weak pty] in
            guard let self = self, self.pty === pty else { return }
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
        _autoAnswerActivity()
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
        if let pty = pty { pty.resize(cols: cols, rows: rows) }
        else { onResize?(cols, rows) }
    }

    // MARK: - Auto-answer

    /// Output landed. Arm (or re-arm) the settle timer.
    ///
    /// This is on the byte path, so it does as little as a debounce can: a
    /// timestamp and, at most once per burst, one `asyncAfter`. Nothing polls
    /// — an idle terminal with rules loaded schedules no work at all, which is
    /// the bar every timer in this desktop is held to.
    private func _autoAnswerActivity() {
        guard let auto = autoAnswer, auto.isArmed else { return }
        lock.lock()
        _autoAnswerLastOutput = Self._now()
        let needSchedule = !_autoAnswerPending
        if needSchedule { _autoAnswerPending = true }
        lock.unlock()
        if needSchedule { _scheduleAutoAnswerCheck(after: auto.settle) }
    }

    /// Read the screen once output has been quiet for the settle interval, and
    /// type the answer if a rule claims it.
    ///
    /// Re-arms itself rather than firing on a fixed delay: output that keeps
    /// arriving keeps pushing the check back, so a program still painting is
    /// never answered mid-frame. That is the same shape as the repaint
    /// throttle and the macOS activity assertion above, for the same reason.
    private func _scheduleAutoAnswerCheck(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self else { return }
            guard let auto = self.autoAnswer, !self.processExited else {
                self.lock.lock()
                self._autoAnswerPending = false
                self.lock.unlock()
                return
            }
            self.lock.lock()
            let quiet = Self._now() - self._autoAnswerLastOutput
            if quiet < auto.settle {
                self.lock.unlock()
                self._scheduleAutoAnswerCheck(after: auto.settle - quiet)
                return
            }
            self._autoAnswerPending = false
            // The scrollback depth goes with the rows: it is what turns "row
            // 12 of the screen" into a line number that survives the screen
            // scrolling, which is how a prompt is told apart from the same
            // prompt asked again.
            let lines = self.emulator.screenLines
            let baseLine = self.emulator.scrollbackCount
            self.lock.unlock()

            switch auto.match(lines: lines, baseLine: baseLine) {
            case .nothing:
                return
            case .tooSoon(let wait):
                // Come back on our own account. Nothing else will bring us
                // here: the program is waiting for the answer, so there is no
                // more output to schedule the next check.
                self.lock.lock()
                self._autoAnswerPending = true
                self.lock.unlock()
                self._scheduleAutoAnswerCheck(after: wait)
            case .fire(let rule):
                self.write(rule.reply)
                self.onAutoAnswer?(rule)
            }
        }
    }

    private static func _now() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    /// Terminate the child process, if any.
    public func terminate() {
        pty?.terminate()
        pty = nil
        #if os(macOS)
        _endOutputActivity()
        #endif
    }
}
