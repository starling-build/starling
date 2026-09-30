// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Gesture disambiguation arena system.
///
/// Implements the gesture arena, which is used for disambiguating the meaning
/// of sequences of pointer events. The first member to accept or the last
/// member to not reject wins.
///
/// **Dart Source:** `packages/flutter/lib/src/gestures/arena.dart`

// Absent on WASI, where FlutterSwiftBridge supplies DispatchQueue itself.
#if canImport(Dispatch)
import Dispatch
#endif

// MARK: - GestureDisposition

/// Whether the gesture was accepted or rejected.
///
/// **Dart Source:** `arena.dart:15-21`
public enum GestureDisposition {
    /// This gesture was accepted as the interpretation of the user's input.
    case accepted

    /// This gesture was rejected as the interpretation of the user's input.
    case rejected
}

// MARK: - GestureArenaMember

/// Represents an object participating in an arena.
///
/// Receives callbacks from the GestureArena to notify the object when it wins
/// or loses a gesture negotiation. Exactly one of ``acceptGesture(_:)`` or
/// ``rejectGesture(_:)`` will be called for each arena this member was added to,
/// regardless of what caused the arena to be resolved. For example, if a
/// member resolves the arena itself, that member still receives an
/// ``acceptGesture(_:)`` callback.
///
/// **Dart Source:** `arena.dart:31-37`
public protocol GestureArenaMember: AnyObject {
    /// Called when this member wins the arena for the given pointer id.
    func acceptGesture(_ pointer: Int)

    /// Called when this member loses the arena for the given pointer id.
    func rejectGesture(_ pointer: Int)
}

// MARK: - GestureArenaEntry

/// An interface to pass information to an arena.
///
/// A given ``GestureArenaMember`` can have multiple entries in multiple arenas
/// with different pointer ids.
///
/// **Dart Source:** `arena.dart:43-57`
public class GestureArenaEntry {
    internal init(_ arena: GestureArenaManager, _ pointer: Int, _ member: GestureArenaMember) {
        self._arena = arena
        self._pointer = pointer
        self._member = member
    }

    /// Internal init for subclasses (e.g., CombiningGestureArenaEntry) that
    /// override ``resolve(_:)`` and do not need the arena/pointer/member fields.
    internal init() {
        self._arena = nil
        self._pointer = 0
        self._member = nil
    }

    private let _arena: GestureArenaManager?
    private let _pointer: Int
    private let _member: GestureArenaMember?

    /// Call this member to claim victory (with accepted) or admit defeat (with rejected).
    ///
    /// It's fine to attempt to resolve a gesture recognizer for an arena that is
    /// already resolved.
    public func resolve(_ disposition: GestureDisposition) {
        _arena!._resolve(_pointer, _member!, disposition)
    }
}

// MARK: - _GestureArena (Internal)

/// Internal state for a single gesture arena.
///
/// **Dart Source:** `arena.dart:59-104`
internal class _GestureArena: CustomStringConvertible {
    var members: [GestureArenaMember] = []
    var isOpen: Bool = true
    var isHeld: Bool = false
    var hasPendingSweep: Bool = false

    /// If a member attempts to win while the arena is still open, it becomes the
    /// "eager winner". We look for an eager winner when closing the arena to new
    /// participants, and if there is one, we resolve the arena in its favor at
    /// that time.
    var eagerWinner: GestureArenaMember?

    func add(_ member: GestureArenaMember) {
        assert(isOpen)
        members.append(member)
    }

    // MARK: CustomStringConvertible

    var description: String {
        var buffer = ""
        if members.isEmpty {
            buffer += "<empty>"
        } else {
            buffer += members.map { member in
                if let eager = eagerWinner, eager === member {
                    return "\(member) (eager winner)"
                }
                return "\(member)"
            }.joined(separator: ", ")
        }
        if isOpen {
            buffer += " [open]"
        }
        if isHeld {
            buffer += " [held]"
        }
        if hasPendingSweep {
            buffer += " [hasPendingSweep]"
        }
        return buffer
    }
}

// MARK: - GestureArenaManager

