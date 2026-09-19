// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Overlay layers with a state of their own
//
// The desktop is one Stack built by the shell's state; a setState there
// rebuilds all of it, and at 2560x1600 with a dozen windows that is a few
// milliseconds. Two kinds of change happen far more often than the rest —
// a menu appearing or vanishing, a bar or a placed window moving — and they
// touch nothing but their own layer. Drawing those layers from widgets with
// a State of their own means the shell can refresh JUST that subtree
// (_popupsDidChange, _layerSurfacesDidChange): under wmbench's stress mix
// the full rebuilds were a fifth of the shell's main-thread time, most of
// them for a layer surface stepping across the screen.
//
// A full shell rebuild still remakes these widgets, which rebuilds them
// too — the desktop's other changes (a window moving under a menu) reach
// them that way. The widgets carry keys so their elements, and therefore
// their States and registrations, survive the parent's rebuilds.

/// The popups rooted at toplevel windows.
final class PopupLayer: StatefulWidget {
    let shell: _DesktopShellState
    init(shell: _DesktopShellState) {
        self.shell = shell
        super.init(key: ValueKey("popup-layer"))
    }
    override func createState() -> State<StatefulWidget> { PopupLayerState() }
}

final class PopupLayerState: State<StatefulWidget> {
    private var _shell: _DesktopShellState { (widget as! PopupLayer).shell }

    override func initState() {
        super.initState()
        _shell._popupLayerState = self
    }

    override func dispose() {
        if _shell._popupLayerState === self { _shell._popupLayerState = nil }
        super.dispose()
    }

    func refresh() { setState {} }

    override func build(_ context: any BuildContext) -> Widget {
        return Stack(fit: .expand, children: _shell._buildPopupWidgets().window)
    }
}

/// One group of layer surfaces (below the windows, above the bars, or the
/// session lock's). The group above the bars also draws the popups rooted
/// at its surfaces (a menu on a panel), which the popup pass stashes per
/// surface; it runs that pass itself, so a popup on a panel refreshes
/// this layer alone, like a popup on a window refreshes the popup layer.
final class LayerSurfacesLayer: StatefulWidget {
    let shell: _DesktopShellState
    let layers: Set<Int>
    let namespace: String?
    let slot: String
    init(shell: _DesktopShellState, layers: Set<Int>, slot: String, namespace: String? = nil) {
        self.shell = shell
        self.layers = layers
        self.namespace = namespace
        self.slot = slot
        super.init(key: ValueKey("layer-surfaces-\(slot)"))
    }
    override func createState() -> State<StatefulWidget> { LayerSurfacesLayerState() }
}

final class LayerSurfacesLayerState: State<StatefulWidget> {
    private var _widget: LayerSurfacesLayer { widget as! LayerSurfacesLayer }

    override func initState() {
        super.initState()
        _widget.shell._layerSurfaceLayerStates[_widget.slot] = self
    }

    override func dispose() {
        if _widget.shell._layerSurfaceLayerStates[_widget.slot] === self {
            _widget.shell._layerSurfaceLayerStates.removeValue(forKey: _widget.slot)
        }
        super.dispose()
    }

    func refresh() { setState {} }

    override func build(_ context: any BuildContext) -> Widget {
        let w = _widget
        // Placement from the buffers committed so far — the shell's build
        // does this too, but a refresh of this layer alone has to as well.
        w.shell._layoutLayerSurfaces()
        let stashed = (w.layers.contains(2) || w.layers.contains(3))
            ? w.shell._buildPopupWidgets().layerStashed : [:]
        return Stack(fit: .expand, children: w.shell._layerSurfaceWidgets(
            layers: w.layers, stashedLayerPopups: stashed, namespace: w.namespace))
    }
}

extension _DesktopShellState {

    /// A popup appeared, vanished, or got its size: rebuild the popup layer
    /// and, for one rooted at a top/overlay layer surface, the layer group
    /// that draws it. Both are cheap, so both are refreshed rather than
    /// walking the parent chain to pick one.
    func _popupsDidChange() {
        if _desktop3DActive { invalidateSecondaryScreens() }
        guard let layer = _popupLayerState else {
            setState {}
            return
        }
        layer.refresh()
        _layerSurfaceLayerStates["above"]?.refresh()
    }

    /// A layer surface moved, resized, changed alpha or got a buffer:
    /// rebuild the layer groups. Appearing and vanishing go through the
    /// shell's setState — they change insets and the keyboard's owner.
    func _layerSurfacesDidChange() {
        if _layerSurfaceLayerStates.isEmpty {
            setState {}
            return
        }
        for state in _layerSurfaceLayerStates.values { state.refresh() }
    }

