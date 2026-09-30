// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Overlay system — a stack of entries that can be managed independently.
///
/// Overlays let independent child widgets "float" visual elements on top of
/// other widgets by inserting them into the overlay's stack. The overlay lets
/// each of these widgets manage their participation in the overlay using
/// `OverlayEntry` objects.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/overlay.dart`

import FlutterSwiftBridge

// MARK: - OverlayEntry

/// A place in an `Overlay` that can contain a widget.
///
/// Overlay entries are inserted into an `Overlay` using the
/// `OverlayState.insert` or `OverlayState.insertAll` functions. To find the
/// closest enclosing overlay for a given `BuildContext`, use the `Overlay.of`
/// function.
///
/// An overlay entry can be in at most one overlay at a time. To remove an entry
/// from its overlay, call the `remove` function on the overlay entry.
///
/// Because an `Overlay` uses a `Stack` layout, overlay entries can use
/// `Positioned` to position themselves within the overlay.
///
/// **Dart Source:** `overlay.dart:108`
public class OverlayEntry {
    /// This entry will include the widget built by this builder in the overlay
    /// at the entry's position.
    ///
    /// To cause this builder to be called again, call `markNeedsBuild` on this
    /// overlay entry.
    public let builder: WidgetBuilder

    /// Whether this entry occludes the entire overlay.
    ///
    /// If an entry claims to be opaque, then, for efficiency, the overlay will
    /// skip building entries below that entry unless they have `maintainState`
    /// set.
    public var opaque: Bool {
        get { _opaque }
        set {
            if _opaque == newValue { return }
            _opaque = newValue
            _overlay?._didChangeEntryOpacity()
        }
    }
    private var _opaque: Bool

    /// Whether this entry must be included in the tree even if there is a fully
    /// opaque entry above it.
    public var maintainState: Bool {
        get { _maintainState }
        set {
            if _maintainState == newValue { return }
            _maintainState = newValue
            _overlay?._didChangeEntryOpacity()
        }
    }
    private var _maintainState: Bool

    /// Whether the `OverlayEntry` is currently mounted in the widget tree.
    public var mounted: Bool {
        return _overlayEntryStateRef != nil
    }

    /// Creates an overlay entry.
    ///
    /// To insert the entry into an `Overlay`, first find the overlay using
    /// `Overlay.of` and then call `OverlayState.insert`. To remove the entry,
    /// call `remove` on the overlay entry itself.
    public init(
        builder: @escaping WidgetBuilder,
        opaque: Bool = false,
        maintainState: Bool = false
    ) {
        self.builder = builder
        self._opaque = opaque
        self._maintainState = maintainState
    }

    // MARK: Internal

    /// The overlay this entry is currently inserted into, if any.
    weak var _overlay: OverlayState?

    /// Whether this entry has been mounted into the widget tree.
    var _mounted: Bool = false

    /// A `GlobalKey` used to identify the `_OverlayEntryWidgetState` for this
    /// entry so that `markNeedsBuild` can trigger a rebuild.
    let _key = GlobalKey<_OverlayEntryWidgetState>(debugLabel: "OverlayEntry")

    /// Weak reference to the associated widget state, tracked for `mounted`.
    weak var _overlayEntryStateRef: _OverlayEntryWidgetState?

    /// Whether the owner has called `dispose`.
    private var _disposedByOwner: Bool = false

    // MARK: Public API

    /// Remove this entry from the overlay.
    ///
    /// This should only be called once.
    public func remove() {
        assert(_overlay != nil, "OverlayEntry.remove called when not in an Overlay")
        guard let overlay = _overlay else { return }
        _overlay = nil
        if !overlay.mounted { return }
        overlay._entries.removeAll { $0 === self }
        // Removed from a dispose while the tree is being finalized (a
        // Tooltip unmounting with its entry showing): the overlay cannot
        // be marked dirty until the lock lifts. Upstream uses a post-frame
        // callback for the same case.
        if let owner = overlay.context?.owner {
            owner.runWhenUnlocked { overlay._markDirty() }
        } else {
            overlay._markDirty()
        }
    }

    /// Cause this entry to rebuild during the next pipeline flush.
    ///
    /// You need to call this function if the output of `builder` has changed.
    public func markNeedsBuild() {
        _key.currentState?._markNeedsBuild()
    }