/// Used for disambiguating the meaning of sequences of pointer events.
///
/// The first member to accept or the last member to not reject wins.
///
/// To debug problems with gestures, consider using
/// ``debugPrintGestureArenaDiagnostics``.
///
/// **Dart Source:** `arena.dart:117-304`
public class GestureArenaManager {
    public init() {}

    private var _arenas: [Int: _GestureArena] = [:]

    /// Adds a new member (e.g., gesture recognizer) to the arena.
    ///
    /// **Dart Source:** `arena.dart:121-129`
    public func add(_ pointer: Int, _ member: GestureArenaMember) -> GestureArenaEntry {
        let state: _GestureArena
        if let existing = _arenas[pointer] {
            state = existing
        } else {
            assert(_debugLogDiagnostic(pointer, "\u{2605} Opening new gesture arena."))
            let newArena = _GestureArena()
            _arenas[pointer] = newArena
            state = newArena
        }
        state.add(member)
        assert(_debugLogDiagnostic(pointer, "Adding: \(member)"))
        return GestureArenaEntry(self, pointer, member)
    }

    /// Prevents new members from entering the arena.
    ///
    /// Called after the framework has finished dispatching the pointer down event.
    ///
    /// **Dart Source:** `arena.dart:134-142`
    public func close(_ pointer: Int) {
        let state = _arenas[pointer]
        if state == nil {
            return  // This arena either never existed or has been resolved.
        }
        state!.isOpen = false
        assert(_debugLogDiagnostic(pointer, "Closing", state))
        _tryToResolveArena(pointer, state!)
    }

    /// Forces resolution of the arena, giving the win to the first member.
    ///
    /// Sweep is typically after all the other processing for a PointerUpEvent
    /// have taken place. It ensures that multiple passive gestures do not cause a
    /// stalemate that prevents the user from interacting with the app.
    ///
    /// Recognizers that wish to delay resolving an arena past PointerUpEvent
    /// should call ``hold(_:)`` to delay sweep until ``release(_:)`` is called.
    ///
    /// See also:
    ///
    ///  - ``hold(_:)``
    ///  - ``release(_:)``
    ///
    /// **Dart Source:** `arena.dart:157-179`
    public func sweep(_ pointer: Int) {
        let state = _arenas[pointer]
        if state == nil {
            return  // This arena either never existed or has been resolved.
        }
        assert(!state!.isOpen)
        if state!.isHeld {
            state!.hasPendingSweep = true
            assert(_debugLogDiagnostic(pointer, "Delaying sweep", state))
            return  // This arena is being held for a long-lived member.
        }
        assert(_debugLogDiagnostic(pointer, "Sweeping", state))
        _arenas.removeValue(forKey: pointer)
        if !state!.members.isEmpty {
            // First member wins.
            assert(_debugLogDiagnostic(pointer, "Winner: \(state!.members.first!)"))
            state!.members.first!.acceptGesture(pointer)
            // Give all the other members the bad news.
            for i in 1..<state!.members.count {
                state!.members[i].rejectGesture(pointer)
            }
        }
    }

    /// Prevents the arena from being swept.
    ///
    /// Typically, a winner is chosen in an arena after all the other
    /// PointerUpEvent processing by ``sweep(_:)``. If a recognizer wishes to delay
    /// resolving an arena past PointerUpEvent, the recognizer can hold the
    /// arena open using this function. To release such a hold and let the arena
    /// resolve, call ``release(_:)``.
    ///
    /// See also:
    ///
    ///  - ``sweep(_:)``
    ///  - ``release(_:)``
    ///
    /// **Dart Source:** `arena.dart:193-200`
    public func hold(_ pointer: Int) {
        let state = _arenas[pointer]
        if state == nil {
            return  // This arena either never existed or has been resolved.
        }
        state!.isHeld = true
        assert(_debugLogDiagnostic(pointer, "Holding", state))
    }

    /// Releases a hold, allowing the arena to be swept.
    ///
    /// If a sweep was attempted on a held arena, the sweep will be done
    /// on release.
    ///
    /// See also:
    ///
    ///  - ``sweep(_:)``
    ///  - ``hold(_:)``
    ///
    /// **Dart Source:** `arena.dart:211-221`
    public func release(_ pointer: Int) {
        let state = _arenas[pointer]
        if state == nil {
            return  // This arena either never existed or has been resolved.
        }
        state!.isHeld = false
        assert(_debugLogDiagnostic(pointer, "Releasing", state))
        if state!.hasPendingSweep {
            sweep(pointer)
        }
    }

