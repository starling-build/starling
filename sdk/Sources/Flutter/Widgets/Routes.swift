// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Minimal Route system — Route, OverlayRoute, ModalRoute, and showDialog.
///
/// Routes are entries managed by a Navigator. They display widgets in the
/// Navigator's Overlay using OverlayEntry objects. ModalRoute adds a barrier
/// behind the route content to prevent interaction with routes below.
///
/// Note: The Dart implementation uses `Route<T>` with a generic result type.
/// Since Swift generics are invariant (unlike Dart's covariant generics),
/// we use `Any?` as the result type to keep the API ergonomic. Callers can
/// cast the result at the call site.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/routes.dart`

import FlutterSwiftBridge

// MARK: - Route

/// An abstraction for an entry managed by a Navigator.
///
/// This class defines an abstract interface between the navigator and the
/// "routes" that are pushed on and popped off the navigator. Most routes have
/// visual affordances, which they place in the navigator's Overlay using one
/// or more OverlayEntry objects.
///
/// **Dart Source:** `navigator.dart:161`
open class Route {
    /// The overlay entries of this route.
    ///
    /// These are typically populated by `install()`. The Navigator is in charge
    /// of adding them to and removing them from the Overlay.
    open var overlayEntries: [OverlayEntry] { return [] }

    /// The navigator that the route is in, if any.
    public weak var navigator: NavigatorState?

    /// Whether this route is the top-most route on the navigator.
    public var isCurrent: Bool = false

    /// Whether this route is in the navigator's history.
    public var isActive: Bool = false

    /// Whether this route is the first route on the navigator.
    public var isFirst: Bool = false

    public init() {}

    // MARK: - Lifecycle

    /// Called when the route is inserted into the navigator.
    ///
    /// Uses this to populate `overlayEntries`.
    ///
    /// **Dart Source:** `navigator.dart:254`
    open func install() {}

    /// Called after `install` when the route is pushed onto the navigator.
    open func didPush() {}

    /// A request was made to pop this route. If the route can handle it
    /// internally, it should do so and return true. Otherwise, it should return
    /// false.
    ///
    /// **Dart Source:** `navigator.dart:389`
    @discardableResult
    open func didPop(_ result: Any? = nil) -> Bool {
        didComplete(result)
        return true
    }

    /// The route was popped or is otherwise complete.
    ///
    /// **Dart Source:** `navigator.dart:504`
    open func didComplete(_ result: Any?) {
        // Subclasses can override to handle completion.
    }

    /// Called when this route's next route changes.
    open func didChangeNext(_ nextRoute: Route?) {}

    /// Called when this route's previous route changes.
    open func didChangePrevious(_ previousRoute: Route?) {}

    /// Called whenever the internal state of the route has changed.
    ///
    /// This should be called whenever `isCurrent`, `isActive`, etc. change.
    open func changedInternalState() {}

    /// Called whenever the Navigator has updated in some manner that might
    /// affect routes, to indicate that the route may wish to rebuild as well.
    ///
    /// The Navigator calls this on every route when its own widget updates —
    /// e.g. a setState above rebuilt it with a new `home`. Routes that cache
    /// overlay entries must mark them needing build here: an entry that
    /// rebuilds to a reference-identical widget short-circuits
    /// reconciliation in `updateChild`, so a stale cache freezes the subtree.
    ///
    /// **Dart Source:** `navigator.dart:498`
    open func changedExternalState() {}

    /// Discards any resources used by the object.
    ///
    /// **Dart Source:** `navigator.dart:490`
    open func dispose() {
        navigator = nil
    }
}

// MARK: - OverlayRoute

/// A route that displays widgets in the Navigator's Overlay.
///
/// **Dart Source:** `routes.dart:55`
open class OverlayRoute: Route {
    /// The overlay entries managed by this route.
    private var _overlayEntries: [OverlayEntry] = []

    open override var overlayEntries: [OverlayEntry] {
        return _overlayEntries
    }

    /// Subclasses must override this to return the builders for the overlay.
    ///
    /// **Dart Source:** `routes.dart:61`
    open func createOverlayEntries() -> [OverlayEntry] {
        fatalError("Subclasses must override createOverlayEntries()")
    }

    /// Controls whether `didPop` calls `NavigatorState.finalizeRoute`.
    ///
    /// If true, this route removes its overlay entries during `didPop`.
    ///
    /// **Dart Source:** `routes.dart:84`
    open var finishedWhenPopped: Bool { return true }

    open override func install() {
        assert(_overlayEntries.isEmpty)
        _overlayEntries.append(contentsOf: createOverlayEntries())
        super.install()
    }

    @discardableResult
    open override func didPop(_ result: Any? = nil) -> Bool {
        let returnValue = super.didPop(result)
        assert(returnValue)
        if finishedWhenPopped {
            navigator?.finalizeRoute(self)
        }
        return returnValue
    }

    open override func dispose() {
        for entry in _overlayEntries {
            entry.remove()
            entry.dispose()
        }
        _overlayEntries.removeAll()
        super.dispose()
    }
}