    /// Discards any resources used by this `OverlayEntry`.
    ///
    /// This method must be called after `remove` if the `OverlayEntry` is
    /// inserted into an `Overlay`.
    ///
    /// After this is called, the object is not in a usable state and should be
    /// discarded.
    public func dispose() {
        assert(
            _overlay == nil,
            "An OverlayEntry must first be removed from the Overlay before dispose is called."
        )
        _disposedByOwner = true
    }
}

// MARK: - _OverlayEntryWidget

/// Internal `StatefulWidget` that wraps a single `OverlayEntry`.
///
/// Its state rebuilds when `entry.markNeedsBuild()` is called via the
/// `GlobalKey` → `_OverlayEntryWidgetState._markNeedsBuild()` path.
///
/// **Dart Source:** `overlay.dart:296`
class _OverlayEntryWidget: StatefulWidget {
    let entry: OverlayEntry
    let overlayState: OverlayState

    init(
        key: any Key,
        entry: OverlayEntry,
        overlayState: OverlayState
    ) {
        self.entry = entry
        self.overlayState = overlayState
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _OverlayEntryWidgetState()
    }
}

// MARK: - _OverlayEntryWidgetState

/// The state for `_OverlayEntryWidget`.
///
/// Calls `entry.builder(context)` in `build` and provides `_markNeedsBuild`
/// so that `OverlayEntry.markNeedsBuild()` can trigger a rebuild of just this
/// entry.
///
/// **Dart Source:** `overlay.dart:312`
class _OverlayEntryWidgetState: State<StatefulWidget> {
    private var _entryWidget: _OverlayEntryWidget {
        return widget as! _OverlayEntryWidget
    }

    override func initState() {
        super.initState()
        _entryWidget.entry._overlayEntryStateRef = self
    }

    override func dispose() {
        _entryWidget.entry._overlayEntryStateRef = nil
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        return _entryWidget.entry.builder(context)
    }

    /// Called by `OverlayEntry.markNeedsBuild()` via the `GlobalKey`.
    func _markNeedsBuild() {
        setState { /* the state that changed is in the builder */ }
    }
}

// MARK: - Overlay

/// A stack of entries that can be managed independently.
///
/// Overlays let independent child widgets "float" visual elements on top of
/// other widgets by inserting them into the overlay's stack. The overlay lets
/// each of these widgets manage their participation in the overlay using
/// `OverlayEntry` objects.
///
/// The `Overlay` widget uses a `Stack` internally, which is very similar to
/// the full `_Theater` render object in Flutter's Dart implementation. The
/// main use case of `Overlay` is related to navigation and being able to
/// insert widgets on top of the pages in an app.
///
/// **Dart Source:** `overlay.dart:478`
public class Overlay: StatefulWidget {
    /// The entries to include in the overlay initially.
    ///
    /// These entries are only used when the `OverlayState` is initialized. If you
    /// are providing a new `Overlay` description for an overlay that's already in
    /// the tree, then the new entries are ignored.
    public let initialEntries: [OverlayEntry]

    /// The content will be clipped (or not) according to this option.
    ///
    /// Defaults to `Clip.hardEdge`.
    public let clipBehavior: Clip

    /// Creates an overlay.
    ///
    /// The initial entries will be inserted into the overlay when its associated
    /// `OverlayState` is initialized.
    public init(
        key: (any Key)? = nil,
        initialEntries: [OverlayEntry] = [],
        clipBehavior: Clip = .hardEdge
    ) {
        self.initialEntries = initialEntries
        self.clipBehavior = clipBehavior
        super.init(key: key)
    }

    // MARK: Static Lookup

    /// The `OverlayState` from the closest instance of `Overlay` that encloses
    /// the given context within the closest `LookupBoundary`, and, in debug mode,
    /// will throw if one is not found.
    ///
    /// Typical usage is as follows:
    ///
    /// ```swift
    /// let overlay = Overlay.of(context)
    /// ```
    ///
    /// **Dart Source:** `overlay.dart:551`
    public static func of(_ context: any BuildContext) -> OverlayState {
        let result = maybeOf(context)
        assert(result != nil, "No Overlay widget found.")
        return result!
    }

