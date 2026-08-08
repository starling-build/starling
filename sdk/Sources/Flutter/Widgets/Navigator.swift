// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Minimal Navigator — manages a stack of Route objects using an Overlay.
///
/// The Navigator manages a stack of routes. Routes create overlay entries which
/// are inserted into the navigator's overlay. Pushing a route adds it to the
/// stack and inserts its overlay entries. Popping removes the top route and
/// its entries.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/navigator.dart`

import FlutterSwiftBridge

// MARK: - Navigator

/// A widget that manages a set of child widgets with a stack discipline.
///
/// Many apps have a navigator near the top of their widget hierarchy in order
/// to display their logical history using an Overlay with the most recently
/// visited pages visually on top of the older pages. Using this pattern lets
/// the navigator visually transition from one page to another by moving the
/// widgets around in the overlay.
///
/// **Dart Source:** `navigator.dart:2064`
public class Navigator: StatefulWidget {
    /// An optional callback to generate a route for a given route name.
    public let onGenerateRoute: ((String) -> Route)?

    /// The widget for the default route of the app (`/`).
    ///
    /// If `home` is provided and `onGenerateRoute` is nil, the navigator will
    /// show this widget as its initial route.
    public let home: Widget?

    /// Creates a Navigator.
    public init(
        key: (any Key)? = nil,
        onGenerateRoute: ((String) -> Route)? = nil,
        home: Widget? = nil
    ) {
        self.onGenerateRoute = onGenerateRoute
        self.home = home
        super.init(key: key)
    }

    // MARK: - Static Convenience

    /// The state from the closest instance of this class that encloses the
    /// given context.
    ///
    /// **Dart Source:** `navigator.dart:2898`
    public static func of(_ context: any BuildContext) -> NavigatorState {
        let result = maybeOf(context)
        assert(result != nil, "Navigator operation requested with a context that does not include a Navigator.")
        return result!
    }

    /// The state from the closest instance of this class that encloses the
    /// given context, if any.
    ///
    /// **Dart Source:** `navigator.dart:2943`
    public static func maybeOf(_ context: any BuildContext) -> NavigatorState? {
        return context.findAncestorStateOfType(NavigatorState.self)
    }

    /// Push a route onto the closest navigator.
    ///
    /// **Dart Source:** `navigator.dart:2306`
    @discardableResult
    public static func push(_ context: any BuildContext, _ route: Route) -> Route {
        Navigator.of(context).push(route)
        return route
    }

    /// Pop the top-most route off the closest navigator.
    ///
    /// **Dart Source:** `navigator.dart:2773`
    public static func pop(_ context: any BuildContext, _ result: Any? = nil) {
        Navigator.of(context).pop(result)
    }

    // MARK: - StatefulWidget

    public override func createState() -> State<StatefulWidget> {
        return NavigatorState()
    }
}

// MARK: - NavigatorState

/// The state for a Navigator widget.
///
/// **Dart Source:** `navigator.dart:3677`
public class NavigatorState: State<StatefulWidget> {
    /// The route stack managed by this navigator.
    private var _routes: [Route] = []

    /// The GlobalKey for the overlay managed by this navigator.
    private let _overlayKey = GlobalKey<OverlayState>(debugLabel: "Navigator Overlay")

    /// The overlay this navigator uses for its visual presentation.
    ///
    /// **Dart Source:** `navigator.dart:4085`
    public var overlay: OverlayState? {
        return _overlayKey.currentState
    }

    private var navigatorWidget: Navigator {
        return widget as! Navigator
    }

    // MARK: - Lifecycle

    public override func initState() {
        super.initState()

        // Create the initial route from `home` if provided. The route reads
        // `home` through the state at build time rather than capturing the
        // widget instance: a captured instance is reference-identical on
        // every rebuild, which `updateChild` short-circuits — an ancestor
        // setState would then never propagate below the Navigator.
        if navigatorWidget.home != nil {
            let initialRoute = _SimpleRoute(childBuilder: { [weak self] in
                self?.navigatorWidget.home ?? SizedBox(width: 0, height: 0)
            })
            _pushRouteInternal(initialRoute)
        }
    }

