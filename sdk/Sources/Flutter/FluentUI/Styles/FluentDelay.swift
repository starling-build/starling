// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A one-shot delay on the frame clock, for the Fluent controls that wait:
// a submenu opening under a resting pointer, a tooltip after its hover
// delay, a tooltip going away after the pointer leaves.
//
// Why not `Foundation.Timer`: it never fires on the DRM embedder, and the
// GTK host's main loop does not run Foundation's either — a tooltip on
// one sat behind a timer that never came due and simply never appeared.
// The port has no post-frame callback yet, so a `Ticker` is the timer that
// exists on every host (the idiom `TeachingTip._deferShow` set). It costs
// a frame per tick while it runs, which for delays of a second or so,
// under a pointer that is moving anyway, is nothing.

import FlutterSwiftBridge

public final class FluentDelay {
    public init() {}
    private var _ticker: Ticker?

    /// Whether a delay is pending.
    public var isScheduled: Bool { _ticker != nil }

    /// Runs `action` once `delay` has passed; a delay already pending is
    /// replaced.
    public func schedule(after delay: Duration, _ action: @escaping () -> Void) {
        cancel()
        let ticker = Ticker { [weak self] elapsed in
            guard elapsed >= delay else { return }
            self?.cancel()
            action()
        }
        _ticker = ticker
        _ = ticker.start()
    }

    /// Drops a pending delay; its action never runs.
    public func cancel() {
        _ticker?.stop()
        _ticker?.dispose()
        _ticker = nil
    }

    deinit { cancel() }
}