    /// The `OverlayState` from the closest instance of `Overlay` that encloses
    /// the given context within the closest `LookupBoundary`, if any.
    ///
    /// Typical usage is as follows:
    ///
    /// ```swift
    /// let overlay = Overlay.maybeOf(context)
    /// ```
    ///
    /// **Dart Source:** `overlay.dart:610`
    public static func maybeOf(_ context: any BuildContext) -> OverlayState? {
        return LookupBoundary.findAncestorStateOfType(
            OverlayState.self,
            context
        )
    }

    // MARK: - StatefulWidget

    public override func createState() -> State<StatefulWidget> {
        return OverlayState()
    }
}

// MARK: - OverlayState

/// The current state of an `Overlay`.
///
/// Used to insert `OverlayEntry`s into the overlay using the `insert` and
/// `insertAll` functions.
///
/// **Dart Source:** `overlay.dart:626`
public class OverlayState: State<StatefulWidget> {
    /// The list of overlay entries managed by this overlay.
    var _entries: [OverlayEntry] = []

    private var overlay: Overlay {
        return widget as! Overlay
    }

    // MARK: - Lifecycle

    public override func initState() {
        super.initState()
        insertAll(overlay.initialEntries)
    }

    // MARK: - Insertion Index

    /// Computes the insertion index for a new entry relative to `below` or
    /// `above`.
    private func _insertionIndex(below: OverlayEntry?, above: OverlayEntry?) -> Int {
        assert(
            above == nil || below == nil,
            "Only one of `above` and `below` may be specified."
        )
        if let below = below {
            if let idx = _entries.firstIndex(where: { $0 === below }) {
                return idx
            }
            return _entries.count
        }
        if let above = above {
            if let idx = _entries.firstIndex(where: { $0 === above }) {
                return idx + 1
            }
            return _entries.count
        }
        return _entries.count
    }

    // MARK: - Public API

    /// Insert the given entry into the overlay.
    ///
    /// If `below` is non-nil, the entry is inserted just below `below`.
    /// If `above` is non-nil, the entry is inserted just above `above`.
    /// Otherwise, the entry is inserted on top.
    ///
    /// It is an error to specify both `above` and `below`.
    ///
    /// **Dart Source:** `overlay.dart:718`
    public func insert(
        _ entry: OverlayEntry,
        below: OverlayEntry? = nil,
        above: OverlayEntry? = nil
    ) {
        assert(
            above == nil || below == nil,
            "Only one of `above` and `below` may be specified."
        )
        assert(entry._overlay == nil, "The entry is already in an Overlay.")
        entry._overlay = self
        setState {
            self._entries.insert(entry, at: self._insertionIndex(below: below, above: above))
        }
    }

    /// Insert all the entries in the given iterable.
    ///
    /// If `below` is non-nil, the entries are inserted just below `below`.
    /// If `above` is non-nil, the entries are inserted just above `above`.
    /// Otherwise, the entries are inserted on top.
    ///
    /// It is an error to specify both `above` and `below`.
    ///
    /// **Dart Source:** `overlay.dart:734`
    public func insertAll(
        _ entries: [OverlayEntry],
        below: OverlayEntry? = nil,
        above: OverlayEntry? = nil
    ) {
        assert(
            above == nil || below == nil,
            "Only one of `above` and `below` may be specified."
        )
        if entries.isEmpty { return }
        for entry in entries {
            assert(entry._overlay == nil, "The entry is already in an Overlay.")
            entry._overlay = self
        }
        setState {
            let idx = self._insertionIndex(below: below, above: above)
            self._entries.insert(contentsOf: entries, at: idx)
        }
    }