    public override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        // The Navigator's configuration changed (e.g. a new `home` from an
        // ancestor rebuild); let every route rebuild its overlay entries.
        //
        // **Dart Source:** `navigator.dart:3931` (NavigatorState.didUpdateWidget)
        for route in _routes {
            route.changedExternalState()
        }
    }

    // MARK: - Public API

    /// Push a route onto the navigator's stack.
    ///
    /// The route is installed and its overlay entries are inserted into the
    /// navigator's overlay.
    ///
    /// **Dart Source:** `navigator.dart:4994`
    public func push(_ route: Route) {
        _pushRouteInternal(route)
        _updateRouteState()
    }

    /// Pop the top-most route off the navigator's stack.
    ///
    /// The route's `didPop` is called with the given result.
    ///
    /// **Dart Source:** `navigator.dart:5573`
    public func pop(_ result: Any? = nil) {
        guard _routes.count > 1 else {
            dbg("Navigator.pop: Cannot pop the last route.")
            return
        }
        let route = _routes.last!
        if route.didPop(result) {
            // didPop returned true — the route accepts being popped.
            // finalizeRoute will be called by OverlayRoute.didPop if
            // finishedWhenPopped is true, which handles removing overlay
            // entries. For plain Route subclasses we finalize here.
            if !(route is OverlayRoute) {
                finalizeRoute(route)
            }
        }
        _updateRouteState()
    }

    /// Pop routes until the predicate returns true.
    ///
    /// The predicate is called with each route, starting from the top. Routes
    /// for which the predicate returns false are popped.
    ///
    /// **Dart Source:** `navigator.dart:5604`
    public func popUntil(_ predicate: (Route) -> Bool) {
        while let route = _routes.last, !predicate(route) {
            pop()
        }
    }

    /// Try to pop the top-most route. Returns true if a route was popped.
    ///
    /// **Dart Source:** `navigator.dart:5513`
    @discardableResult
    public func maybePop(_ result: Any? = nil) -> Bool {
        if canPop() {
            pop(result)
            return true
        }
        return false
    }

    /// Whether the navigator can pop (i.e., there is more than one route).
    ///
    /// **Dart Source:** `navigator.dart:5483`
    public func canPop() -> Bool {
        return _routes.count > 1
    }

    /// Called by routes (typically OverlayRoute.didPop) to finalize a route
    /// that has been popped.
    ///
    /// This removes the route from the history and removes its overlay entries
    /// from the overlay.
    ///
    /// **Dart Source:** `navigator.dart:5698`
    public func finalizeRoute(_ route: Route) {
        _routes.removeAll { $0 === route }
        _removeOverlayEntries(for: route)
        route.dispose()
        _updateRouteState()
    }

    // MARK: - Build

    /// Builds the navigator as an Overlay containing the overlay entries from
    /// all routes in the stack.
    ///
    /// **Dart Source:** `navigator.dart:5848`
    public override func build(_ context: any BuildContext) -> Widget {
        // Collect all overlay entries from all routes for initial entries.
        var allEntries: [OverlayEntry] = []
        for route in _routes {
            allEntries.append(contentsOf: route.overlayEntries)
        }

        return _NavigatorScope(
            navigatorState: self,
            child: Overlay(
                key: _overlayKey,
                initialEntries: allEntries,
                clipBehavior: .hardEdge
            )
        )
    }

    // MARK: - Internal

    /// Install a route and record it in the route stack.
    private func _pushRouteInternal(_ route: Route) {
        route.navigator = self
        route.install()

        _routes.append(route)

        // Insert the route's overlay entries into the overlay if it's already
        // mounted. On first build, the overlay is not yet available — entries
        // will be picked up from `build()` via `initialEntries`.
        if let overlayState = overlay {
            overlayState.insertAll(route.overlayEntries)
        }

        route.didPush()
    }

    /// Remove a route's overlay entries from the overlay.
    private func _removeOverlayEntries(for route: Route) {
        for entry in route.overlayEntries {
            entry.remove()
        }
    }

    /// Update isCurrent / isActive / isFirst on all routes.
    private func _updateRouteState() {
        for (index, route) in _routes.enumerated() {
            route.isCurrent = (index == _routes.count - 1)
            route.isActive = true
            route.isFirst = (index == 0)
            route.changedInternalState()
        }

        // Trigger rebuild so the overlay is updated.
        if mounted {
            setState { /* route stack changed */ }
        }
    }
}

// MARK: - _NavigatorScope

/// An InheritedWidget that provides the NavigatorState to descendants.
///
/// This is NOT used for `Navigator.of()` lookups (those use
/// `findAncestorStateOfType`), but it can be useful for routes that
/// need to mark the overlay for rebuild when the navigator state changes.
private class _NavigatorScope: InheritedWidget {
    let navigatorState: NavigatorState

    init(
        key: (any Key)? = nil,
        navigatorState: NavigatorState,
        child: Widget
    ) {
        self.navigatorState = navigatorState
        super.init(key: key, child: child)
    }

    override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        return navigatorState !== (oldWidget as! _NavigatorScope).navigatorState
    }
}

// MARK: - _SimpleRoute

/// A trivial Route that wraps a single widget as the navigator's initial route.
///
/// Used when `Navigator.home` is provided instead of `onGenerateRoute`. The
/// child comes from `childBuilder` at build time so each rebuild sees the
/// Navigator's current `home` — storing the widget itself would pin the
/// subtree to the instance captured at install (see `initState`).
private class _SimpleRoute: Route {
    let childBuilder: () -> Widget
    private var _entries: [OverlayEntry] = []

    init(childBuilder: @escaping () -> Widget) {
        self.childBuilder = childBuilder
        super.init()
    }

    override var overlayEntries: [OverlayEntry] { return _entries }

    override func install() {
        _entries = [
            OverlayEntry(builder: { [weak self] context in
                guard let self = self else {
                    return SizedBox(width: 0, height: 0)
                }
                return self.childBuilder()
            })
        ]
        super.install()
    }

    override func changedExternalState() {
        super.changedExternalState()
        for entry in _entries {
            entry.markNeedsBuild()
        }
    }

    override func dispose() {
        for entry in _entries {
            entry.dispose()
        }
        _entries.removeAll()
        super.dispose()
    }
}
