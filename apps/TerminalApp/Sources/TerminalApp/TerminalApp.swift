// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Terminal app: a workspace of floating terminal panes. Each pane owns
// a TerminalSession and renders it with the sdk's TerminalView (docs/plans/
// terminal-widget.md) — the app itself is only geometry, chrome and
// z-order. That the terminal is now a widget is what makes N of them a
// hundred lines rather than a rewrite.
//
// It stays the perf and conformance testbed, but the panes get in the way
// of that: the bench protocol fullscreens the window and expects the grid
// to fill it, and a pane is a box inside it. STARLING_TERMINAL_SINGLE=1
// therefore renders ONE full-window TerminalView with no chrome — the
// pre-pane tree exactly — and the harness sets it (test/bench/core/).

import Flutter
import FlutterSwiftBridge   // Color, Offset, Size
import Foundation

// MARK: - Theme

private enum PaneTheme {
    static let desktop = Color(0xD9161A1F)
    static let titleBar = Color(0xFF2A2F37)
    static let titleBarActive = Color(0xFF343B45)
    static let titleText = Color(0xFFB6BDC7)
    static let titleTextActive = Color(0xFFE6EAF0)
    static let border = Color(0xFF0E1116)
    static let close = Color(0xFFFF5F57)
    static let closeIdle = Color(0xFF6E5A5E)
    static let toolbarText = Color(0xFFC8CED8)
    static let toolbarFill = Color(0xFF2A2F37)
    static let grip = Color(0x66FFFFFF)

    static let titleBarH: Double = 30
    static let gripSize: Double = 16
    static let minW: Double = 260
    static let minH: Double = 120
}

// MARK: - A pane

/// One floating terminal: a session, a rectangle, and an identity that
/// survives rebuilds.
private final class Pane {
    let id: Int
    let session: TerminalSession
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(id: Int, x: Double, y: Double, w: Double, h: Double) {
        self.id = id
        self.session = TerminalSession()
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    /// The terminal's own box: the pane minus its title bar.
    var terminalSize: Size { Size(w, max(1, h - PaneTheme.titleBarH)) }
}

// MARK: - TerminalApp

class TerminalApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TerminalAppState()
    }
}

class _TerminalAppState: State<StatefulWidget>, @unchecked Sendable {

    /// Painting order, so the last entry is the top pane and also the
    /// focused one. Bringing a pane forward moves it to the end.
    private var panes: [Pane] = []
    private var _nextId = 1

    /// Pointer position at the last move event, for delta dragging (the
    /// pane moves under the pointer, so successive LOCAL positions would
    /// chase each other — globals do not).
    private var _lastPointer: Offset? = nil
    private enum DragKind { case move, resize }
    private var _dragKind: DragKind = .move

    override func initState() {
        super.initState()
        _newPane()
    }

    override func dispose() {
        for pane in panes { pane.session.terminate() }
        super.dispose()
    }

    // MARK: - Pane lifecycle

    @discardableResult
    private func _newPane() -> Pane {
        // Cascade so a new pane never lands exactly on the last one.
        let n = Double(panes.count % 8)
        let size = _windowSize()
        let w = min(860, max(PaneTheme.minW, size.width - 120))
        let h = min(520, max(PaneTheme.minH, size.height - 140))
        let pane = Pane(id: _nextId, x: 40 + n * 28, y: 52 + n * 24, w: w, h: h)
        _nextId += 1
        pane.session.startShell()
        panes.append(pane)
        return pane
    }

    private func _close(_ pane: Pane) {
        pane.session.terminate()
        panes.removeAll { $0 === pane }
        // Never leave an empty desktop: the app with no panes has no way
        // back except the toolbar, and a terminal that closes to nothing
        // reads as the app having quit.
        if panes.isEmpty { _newPane() }
        setState {}
    }

    private func _bringToFront(_ pane: Pane) {
        guard panes.last !== pane else { return }
        panes.removeAll { $0 === pane }
        panes.append(pane)
        setState {}
    }

    private func _windowSize() -> Size {
        if let view = PlatformDispatcher.instance.implicitView {
            let dpr = view.devicePixelRatio
            let phys = view.physicalSize
            if phys.width > 0, phys.height > 0, dpr > 0 {
                return Size(phys.width / dpr, phys.height / dpr)
            }
        }
        return Size(1100, 700)
    }

    // MARK: - Build

    /// Bench/embedding mode: one terminal, whole window, no pane chrome.
    /// The measured tree is then exactly a TerminalView, which is what the
    /// numbers in docs/perf/ are about.
    private static let single =
        ProcessInfo.processInfo.environment["STARLING_TERMINAL_SINGLE"] != nil

    override func build(_ context: any BuildContext) -> Widget {
        if Self.single, let only = panes.first {
            return TerminalView(session: only.session)
        }
        var layers: [Widget] = [
            // The desktop under the panes. Clicking it is not a click on any
            // pane, so it just drops the drag.
            Positioned(fill: (), child: ColoredBox(color: PaneTheme.desktop))
        ]
        for pane in panes {
            layers.append(_paneWidget(pane, focused: pane === panes.last))
        }
        layers.append(_toolbar())
        return Stack(children: layers)
    }