    /// Remove all the entries listed in the given iterable, then reinsert them
    /// into the overlay in the given order.
    ///
    /// Entries mentioned in `newEntries` but absent from the overlay are inserted
    /// as if with `insertAll`.
    ///
    /// Entries not mentioned in `newEntries` but present in the overlay are
    /// positioned as a group in the resulting list relative to the entries that
    /// were moved, as specified by one of `below` or `above`, which, if
    /// specified, must be one of the entries in `newEntries`:
    ///
    /// If `below` is non-nil, the group is positioned just below `below`.
    /// If `above` is non-nil, the group is positioned just above `above`.
    /// Otherwise, the group is left on top, with all the rearranged entries
    /// below.
    ///
    /// It is an error to specify both `above` and `below`.
    ///
    /// **Dart Source:** `overlay.dart:789`
    public func rearrange(
        _ newEntries: [OverlayEntry],
        below: OverlayEntry? = nil,
        above: OverlayEntry? = nil
    ) {
        assert(
            above == nil || below == nil,
            "Only one of `above` and `below` may be specified."
        )
        if newEntries.isEmpty { return }

        // Build an identity set of the old entries.
        let oldIdentitySet = Set(_entries.map { ObjectIdentifier($0) })

        for entry in newEntries {
            entry._overlay = entry._overlay ?? self
        }

        setState {
            // Build an identity set of the new entries.
            let newIdentitySet = Set(newEntries.map { ObjectIdentifier($0) })

            // Entries in _entries but not in newEntries — these are the "old"
            // entries that keep their relative position.
            let oldOnly = self._entries.filter { !newIdentitySet.contains(ObjectIdentifier($0)) }

            // Start with newEntries.
            self._entries = newEntries

            // Insert the old-only group at the right position.
            let idx = self._insertionIndex(below: below, above: above)
            self._entries.insert(contentsOf: oldOnly, at: idx)
        }
    }

    /// (DEBUG ONLY) Check whether a given entry is visible (i.e., not behind an
    /// opaque entry).
    ///
    /// **Dart Source:** `overlay.dart:836`
    public func debugIsVisible(_ entry: OverlayEntry) -> Bool {
        var result = false
        for i in stride(from: _entries.count - 1, through: 0, by: -1) {
            let candidate = _entries[i]
            if candidate === entry {
                result = true
                break
            }
            if candidate.opaque {
                break
            }
        }
        return result
    }

    // MARK: - Internal

    /// Marks the overlay as needing a rebuild. Called when entries change
    /// opacity or are removed.
    func _didChangeEntryOpacity() {
        setState { /* opacity changed — rebuild */ }
    }

    /// Marks the overlay as needing a rebuild.
    func _markDirty() {
        if mounted {
            setState { /* entry list changed */ }
        }
    }

    // MARK: - Build

    /// Builds the overlay widget tree.
    ///
    /// Creates a `Stack` where each child is an `_OverlayEntryWidget` wrapping
    /// one of the managed `OverlayEntry` instances. Entries behind an opaque
    /// entry are either skipped or wrapped in `Offstage` if they have
    /// `maintainState` set.
    ///
    /// **Dart Source:** `overlay.dart:864`
    public override func build(_ context: any BuildContext) -> Widget {
        // This list is filled backwards and then reversed before it is
        // added to the tree, matching the Dart implementation.
        var children: [Widget] = []
        var onstage = true

        for entry in _entries.reversed() {
            if onstage {
                children.append(
                    _OverlayEntryWidget(
                        key: entry._key,
                        entry: entry,
                        overlayState: self
                    )
                )
                if entry.opaque {
                    onstage = false
                }
            } else if entry.maintainState {
                children.append(
                    Offstage(
                        offstage: true,
                        child: _OverlayEntryWidget(
                            key: entry._key,
                            entry: entry,
                            overlayState: self
                        )
                    )
                )
            }
        }

        return _Theater(
            clipBehavior: overlay.clipBehavior,
            children: children.reversed()
        )
    }
}

// MARK: - _Theater

/// Simplified theater widget that lays out overlay entries in a `Stack`.
///
/// In Flutter's Dart implementation this is a full custom `RenderObject`
/// (`_RenderTheater`). Here we use a plain `Stack` with `StackFit.expand`
/// and `Positioned.fill` semantics for simplicity — every overlay entry
/// stretches to fill the available space, which is the default behaviour for
/// non-`Positioned` children in a `Stack` with `StackFit.expand`.
///
/// **Dart Source:** `overlay.dart` (simplified)
private class _Theater: StatelessWidget {
    let clipBehavior: Clip
    let theaterChildren: [Widget]

    init(
        key: (any Key)? = nil,
        clipBehavior: Clip = .hardEdge,
        children: [Widget] = []
    ) {
        self.clipBehavior = clipBehavior
        self.theaterChildren = children
        super.init(key: key)
    }

    override func build(_ context: any BuildContext) -> Widget {
        return Stack(
            fit: .expand,
            clipBehavior: clipBehavior,
            children: theaterChildren
        )
    }
}
