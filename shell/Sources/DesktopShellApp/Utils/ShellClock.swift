// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - ShellClock

/// The clock in the menu bar / taskbar, as a widget that owns its own cadence.
///
/// WHY IT IS A WIDGET AND NOT A STRING
///
/// It used to be a string the shell computed inside its own `build`, which
/// meant the clock advanced only when something ELSE rebuilt the shell. On an
/// idle desktop nothing does — measured with `STARLING_FRAME_LOG=1`, the
/// desktop builds **zero** frames across two minute boundaries — so the time on
/// screen simply stopped at whatever it read when the user last touched the
/// machine. Leave the desktop for ten minutes and it was ten minutes wrong.
///
/// The fix is not a shell-wide tick. The Windows shell had exactly that and it
/// was the single most expensive thing it did at idle: a 1 Hz tick rebuilt the
/// whole 4K chrome 59 times a minute to paint an identical string
/// (`sdk/Examples/WinShellBar/Dock.swift`'s `DockClock`, which this follows).
/// A clock is the only thing that knows what cadence its own FORMAT needs, so
/// it keeps that decision, wakes once per boundary, and rebuilds its own leaf.
///
/// Cost at idle: one wakeup a minute, against 60 for a naive fix and zero for
/// the bug.
final class ShellClock: StatefulWidget {
    /// A `DateFormatter` pattern. Seconds in it mean a one-second cadence;
    /// anything else only moves on the minute.
    let format: String
    /// Qualified because `FlutterSwiftBridge` exports a `TextStyle` too, and a
    /// type reference — unlike the call sites' expressions — cannot choose
    /// between them on its own.
    let style: Flutter.TextStyle

    init(key: (any Key)? = nil, format: String, style: Flutter.TextStyle) {
        self.format = format
        self.style = style
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { ShellClockState() }
}

final class ShellClockState: State<StatefulWidget> {
    private var now = Date()
    /// Retires a pending wake. `DispatchQueue.main.asyncAfter` plus a
    /// generation token is the house timer idiom — `Foundation.Timer` never
    /// fires at all on the DRM embedder.
    private var generation = 0

    override func initState() {
        super.initState()
        _scheduleNextTick()
    }

    override func dispose() {
        generation &+= 1
        super.dispose()
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        if (oldWidget as! ShellClock).format != (widget as! ShellClock).format {
            _scheduleNextTick()
        }
    }

    private func _scheduleNextTick() {
        generation &+= 1
        let gen = generation
        let period: TimeInterval =
            (widget as! ShellClock).format.contains("s") ? 1 : 60
        let t = Date().timeIntervalSince1970
        // Land just AFTER the boundary: a wake a hair before it paints the
        // old minute and then reschedules for ~0s.
        let delay = period - t.truncatingRemainder(dividingBy: period) + 0.05
        // Same spelling as the shell's other deadline timers: the closure is
        // main-queue-only by construction, and `asyncAfter` wants a
        // `@Sendable` one.
        let fire: () -> Void = { [weak self] in
            guard let self, self.generation == gen else { return }
            self.setState { self.now = Date() }
            self._scheduleNextTick()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: unsafeBitCast(fire, to: (@Sendable () -> Void).self))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let clock = widget as! ShellClock
        let f = DateFormatter()
        f.dateFormat = clock.format
        return Text(f.string(from: now), style: clock.style)
    }
}

// MARK: - ShellCaret

/// The blinking caret in the launcher's search box, as a widget that owns its
/// own blink.
///
/// WHY IT IS A WIDGET, for the same reason as `ShellClock` above and with a
/// much bigger number attached. The blink used to be shell state: a 530 ms
/// `asyncAfter` chain toggled `_launcherCaretOn` inside `setState`, which
/// rebuilds the WHOLE tree. Measured with `STARLING_FRAME_LOG=1`, an open
/// Start menu sitting untouched cost **2.35% of a core** — 1.9 frames a
/// second at 9.7 ms each, of which 9.2 ms was rebuilding the shell and its
/// thirteen app tiles, all to flip one 2x18 rectangle between two colours.
/// Closed, the same desktop is 0.03%.
///
/// This is the Windows shell's lesson arriving on Linux: a parked Run dialog
/// there blinked its caret forever in a window nobody could see. What the
/// blink needs to know is local to the caret, so it lives here.
final class ShellCaret: StatefulWidget {
    /// Drawn as a "|" glyph whose colour goes to alpha 0 when off, NOT as a
    /// box that appears and disappears: a caret that leaves the tree shifts
    /// the label beside it a few pixels twice a second. Same glyph, same
    /// metrics, and the layout cannot move.
    let color: Color
    let fontSize: Double
    let fontFamily: String?
    /// Bumped by the owner on every keystroke. The caret goes solid and the
    /// blink restarts from there — what a real text field does, and what
    /// makes the box read as an input rather than a label.
    let resetToken: Int

    init(key: (any Key)? = nil, color: Color, fontSize: Double,
         fontFamily: String? = nil, resetToken: Int) {
        self.color = color
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.resetToken = resetToken
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { ShellCaretState() }
}

final class ShellCaretState: State<StatefulWidget> {
    private var on = true
    private var generation = 0

    override func initState() {
        super.initState()
        _schedule()
    }

    override func dispose() {
        generation &+= 1
        super.dispose()
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        let old = (oldWidget as! ShellCaret).resetToken
        if old != (widget as! ShellCaret).resetToken {
            on = true
            _schedule()
        }
    }

    private func _schedule() {
        generation &+= 1
        let gen = generation
        let fire: () -> Void = { [weak self] in
            guard let self, self.generation == gen else { return }
            self.setState { self.on.toggle() }
            self._schedule()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(530),
            execute: unsafeBitCast(fire, to: (@Sendable () -> Void).self))
    }

    override func build(_ context: any BuildContext) -> Widget {
        let c = widget as! ShellCaret
        // No RepaintBoundary here: it was tried and measured, and changed
        // nothing. This compositor repaints the scene per frame regardless,
        // so scoping the BUILD (which this widget does) is the win; scoping
        // the paint is not available to ask for.
        return Text("|", style: Flutter.TextStyle(
            color: on ? c.color : c.color.withValues(alpha: 0),
            fontSize: c.fontSize, fontFamily: c.fontFamily), maxLines: 1)
    }
}