    private func _toolbar() -> Widget {
        return Positioned(
            left: 12, top: 10,
            child: Listener(
                onPointerDown: { [self] _ in
                    setState { _newPane() }
                },
                behavior: .opaque,
                child: SizedBox(
                    width: 132, height: 28,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: PaneTheme.toolbarFill,
                            borderRadius: BorderRadius.all(Radius(circular: 6))
                        ),
                        child: Center(
                            child: Text(
                                "+  New Terminal",
                                style: TextStyle(
                                    color: PaneTheme.toolbarText,
                                    fontSize: 12,
                                    fontFamily: TerminalFontLoader.family,
                                    fontFamilyFallback: TerminalFontLoader.fallback
                                )
                            )
                        )
                    )
                )
            )
        )
    }

    private func _paneWidget(_ pane: Pane, focused: Bool) -> Widget {
        let body = Column(
            crossAxisAlignment: .stretch,
            children: [
                _titleBar(pane, focused: focused),
                SizedBox(
                    width: pane.w,
                    height: pane.terminalSize.height,
                    child: TerminalView(
                        session: pane.session,
                        // The pane knows its box; the view must not size its
                        // grid from the window (see TerminalView.size).
                        size: pane.terminalSize,
                        // Only the top pane takes the keyboard, and it takes
                        // it on mount — bringing a pane forward reorders the
                        // children, which remounts it, which focuses it.
                        autofocus: focused
                    )
                ),
            ]
        )

        return Positioned(
            left: pane.x, top: pane.y,
            child: SizedBox(
                width: pane.w, height: pane.h,
                child: Listener(
                    // Anywhere in the pane: raise it. The terminal below
                    // still gets the click (translucent behaviour), so a
                    // click both focuses the pane and places the cursor.
                    onPointerDown: { [self] _ in _bringToFront(pane) },
                    behavior: .translucent,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            border: Border.all(color: PaneTheme.border, width: 1),
                            borderRadius: BorderRadius.all(Radius(circular: 8)),
                            boxShadow: focused
                                ? [BoxShadow(color: Color(0x66000000),
                                             offset: Offset(0, 6), blurRadius: 18)]
                                : [BoxShadow(color: Color(0x33000000),
                                             offset: Offset(0, 2), blurRadius: 8)]
                        ),
                        child: ClipRRect(
                            borderRadius: BorderRadius.all(Radius(circular: 8)),
                            child: Stack(children: [
                                body,
                                _resizeGrip(pane),
                            ])
                        )
                    )
                )
            )
        )
    }

    private func _titleBar(_ pane: Pane, focused: Bool) -> Widget {
        let label = "Terminal \(pane.id)"
        return SizedBox(
            width: pane.w, height: PaneTheme.titleBarH,
            child: Listener(
                onPointerDown: { [self] event in
                    _bringToFront(pane)
                    _dragKind = .move
                    _lastPointer = event.position
                },
                onPointerMove: { [self] event in
                    guard _dragKind == .move, let last = _lastPointer else { return }
                    let dx = event.position.dx - last.dx
                    let dy = event.position.dy - last.dy
                    _lastPointer = event.position
                    let bounds = _windowSize()
                    setState {
                        // Keep a grabbable strip on screen: a pane dragged
                        // entirely past an edge could not be dragged back.
                        pane.x = min(max(pane.x + dx, -pane.w + 80), bounds.width - 80)
                        pane.y = min(max(pane.y + dy, 0), bounds.height - PaneTheme.titleBarH)
                    }
                },
                onPointerUp: { [self] _ in _lastPointer = nil },
                behavior: .opaque,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: focused ? PaneTheme.titleBarActive : PaneTheme.titleBar
                    ),
                    child: Stack(children: [
                        Center(
                            child: Text(
                                label,
                                style: TextStyle(
                                    color: focused ? PaneTheme.titleTextActive
                                                   : PaneTheme.titleText,
                                    fontSize: 12,
                                    fontFamily: TerminalFontLoader.family,
                                    fontFamilyFallback: TerminalFontLoader.fallback
                                )
                            )
                        ),
                        Positioned(
                            left: 10, top: 9,
                            child: Listener(
                                onPointerDown: { [self] _ in _close(pane) },
                                behavior: .opaque,
                                child: SizedBox(
                                    width: 12, height: 12,
                                    child: DecoratedBox(
                                        decoration: BoxDecoration(
                                            color: focused ? PaneTheme.close
                                                           : PaneTheme.closeIdle,
                                            shape: .circle
                                        )
                                    )
                                )
                            )
                        ),
                    ])
                )
            )
        )
    }

    private func _resizeGrip(_ pane: Pane) -> Widget {
        return Positioned(
            left: pane.w - PaneTheme.gripSize,
            top: pane.h - PaneTheme.gripSize,
            child: Listener(
                onPointerDown: { [self] event in
                    _bringToFront(pane)
                    _dragKind = .resize
                    _lastPointer = event.position
                },
                onPointerMove: { [self] event in
                    guard _dragKind == .resize, let last = _lastPointer else { return }
                    let dx = event.position.dx - last.dx
                    let dy = event.position.dy - last.dy
                    _lastPointer = event.position
                    setState {
                        pane.w = max(PaneTheme.minW, pane.w + dx)
                        pane.h = max(PaneTheme.minH, pane.h + dy)
                    }
                },
                onPointerUp: { [self] _ in
                    _lastPointer = nil
                    _dragKind = .move
                },
                behavior: .opaque,
                child: SizedBox(
                    width: PaneTheme.gripSize, height: PaneTheme.gripSize,
                    child: Center(
                        child: SizedBox(
                            width: 8, height: 8,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: PaneTheme.grip,
                                    borderRadius: BorderRadius.all(Radius(circular: 2))
                                )
                            )
                        )
                    )
                )
            )
        )
    }
}
