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