    /// Reject or accept a gesture recognizer.
    ///
    /// This is called by calling ``GestureArenaEntry/resolve(_:)`` on the object
    /// returned from ``add(_:_:)``.
    ///
    /// **Dart Source:** `arena.dart:226-249`
    internal func _resolve(_ pointer: Int, _ member: GestureArenaMember, _ disposition: GestureDisposition) {
        let state = _arenas[pointer]
        if state == nil {
            return  // This arena has already resolved.
        }
        assert(state!.members.contains { $0 === member })
        switch disposition {
        case .accepted:
            assert(_debugLogDiagnostic(pointer, "Accepting: \(member)"))
            if state!.isOpen {
                if state!.eagerWinner == nil {
                    state!.eagerWinner = member
                }
            } else {
                assert(_debugLogDiagnostic(pointer, "Self-declared winner: \(member)"))
                _resolveInFavorOf(pointer, state!, member)
            }
        case .rejected:
            assert(_debugLogDiagnostic(pointer, "Rejecting: \(member)"))
            state!.members.removeAll { $0 === member }
            member.rejectGesture(pointer)
            if !state!.isOpen {
                _tryToResolveArena(pointer, state!)
            }
        }
    }

    /// **Dart Source:** `arena.dart:251-263`
    private func _tryToResolveArena(_ pointer: Int, _ state: _GestureArena) {
        assert(_arenas[pointer] === state)
        assert(!state.isOpen)
        if state.members.count == 1 {
            // DIFFERENCE FROM DART: Uses DispatchQueue.main.async instead of
            // scheduleMicrotask. nonisolated(unsafe) is used to safely capture
            // non-Sendable values across isolation boundaries, mirroring Dart's
            // single-isolate execution model where gesture processing happens
            // on the main thread.
            nonisolated(unsafe) let capturedState = state
            nonisolated(unsafe) let capturedSelf = self
            DispatchQueue.main.async {
                capturedSelf._resolveByDefault(pointer, capturedState)
            }
        } else if state.members.isEmpty {
            _arenas.removeValue(forKey: pointer)
            assert(_debugLogDiagnostic(pointer, "Arena empty."))
        } else if state.eagerWinner != nil {
            assert(_debugLogDiagnostic(pointer, "Eager winner: \(state.eagerWinner!)"))
            _resolveInFavorOf(pointer, state, state.eagerWinner!)
        }
    }

    /// **Dart Source:** `arena.dart:265-276`
    private func _resolveByDefault(_ pointer: Int, _ state: _GestureArena) {
        if _arenas[pointer] == nil {
            return  // This arena has already resolved.
        }
        assert(_arenas[pointer] === state)
        assert(!state.isOpen)
        let members = state.members
        assert(members.count == 1)
        _arenas.removeValue(forKey: pointer)
        assert(_debugLogDiagnostic(pointer, "Default winner: \(state.members.first!)"))
        state.members.first!.acceptGesture(pointer)
    }

    /// **Dart Source:** `arena.dart:278-289`
    private func _resolveInFavorOf(_ pointer: Int, _ state: _GestureArena, _ member: GestureArenaMember) {
        assert(state === _arenas[pointer])
        assert(state.eagerWinner == nil || state.eagerWinner === member)
        assert(!state.isOpen)
        _arenas.removeValue(forKey: pointer)
        for rejectedMember in state.members {
            if rejectedMember !== member {
                rejectedMember.rejectGesture(pointer)
            }
        }
        member.acceptGesture(pointer)
    }

    /// **Dart Source:** `arena.dart:291-303`
    @discardableResult
    private func _debugLogDiagnostic(_ pointer: Int, _ message: String, _ state: _GestureArena? = nil) -> Bool {
        assert({
            if debugPrintGestureArenaDiagnostics {
                let count = state?.members.count
                let s = count != 1 ? "s" : ""
                debugPrint(
                    "Gesture arena \(String(pointer).paddedToLength(4)) \u{2759} \(message)\(count != nil ? " with \(count!) member\(s)." : "")",
                    nil
                )
            }
            return true
        }())
        return true
    }
}