// MARK: - ModalRoute

/// A route that blocks interaction with previous routes.
///
/// A modal route creates two overlay entries: a barrier (which darkens the
/// background and optionally can be tapped to dismiss) and the actual content.
///
/// **Dart Source:** `routes.dart:1243`
open class ModalRoute: OverlayRoute {
    /// The color to use for the modal barrier.
    ///
    /// If this is nil, the barrier will be transparent.
    ///
    /// **Dart Source:** `routes.dart:1785`
    open var barrierColor: Color? { return Color(0x80000000) }

    /// Whether touching the barrier dismisses the route.
    ///
    /// **Dart Source:** `routes.dart:1716`
    open var barrierDismissible: Bool { return false }

    /// The semantic label used for a dismissible barrier.
    ///
    /// **Dart Source:** `routes.dart:1815`
    open var barrierLabel: String? { return nil }

    /// Override this method to build the primary content of this route.
    ///
    /// **Dart Source:** `routes.dart:1432`
    open func buildContent(_ context: any BuildContext) -> Widget {
        fatalError("Subclasses must override buildContent(_:)")
    }

    // MARK: - Internal

    private var _modalBarrierEntry: OverlayEntry?
    private var _modalScopeEntry: OverlayEntry?

    /// Creates two overlay entries: the barrier and the content.
    ///
    /// **Dart Source:** `routes.dart:2327`
    open override func createOverlayEntries() -> [OverlayEntry] {
        let barrierEntry = OverlayEntry(builder: { [weak self] context in
            guard let self = self else {
                return SizedBox(width: 0, height: 0)
            }
            return ModalBarrier(
                color: self.barrierColor,
                dismissible: self.barrierDismissible,
                onDismiss: { [weak self] in
                    self?.navigator?.pop()
                },
                semanticsLabel: self.barrierLabel
            )
        })
        _modalBarrierEntry = barrierEntry

        let scopeEntry = OverlayEntry(
            builder: { [weak self] context in
                guard let self = self else {
                    return SizedBox(width: 0, height: 0)
                }
                return self.buildContent(context)
            },
            maintainState: true
        )
        _modalScopeEntry = scopeEntry

        return [barrierEntry, scopeEntry]
    }

    open override func changedInternalState() {
        super.changedInternalState()
        _modalBarrierEntry?.markNeedsBuild()
        _modalScopeEntry?.markNeedsBuild()
    }

    /// **Dart Source:** `routes.dart:1594` (`ModalRoute.changedExternalState`)
    open override func changedExternalState() {
        super.changedExternalState()
        _modalBarrierEntry?.markNeedsBuild()
        _modalScopeEntry?.markNeedsBuild()
    }
}

// MARK: - DialogRoute

/// A concrete ModalRoute that builds its content from a builder closure.
///
/// This is the route type used by `showDialog`.
///
/// **Dart Source:** `routes.dart:2554` (modeled after RawDialogRoute)
public class DialogRoute: ModalRoute {
    private let builder: WidgetBuilder
    private let _barrierColor: Color?
    private let _barrierDismissible: Bool
    private let _barrierLabel: String?

    public init(
        builder: @escaping WidgetBuilder,
        barrierColor: Color? = Color(0x80000000),
        barrierDismissible: Bool = false,
        barrierLabel: String? = nil
    ) {
        self.builder = builder
        self._barrierColor = barrierColor
        self._barrierDismissible = barrierDismissible
        self._barrierLabel = barrierLabel
        super.init()
    }

    public override var barrierColor: Color? { return _barrierColor }
    public override var barrierDismissible: Bool { return _barrierDismissible }
    public override var barrierLabel: String? { return _barrierLabel }

    public override func buildContent(_ context: any BuildContext) -> Widget {
        return builder(context)
    }
}

// MARK: - showDialog

/// Displays a dialog above the current contents of the app.
///
/// The `builder` callback is passed the build context of the dialog and should
/// return the widget to display in the dialog.
///
/// Content below the dialog is dimmed with a `ModalBarrier`. The widget
/// returned by the `builder` does not share a context with the location that
/// `showDialog` is originally called from.
///
/// The `barrierDismissible` argument is used to indicate whether tapping on the
/// barrier will dismiss the dialog. It is `false` by default.
///
/// The `barrierColor` argument is used to specify the color of the modal
/// barrier that darkens everything below the dialog. If nil, the default
/// color `Color(0x80000000)` (semi-transparent black) is used.
///
/// **Dart Source:** `routes.dart:2720`
@discardableResult
public func showDialog(
    context: any BuildContext,
    barrierDismissible: Bool = false,
    barrierColor: Color? = Color(0x80000000),
    barrierLabel: String? = nil,
    builder: @escaping WidgetBuilder
) -> Route {
    let route = DialogRoute(
        builder: builder,
        barrierColor: barrierColor,
        barrierDismissible: barrierDismissible,
        barrierLabel: barrierLabel
    )
    Navigator.of(context).push(route)
    return route
}