    /// The popup pass: every mapped popup, positioned through its parent
    /// chain — a toplevel window, another popup, or a layer surface. Popups
    /// under a top/overlay layer surface come back stashed by that surface
    /// rather than in `window`, so the layer's group draws them above it.
    func _buildPopupWidgets(origin: Offset = .zero) -> (window: [Widget], layerStashed: [UInt32: [Widget]]) {
        var children: [Widget] = []
        var stashedLayerPopups: [UInt32: [Widget]] = [:]
        #if os(Linux)
        let sortedPopups = (_missionControlOpen && mcIsOnHost) ? [] : popups.sorted { a, b in
            // Count nesting depth by walking parent chain
            func depth(_ p: (key: String, value: (textureId: Int, parentSurfaceId: UInt32, x: Double, y: Double, width: Double, height: Double, mapped: Bool))) -> Int {
                var d = 0
                var sid = p.value.parentSurfaceId
                while let parent = popups["popup-\(sid)"] ?? popups["x11popup-\(sid)"] {
                    d += 1
                    sid = parent.parentSurfaceId
                }
                return d
            }
            let da = depth(a), db = depth(b)
            if da != db { return da < db }
            let aa = _popupAbove.contains(a.key), ab = _popupAbove.contains(b.key)
            if aa != ab { return !aa }   // keep-above sorts last (topmost)
            return (_popupZ[a.key] ?? 0) < (_popupZ[b.key] ?? 0)
        }
        for (popupId, popup) in sortedPopups {
            if !popup.mapped { continue }
            // Walk the parent chain to compute absolute popup position.
            // For nested popups (submenu of a menu), accumulate positions up to the toplevel.
            // Also track the immediate parent popup's absolute position for flip.
            var absX = popup.x
            var absY = popup.y
            var parentSurfaceId = popup.parentSurfaceId
            var immediateParentAbsX = 0.0
            var immediateParentWidth = 0.0
            var isFirstParent = true
            var popupSpaceId: Int? = nil
            var popupLayerRoot: UInt32? = nil
            var parentWindowId: String? = nil
            while true {
                // Check if parent is another popup (a submenu's menu)
                if let parentPopup = popups["popup-\(parentSurfaceId)"]
                                  ?? popups["x11popup-\(parentSurfaceId)"] {
                    if isFirstParent {
                        // Compute the immediate parent's absolute position (recursively)
                        // by noting we'll add its x to absX next.
                        immediateParentWidth = parentPopup.width
                        isFirstParent = false
                    }
                    absX += parentPopup.x
                    absY += parentPopup.y
                    parentSurfaceId = parentPopup.parentSurfaceId
                    continue
                }
                // Parent is a layer surface (a menu on a panel): its place
                // came from the layer layout above.
                if let layer = layerSurfaces[parentSurfaceId] {
                    absX += layer.absX
                    absY += layer.absY
                    popupLayerRoot = parentSurfaceId
                    if isFirstParent {
                        immediateParentAbsX = layer.absX
                        immediateParentWidth = layer.width
                    }
                    break
                }
                // Parent is a toplevel window — add window position. The id is a
                // Wayland surface id or, for an X11 menu, an X11 window id.
                var parentWinIdOpt: String? = waylandIntegration?.windowId(forSurfaceId: parentSurfaceId)
                if parentWinIdOpt == nil {
                    parentWinIdOpt = x11Integration?.shellWindowId(forX11Window: parentSurfaceId)
                }
                if let parentWinId = parentWinIdOpt,
                   let parentWin = windowManager.windows.first(where: { $0.id == parentWinId }) {
                    absX += parentWin.rect.left
                    absY += parentWin.rect.top + DesktopTheme.kTitleBarHeight
                    popupSpaceId = parentWin.spaceId
                    parentWindowId = parentWin.id
                    if isFirstParent {
                        // Direct child of toplevel — no flip needed for x
                        immediateParentAbsX = parentWin.rect.left
                        immediateParentWidth = parentWin.rect.width
                    }
                }
                break
            }

            // Popups live on their toplevel's space: a menu opened on space 1
            // must not float over space 2 after a switch.
            if let pid = parentWindowId,
               let win = windowManager.windows.first(where: { $0.id == pid }) {
                if win.spaceId != windowManager.activeSpaceId(onOutput: _desktop3DOutputId(for: win)) { continue }
                if _desktop3DActive && !_desktop3DIsShown(win) { continue }
            } else if let sid = popupSpaceId, sid != windowManager.activeSpace.id { continue }

            // Compute immediate parent popup's absolute x for flip.
            if !isFirstParent {
                immediateParentAbsX = absX - popup.x
            }

            // Constraint adjustment: keep popups within screen bounds — a
            // MENU's; a free-standing override-redirect X11 window (parent
            // 0) is placed by its client, root-absolute, and may hang off
            // an edge on purpose (a bar, a benchmark's offscreen check).
            let rootAnchored = popupId.hasPrefix("x11popup-") && popup.parentSurfaceId == 0
            if !rootAnchored {
                if absX + popup.width > screenWidth {
                    if !isFirstParent {
                        // Nested popup (submenu): flip to left side of parent popup.
                        absX = immediateParentAbsX - popup.width
                    } else {
                        // Direct child of toplevel: slide left to fit.
                        absX = screenWidth - popup.width
                    }
                }
                if absX < 0 { absX = 0 }
                if absY + popup.height > screenHeight {
                    absY = screenHeight - popup.height
                }
                if absY < 0 { absY = 0 }
            }

            let isX11Popup = popupId.hasPrefix("x11popup-")
            var texture: Widget = TextureWidget(textureId: popup.textureId, filterQuality: .none)
            if let a = popupAlpha[popupId], a < 1.0 {
                texture = Opacity(opacity: max(0.0, a), child: texture)
            }
            // Both need the flip: Wayland surfaces arrive bottom-up, and an X11
            // menu is a DMA-BUF from Vulkan/GL exactly like its toplevels, which
            // pass flipTextureY: true. A solid-colour test popup looks identical
            // either way — only real content (mirrored menu labels) shows it.
            let flipped: Widget = Transform(
                transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                alignment: Alignment.center,
                child: texture
            )

            // Wrap in Listener to forward pointer events to popup surface.
            let popupChild: Widget
            if isX11Popup,
               let x11 = x11Integration,
               let x11WinId = UInt32(popupId.dropFirst("x11popup-".count)) {
                // Menus are only useful if you can click them. Same physical-px
                // conversion the X11 toplevel path does.
                let toPhys = currentShellDpi
                popupChild = Listener(
                    onPointerDown: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 2,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: Int64(event.buttons))
                    },
                    onPointerMove: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 3,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: Int64(event.buttons))
                    },
                    onPointerUp: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 1,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: 0)
                    },
                    onPointerHover: { event in
                        x11.sendPointerEvent(windowId: x11WinId, phase: 6,
                                             x: event.localPosition.dx * toPhys,
                                             y: event.localPosition.dy * toPhys,
                                             buttons: 0)
                    },
                    child: flipped
                )
            } else if let wl = waylandIntegration,
               let surfaceId = wl.surfaceId(forWindowId: popupId) {
                popupChild = Listener(
                    onPointerDown: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 2,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: Int64(event.buttons)
                        )
                    },
                    onPointerMove: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 3,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: Int64(event.buttons)
                        )
                    },
                    onPointerUp: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 1,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: 0
                        )
                    },
                    onPointerHover: { event in
                        wl.sendPointerEvent(
                            surfaceId: surfaceId,
                            phase: 6,
                            x: event.localPosition.dx,
                            y: event.localPosition.dy,
                            buttons: 0
                        )
                    },
                    onPointerSignal: { event in
                        if let scroll = event as? PointerScrollEvent {
                            wl.sendScrollEvent(
                                surfaceId: surfaceId,
                                x: scroll.localPosition.dx,
                                y: scroll.localPosition.dy,
                                scrollDeltaX: scroll.scrollDelta.dx,
                                scrollDeltaY: scroll.scrollDelta.dy
                            )
                        }
                    },
                    behavior: .opaque,
                    child: flipped
                )
            } else {
                popupChild = flipped
            }

            // In the room, the popup rides its window's pane: the same
            // matrix, centred on the same pivot made popup-local, so a menu
            // on a window seen at an angle lies on the glass with it and
            // its clicks map back through the same inverse. A window not
            // drawn (behind the viewer, out of sight) keeps its popups too.
            var popupBody: Widget = popupChild
            if let pid = parentWindowId, let placement = _desktop3DPopupPlacements[pid] {
                switch placement {
                case .hidden:
                    continue
                case .posed(let m, let pivot):
                    popupBody = Transform(
                        transform: m,
                        origin: Offset(pivot.dx - absX, pivot.dy - absY),
                        child: popupChild)
                case .flat:
                    break
                }
            }
            let positioned = Positioned(
                key: ValueKey(popupId),
                left: absX - origin.dx,
                top: absY - origin.dy,
                width: popup.width,
                height: popup.height,
                child: popupBody
            )
            // A menu on a top/overlay layer surface must sit above it, and
            // that layer is drawn after this pass.
            if let root = popupLayerRoot, (layerSurfaces[root]?.info.layer ?? 0) >= 2 {
                stashedLayerPopups[root, default: []].append(positioned)
            } else {
                children.append(positioned)
            }
        }
        #endif
        // The drag-and-drop icon rides the pointer, above every popup.
        if let icon = _dragIcon, icon.width > 0, icon.height > 0 {
            let flipped = Transform(
                transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                alignment: Alignment.center,
                child: TextureWidget(textureId: icon.textureId, filterQuality: .none))
            children.append(Positioned(
                left: _lastPointer.dx, top: _lastPointer.dy,
                width: icon.width, height: icon.height,
                child: IgnorePointer(child: flipped)))
        }
        return (children, stashedLayerPopups)
    }
}
