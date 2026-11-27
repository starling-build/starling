// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The two ways a touch asks for the menu a right-click opens: a finger held still (a long press), and two fingers
// tapped together. A surface that takes raw pointer events (the slide, the thumbnail rail, a grid's headers) feeds
// its pointer events here; the trigger calls `fire` with where the menu goes. Mouse and pen events are ignored: they
// have a secondary button of their own.

import Flutter
import FlutterSwiftBridge
import Foundation

final class TouchMenuTrigger {
    /// How long a finger holds still before the menu opens, and how long two fingers have to land and lift together.
    static let holdDelay = 0.5
    static let tapWindow = 0.6
    /// How far a finger may drift (points) and still be holding, or tapping.
    static let slop = 8.0

    private var _touches: [Int: (at: Double, start: Offset)] = [:]
    private var _generation = 0
    private var _twoFinger: (at: Double, position: Offset)? = nil
    private var _fire: ((Offset) -> Void)? = nil

    private static func _now() -> Double { Date().timeIntervalSince1970 }

    /// A pointer went down. Returns true when it is the second finger of a two-finger tap, so the caller leaves its own
    /// handling of this finger out. With `hold` the first finger also arms the long press.
    @discardableResult
    func down(_ e: PointerDownEvent, hold: Bool = true, fire: @escaping (Offset) -> Void) -> Bool {
        guard e.kind == .touch else { return false }
        let now = Self._now()
        _touches = _touches.filter { now - $0.value.at < Self.tapWindow || $0.key == e.pointer }
        if _touches[e.pointer] != nil { return false }   // the same touch reaching a second listener
        _fire = fire
        if let first = _touches.values.first, now - first.at < Self.tapWindow {
            _generation &+= 1
            _touches[e.pointer] = (now, e.position)
            _twoFinger = (now, e.position)
            return true
        }
        _touches[e.pointer] = (now, e.position)
        _twoFinger = nil
        _generation &+= 1
        if hold {
            let generation = _generation, at = e.position
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay) { [weak self] in
                guard let self, generation == self._generation, self._touches.count == 1 else { return }
                self._touches = [:]
                self._fire?(at)
            }
        }
        return false
    }

    /// A pointer moved: past the slop it is a drag, not a hold or a tap.
    func moved(_ pointer: Int, _ position: Offset) {
        guard let t = _touches[pointer] else { return }
        let dx = position.dx - t.start.dx, dy = position.dy - t.start.dy
        if dx * dx + dy * dy > Self.slop * Self.slop {
            _generation &+= 1
            _twoFinger = nil
        }
    }

    /// A pointer lifted (or was cancelled). The last of two fingers up, soon enough and in place, opens the menu.
    func up(_ pointer: Int) {
        guard _touches.removeValue(forKey: pointer) != nil else { return }
        _generation &+= 1
        if _touches.isEmpty, let two = _twoFinger {
            _twoFinger = nil
            if Self._now() - two.at < Self.tapWindow { _fire?(two.position) }
        }
    }
}
