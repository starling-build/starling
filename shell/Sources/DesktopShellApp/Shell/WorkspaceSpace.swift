// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

//
// Workspace mode: the list of workspaces on the left, the app you are working
// in down the middle, and whatever it opened on the right as tabs.
//
// Three columns rather than two so a workspace is a place you keep, not a mode
// you toggle: the rail is how you move between them. The middle column is
// nil-able on purpose — when the driver quits, the workspace and its other
// windows survive and the middle returns to its empty state.
//
// Windows here are owned (WindowInfo.ownerAgentId carries the workspace id),
// which is what keeps them out of the dock, tiling, Mission Control and focus
// on the ordinary desktop. See WindowManager.windows(inWorkspace:).
//
// This replaced the AI Space, whose workbench UI is gone. What remains of that
// is AgentWindows.swift: headless windows for broker clients, which the
// functional tier drives through the semantics endpoint.
//

import CupertinoIcons
import Flutter
import FlutterSwiftBridge
import Foundation
import StarlingRegistry

private enum WS {
    static let railW: Double = 260       // workspace list
    static let driverMin: Double = 420
    static let driverMax: Double = 1100
    static let dividerW: Double = 8
    static let pad: Double = 14
    static let rowH: Double = 44
    static let tabH: Double = 26
    static let tabGap: Double = 6
    static let tabTop: Double = 11
    static let paneGap: Double = 10
    /// Tab width bounds. The floor is icon-plus-padding: below it a tab says
    /// nothing, so the strip spills into a "+N" chip instead of shrinking on.
    static let tabWMin: Double = 34
    static let tabWMax: Double = 190
    /// Floor for the right-hand column, so the shared divider position cannot
    /// collapse it when the workspace is shown on a narrow output.
    static let minTabColumnW: Double = 280
}

extension _DesktopShellState {

    /// The workspace UI, laid out for ONE output — each monitor in workspace
    /// mode runs its OWN workspace now. Everything here is in that output's local
    /// coordinates, so the caller positions it at the output's origin and the
    /// same code serves the primary tree and any secondary screen.
    ///
    /// It cannot be drawn on two outputs at once, and not for a rendering
    /// reason: `_applyWorkspaceWindowGeometry` resizes the real client windows
    /// to the pane, and one client has one buffer size. See
    /// `docs/plans/multi-output.md`.
    func _buildWorkspaceSpace(output: DisplayOutput) -> Widget {
        // Inner builders (the rail) read the selection through this — an
        // extension cannot add stored state per call, and builds are
        // single-threaded, so the entry point pins its output here.
        _wsBuildOutputId = output.id
        let w = output.logicalWidth
        let h = output.logicalHeight
        _applyWorkspaceWindowGeometry(output: output)
        var layers: [Widget] = []
        let top = DesktopTheme.kStatusBarHeight

        // Dim scrim, so the space reads as its own mode rather than a desktop
        // that happens to have windows arranged on it. Near-opaque on purpose:
        // at half alpha the wallpaper read straight through the columns and
        // the mode looked like two empty outlines floating on the desktop.
        // The wallpaper survives as a tint, not as a picture.
        layers.append(Positioned(fill: (), child: ColoredBox(
            color: Color(0xF20E0F15), child: SizedBox(expand: ()))))

        layers.append(contentsOf: _workspaceRail(top: top, h: h))

        guard let ws = windowManager.selectedWorkspace(onOutput: output.id) else {
            return Stack(children: layers)
        }

        let driverW = _workspaceDriverWidth(forOutputWidth: w)
        let driverLeft = WS.railW
        let rightLeft = driverLeft + driverW + WS.dividerW

        layers.append(contentsOf: _workspaceDriverColumn(
            ws, left: driverLeft, width: driverW, top: top, h: h))
        layers.append(contentsOf: _workspaceDivider(
            left: driverLeft + driverW, top: top, h: h))
        layers.append(contentsOf: _workspaceTabColumn(
            ws, left: rightLeft, width: w - rightLeft, top: top, h: h))
        layers.append(contentsOf: _workspaceRenameLayer())
        layers.append(contentsOf: _workspaceMenuLayer(w, h))
        // Topmost, so nothing opaque below can swallow the hover; translucent,
        // so every click still lands on whatever is under it.
        layers.append(_workspaceHoverProbe(top: top))

        return Stack(children: layers)
    }

    /// The divider position is one shared number, but the outputs it may be
    /// rendered on are not the same width. Clamp it so a narrower monitor
    /// cannot push the tab column to zero (or negative) width.
    func _workspaceDriverWidth(forOutputWidth w: Double) -> Double {
        let maxForOutput = max(WS.driverMin,
                               w - WS.railW - WS.dividerW - WS.minTabColumnW)
        return min(min(WS.driverMax, maxForOutput), max(WS.driverMin, _workspaceDriverW))
    }

    // MARK: Rail

    private func _workspaceRail(top: Double, h: Double) -> [Widget] {
        var out: [Widget] = []
        out.append(Positioned(
            left: 0, top: top, width: WS.railW, height: h - top,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Color(0xE60F1118),
                    border: Border(right: BorderSide(color: Color(0x26FFFFFF), width: 1))),
                child: SizedBox(expand: ()))))
        out.append(Positioned(
            left: WS.pad, top: top + 13,
            child: IgnorePointer(child: Text("Workspaces", style: TextStyle(
                color: shellTheme.overlayText, fontSize: 15, fontWeight: .w700)))))
        out.append(Positioned(
            left: WS.railW - WS.pad - 78, top: top + 9, width: 78, height: 26,
            child: _workspaceButton("+ New", fontSize: 11) { [self] in
                setState { windowManager.addWorkspace(onOutput: _wsBuildOutputId) }
            }))

        let selectedId = windowManager.selectedWorkspace(onOutput: _wsBuildOutputId)?.id
        var rowY = top + 50
        for ws in windowManager.workspaces {
            let isSel = ws.id == selectedId
            let wsId = ws.id
            let count = windowManager.windows(inWorkspace: wsId).count
            let subtitle = count == 0 ? "empty"
                : (count == 1 ? "1 window" : "\(count) windows")
            let renaming = _wsRenamingId == wsId
            let anchor = Offset(20, rowY + WS.rowH + 2)
            var row: [Widget] = [
                Positioned(fill: (), child: GestureDetector(
                    onTap: { [self] in
                        setState {
                            windowManager.selectWorkspace(wsId, onOutput: _wsBuildOutputId)
                        }
                    },
                    onSecondaryTap: { [self] in
                        setState {
                            windowManager.selectWorkspace(wsId, onOutput: _wsBuildOutputId)
                            _wsTabMenuWinId = nil
                            _wsRailMenuWsId = wsId
                            _wsMenuAt = anchor
                        }
                    },
                    behavior: .opaque,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: isSel ? Color(0x26FFFFFF) : Color(0x0DFFFFFF),
                            border: Border.all(
                                color: (renaming || isSel) ? shellTheme.accent
                                                           : Color(0x1FFFFFFF),
                                width: renaming ? 2 : 1),
                            borderRadius: BorderRadius.all(Radius(circular: 8))),
                        child: SizedBox(expand: ())))),
                Positioned(left: 12, top: 6,
                    child: IgnorePointer(child: Text(
                        renaming ? _wsRenameBuffer + "|" : ws.name,
                        style: TextStyle(
                            color: shellTheme.overlayText, fontSize: 12,
                            fontWeight: .w600)))),
                Positioned(left: 12, top: 24,
                    child: IgnorePointer(child: Text(
                        renaming ? "Enter to save · Esc to cancel" : subtitle,
                        style: TextStyle(
                            color: shellTheme.overlayTextDim,
                            fontSize: 10.5, fontWeight: .w400)))),
            ]
            // Only the row under the pointer offers it, so the rail reads as
            // a plain list until you reach for something.
            if _wsHoverRailId == wsId && !renaming {
                row.append(Positioned(
                    left: WS.railW - 20 - 34, top: 10, width: 24, height: 24,
                    child: _wsRenameAffordance(wsId)))
            }
            out.append(Positioned(
                key: ValueKey("ws-row-\(ws.id)"),
                left: 10, top: rowY, width: WS.railW - 20, height: WS.rowH,
                child: Stack(children: row)))
            rowY += WS.rowH + 8
        }
        return out
    }

    // MARK: Driver column

    private func _workspaceDriverColumn(
        _ ws: WorkspaceInfo, left: Double, width: Double, top: Double, h outputH: Double
    ) -> [Widget] {
        var out: [Widget] = []
        let h = outputH - top - WS.paneGap * 2

        guard let driverId = ws.driverWindowId,
              let win = windowManager.windows.first(where: { $0.id == driverId }) else {
            // Empty state: the + is the only thing to do here, so it is the
            // whole column rather than a control parked in a corner.
            let wsId = ws.id
            out.append(Positioned(
                left: left + WS.paneGap, top: top + WS.paneGap,
                width: width - WS.paneGap * 2, height: h,
                child: GestureDetector(
                    onTap: { [self] in openLauncher(driverTarget: wsId) },
                    behavior: .opaque,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Color(0x14FFFFFF),
                            border: Border.all(color: Color(0x2EFFFFFF), width: 1),
                            borderRadius: BorderRadius.all(Radius(circular: 10))),
                        child: Center(child: Column(
                            mainAxisAlignment: .center,
                            children: [
                                Text("+", style: TextStyle(
                                    color: shellTheme.overlayText,
                                    fontSize: 40, fontWeight: .w300)),
                                SizedBox(height: 8),
                                Text("Choose an app to work in", style: TextStyle(
                                    color: shellTheme.overlayTextDim,
                                    fontSize: 12.5, fontWeight: .w400)),
                            ]))))))
            return out
        }

        let focused = windowManager.focusedWindowId == win.id
        out.append(Positioned(
            key: ValueKey("ws-driver-\(win.id)"),
            left: left + WS.paneGap, top: top + WS.paneGap,
            width: width - WS.paneGap * 2, height: h,
            child: _workspacePane(win, focused: focused)))
        return out
    }

    // MARK: Tab column

    private func _workspaceTabColumn(
        _ ws: WorkspaceInfo, left: Double, width: Double, top: Double, h: Double
    ) -> [Widget] {
        var out: [Widget] = []
        // The driver is shown in the middle, never as a tab.
        let tabs = windowManager.windows(inWorkspace: ws.id)
            .filter { $0.id != ws.driverWindowId }

        let paneTop0 = top + WS.tabTop + WS.tabH + WS.paneGap
        guard !tabs.isEmpty else {
            // A bordered surface, matching the driver column's empty state:
            // bare text on the scrim read as a stray label rather than as a
            // panel waiting for content.
            out.append(Positioned(
                left: left + WS.paneGap, top: paneTop0,
                width: width - WS.paneGap * 2,
                height: h - paneTop0 - WS.paneGap,
                child: IgnorePointer(child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x14FFFFFF),
                        border: Border.all(color: Color(0x2EFFFFFF), width: 1),
                        borderRadius: BorderRadius.all(Radius(circular: 10))),
                    child: Center(child: Text(
                        "Apps opened here will appear in this panel",
                        style: TextStyle(color: shellTheme.overlayTextDim,
                                         fontSize: 12.5, fontWeight: .w400)))))))
            out.append(Positioned(
                left: left + WS.paneGap, top: top + WS.tabTop,
                width: 30, height: WS.tabH,
                child: _workspaceButton("+", fontSize: 14) { [self] in
                    openLauncher()
                }))
            return out
        }

        // Follow the workspace unless a tab was explicitly picked; a stale
        // pick (its window closed) falls back rather than showing nothing.
        let explicit = _workspaceActiveTab[ws.id]
        let active = tabs.first(where: { $0.id == explicit }) ?? tabs[tabs.count - 1]

        // Budget the strip so the trailing `+` is always reachable: it is the
        // only way to open an app from in here, and the old sizing floored the
        // tab width while `x` kept advancing, so past ~6 windows both the last
        // tabs and the `+` ran off the panel edge.
        let plusW = 30.0
        let stripW = width - WS.paneGap * 2
        let avail = stripW - plusW - WS.tabGap
        var shown = tabs
        var hidden = 0
        var tabW = min(WS.tabWMax,
                       (avail - WS.tabGap * Double(tabs.count - 1))
                           / Double(tabs.count))
        let chipW = 30.0
        if tabW < WS.tabWMin {
            // Still too many at the floor: show what fits beside a "+N"
            // chip, and count the rest into it.
            tabW = WS.tabWMin
            let forTabs = avail - chipW - WS.tabGap
            let fit = max(1, Int((forTabs + WS.tabGap) / (tabW + WS.tabGap)))
            if fit < tabs.count {
                hidden = tabs.count - fit
                shown = Array(tabs.prefix(fit))
                // The selected tab must never be one of the hidden ones —
                // its pane is what fills the panel below.
                if !shown.contains(where: { $0.id == active.id }) {
                    shown[fit - 1] = active
                }
            }
        }

        var x = left + WS.paneGap
        for tab in shown {
            let isActive = tab.id == active.id
            let tabId = tab.id
            let wsId = ws.id
            let labelled = tabW >= 84
            var row: [Widget] = [
                SizedBox(width: 13, height: 13, child: CustomPaint(
                    painter: IconPainter(
                        _iconType(for: _wsBaseAppId(tab.appId)),
                        color: isActive ? shellTheme.overlayText
                                        : shellTheme.overlayTextDim))),
            ]
            if labelled {
                row.append(SizedBox(width: 6))
                row.append(Text(
                    String(tab.title.prefix(Int((tabW - 34) / 6.2))),
                    style: TextStyle(
                        color: isActive ? shellTheme.overlayText
                                        : shellTheme.overlayTextDim,
                        fontSize: 11, fontWeight: isActive ? .w600 : .w400)))
            }
            let anchor = Offset(x, top + WS.tabTop + WS.tabH + 4)
            out.append(Positioned(
                key: ValueKey("ws-tab-\(tab.id)"),
                left: x, top: top + WS.tabTop, width: tabW, height: WS.tabH,
                child: GestureDetector(
                    onTap: { [self] in
                        setState { _workspaceActiveTab[wsId] = tabId }
                    },
                    onSecondaryTap: { [self] in
                        setState {
                            _workspaceActiveTab[wsId] = tabId
                            _wsRailMenuWsId = nil
                            _wsTabMenuWinId = tabId
                            _wsMenuAt = anchor
                        }
                    },
                    behavior: .opaque,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: isActive ? Color(0x30FFFFFF) : Color(0x14FFFFFF),
                            border: Border.all(
                                color: isActive ? shellTheme.accent : Color(0x1FFFFFFF),
                                width: 1),
                            borderRadius: BorderRadius.all(Radius(circular: 6))),
                        child: Center(child: Row(
                            mainAxisAlignment: .center, children: row))))))
            x += tabW + WS.tabGap
        }
        if hidden > 0 {
            out.append(Positioned(
                left: x, top: top + WS.tabTop, width: chipW, height: WS.tabH,
                child: IgnorePointer(child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x14FFFFFF),
                        borderRadius: BorderRadius.all(Radius(circular: 6))),
                    child: Center(child: Text(
                        "+\(hidden)",
                        style: TextStyle(color: shellTheme.overlayTextDim,
                                         fontSize: 10, fontWeight: .w600)))))))
        }
        // Immediately after the last tab (or the overflow chip), never parked
        // at the panel edge: it has to sit in the same place relative to the
        // strip whether or not there are tabs yet, or it jumps across the
        // panel the moment the first app opens. The width budget above
        // reserves its slot, so "after the last tab" is always on screen.
        // The dock is faded out in this mode, so without this there is no way
        // to open a second app from inside a workspace.
        out.append(Positioned(
            left: hidden > 0 ? x + chipW + WS.tabGap : x,
            top: top + WS.tabTop, width: plusW, height: WS.tabH,
            child: _workspaceButton("+", fontSize: 14) { [self] in
                openLauncher()
            }))

        let paneTop = top + WS.tabTop + WS.tabH + WS.paneGap
        out.append(Positioned(
            key: ValueKey("ws-pane-\(active.id)"),
            left: left + WS.paneGap, top: paneTop,
            width: width - WS.paneGap * 2,
            height: h - paneTop - WS.paneGap,
            child: _workspacePane(
                active, focused: windowManager.focusedWindowId == active.id)))
        return out
    }

    // MARK: Divider

    private func _workspaceDivider(left: Double, top: Double, h: Double) -> [Widget] {
        [Positioned(
            left: left, top: top, width: WS.dividerW, height: h - top,
            child: Listener(
                onPointerDown: { [self] _ in _workspaceDividerDragging = true },
                onPointerMove: { [self] event in
                    guard _workspaceDividerDragging else { return }
                    let w = event.position.dx - WS.railW - WS.dividerW / 2
                    setState {
                        _workspaceDriverW = min(WS.driverMax, max(WS.driverMin, w))
                    }
                },
                // Clients are reconfigured once, on release: resizing a live
                // app every frame of a drag is what made this stutter.
                onPointerUp: { [self] _ in
                    _workspaceDividerDragging = false
                    setState { _applyWorkspaceWindowGeometry() }
                },
                onPointerHover: { _ in DesktopCursor.setShape(.resizeEW) },
                behavior: .opaque,
                child: ColoredBox(color: Color(0x1AFFFFFF),
                                  child: SizedBox(expand: ()))))]
    }

    // MARK: Panes

    /// A live window rendered into a pane: texture, Y-flip where the client
    /// needs it, and pointer/scroll forwarded in the window's own coordinates.
    private func _workspacePane(_ win: WindowInfo, focused: Bool) -> Widget {
        var content: Widget
        if let texId = win.textureId {
            content = TextureWidget(textureId: texId, filterQuality: .low)
            if win.flipTextureY {
                content = Transform(
                    transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                    alignment: Alignment.center,
                    child: content)
            }
        } else {
            content = ColoredBox(color: Color(0xFF1A1A20), child: SizedBox(expand: ()))
        }
        let winId = win.id
        // Panes are laid out at the window's own size (see
        // _applyWorkspaceWindowGeometry), so there is no scale factor to undo
        // on the way in: no scale factor to undo.
        let forwarded: Widget = Listener(
            onPointerDown: { [self] event in
                if windowManager.focusedWindowId != winId {
                    setState { windowManager.focusedWindowId = winId }
                }
                win.onPointerEvent?(2, event.localPosition.dx,
                                    event.localPosition.dy, Int64(event.buttons))
            },
            onPointerMove: { event in
                win.onPointerEvent?(3, event.localPosition.dx,
                                    event.localPosition.dy, Int64(event.buttons))
            },
            onPointerUp: { event in
                win.onPointerEvent?(1, event.localPosition.dx,
                                    event.localPosition.dy, 0)
            },
            onPointerHover: { event in
                DesktopCursor.setShape(.default)
                win.onPointerEvent?(6, event.localPosition.dx,
                                    event.localPosition.dy, 0)
            },
            onPointerSignal: { event in
                if let scroll = event as? PointerScrollEvent {
                    win.onScrollEvent?(scroll.localPosition.dx,
                                       scroll.localPosition.dy,
                                       scroll.scrollDelta.dx, scroll.scrollDelta.dy)
                }
            },
            behavior: .opaque,
            child: content)
        return DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(
                    color: focused ? shellTheme.accent : Color(0x40FFFFFF),
                    width: focused ? 2 : 1),
                borderRadius: BorderRadius.all(Radius(circular: 6))),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: 6)),
                child: forwarded))
    }

    // MARK: Geometry

    /// The pane rect is authoritative and the client follows it. Diff-guarded:
    /// onContentResize reconfigures a live app, so calling it with the size it
    /// already has is a wasted round trip through the child.
    /// Size the workspace's client windows to their panes on the output the
    /// workspace is shown on. This configures the REAL clients (each
    /// `onContentResize` is a Wayland configure or a DMA-BUF child resize),
    /// which is why the workspace can only live on one output at a time.
    func _applyWorkspaceWindowGeometry(output: DisplayOutput? = nil) {
        let out = output ?? displayLayout?.host
            ?? DisplayOutput(id: 0, name: "primary",
                             physicalWidth: Int(screenWidth * currentShellDpi),
                             physicalHeight: Int(screenHeight * currentShellDpi),
                             scale: currentShellDpi, originX: 0, originY: 0,
                             isHost: true, isPrimary: true, refreshMhz: 60000)
        guard let ws = windowManager.selectedWorkspace(onOutput: out.id) else { return }
        let top = DesktopTheme.kStatusBarHeight
        let driverW = _workspaceDriverWidth(forOutputWidth: out.logicalWidth)
        let rightLeft = WS.railW + driverW + WS.dividerW

        let driverSize = (w: driverW - WS.paneGap * 2,
                          h: out.logicalHeight - top - WS.paneGap * 2)
        let paneTop = top + WS.tabTop + WS.tabH + WS.paneGap
        let tabSize = (w: out.logicalWidth - rightLeft - WS.paneGap * 2,
                       h: out.logicalHeight - paneTop - WS.paneGap)

        for win in windowManager.windows(inWorkspace: ws.id) {
            let isDriver = win.id == ws.driverWindowId
            let size = isDriver ? driverSize : tabSize
            guard size.w > 1, size.h > 1 else { continue }
            let r = Rect.fromLTWH(0, 0, size.w, size.h)
            guard win.rect.width != r.width || win.rect.height != r.height else { continue }
            win.rect = r
            win.onContentResize?(size.w, size.h)
        }
    }

    // MARK: Escape hatch

    /// The real app id inside a workspace-namespaced one ("ws-3:terminal").
    /// Registry lookups (icon, name) need the base; routing needs the whole.
    func _wsBaseAppId(_ appId: String) -> String {
        guard appId.hasPrefix("ws-"), let c = appId.firstIndex(of: ":")
        else { return appId }
        return String(appId[appId.index(after: c)...])
    }

    /// Move a workspace window out to the desktop. Without this anything
    /// opened in a workspace is trapped there for as long as it runs.
    ///
    /// The window keeps its process and its texture; what changes is
    /// ownership (so the desktop's queries stop filtering it out), its space,
    /// and its size — a pane-sized client dropped on the desktop with the
    /// pane's rect would arrive as a full-height sliver.
    func _wsMoveWindowToDesktop(_ winId: String) {
        guard let win = windowManager.windows.first(where: { $0.id == winId }),
              let wsId = win.ownerAgentId else { return }

        // Give the window back its plain app id when the desktop has no other
        // instance of that app, which restores its dock icon and registry
        // name. When one IS running, the composite key stays: the map is
        // appId -> textureId and keystrokes route through it, so overwriting
        // the entry would steal the desktop copy's keyboard. The window still
        // works either way; it just goes without a dock indicator.
        let base = _wsBaseAppId(win.appId)
        if base != win.appId, processTextureIds[base] == nil {
            if let tex = processTextureIds[win.appId] {
                processTextureIds.removeValue(forKey: win.appId)
                processTextureIds[base] = tex
            }
            win.appId = base
        }

        if let ws = windowManager.workspaces.first(where: { $0.id == wsId }),
           ws.driverWindowId == winId {
            ws.driverWindowId = nil
        }
        if _workspaceActiveTab[wsId] == winId {
            _workspaceActiveTab.removeValue(forKey: wsId)
        }

        win.ownerAgentId = nil
        // The space this output returns to when the workspace toggles off —
        // the desktop the user will actually be looking at. Clamped below the
        // special spaces so the window can never land back on a workspace.
        let lastUser = max(0, windowManager.firstSpecialIndex - 1)
        let idx = min(_workspaceReturnByOutput[_wsBuildOutputId] ?? lastUser,
                      lastUser)
        win.spaceId = windowManager.spaces[max(0, idx)].id

        let rec = AppRegistry.shared.app(id: base)
        let w = min(max(rec?.windowRect?.width ?? 900, 480), screenWidth - 80)
        let h = min(max(rec?.windowRect?.height ?? 620, 360), screenHeight - 120)
        win.rect = Rect.fromLTWH(max(40, (screenWidth - w) / 2),
                                 max(DesktopTheme.kStatusBarHeight + 20,
                                     (screenHeight - h) / 2),
                                 w, h)
        win.onContentResize?(w, h)
        windowManager.onWindowsChanged?()
    }

    // MARK: Hover

    /// Which rail row the pointer is over, tracked as ONE translucent probe
    /// over the whole space rather than a region per row.
    ///
    /// `MouseRegion`'s enter/exit are not the tool here — this shell reads
    /// hover from `Listener.onPointerHover` everywhere it already does it
    /// (the dock's magnification, the divider's cursor), and a per-row region
    /// also gets *leaving* wrong: nothing fires when the pointer exits the
    /// rail sideways into the driver, so the last row stays lit. Deriving the
    /// row from the position makes "no row" fall out for free.
    ///
    /// It only calls setState when the row actually changes, so this is a
    /// rebuild per boundary crossed, not per mouse move.
    private func _workspaceHoverProbe(top: Double) -> Widget {
        return Positioned(fill: (), child: Listener(
            onPointerHover: { [self] e in
                let id = _wsRailRowAt(e.position, top: top)
                guard id != _wsHoverRailId else { return }
                setState { _wsHoverRailId = id }
            },
            behavior: .translucent,
            child: SizedBox(expand: ())))
    }

    private func _wsRailRowAt(_ p: Offset, top: Double) -> String? {
        guard p.dx >= 10, p.dx <= WS.railW - 10 else { return nil }
        var rowY = top + 50
        for ws in windowManager.workspaces {
            if p.dy >= rowY, p.dy < rowY + WS.rowH { return ws.id }
            rowY += WS.rowH + 8
        }
        return nil
    }

    // MARK: Inline rename

    /// Open the rail's inline editor on one row. Shared by the hover pencil
    /// and the context menu's Rename, so the two cannot drift apart.
    func _wsBeginRename(_ wsId: String) {
        _wsRailMenuWsId = nil
        _wsRenamingId = wsId
        _wsRenameBuffer = windowManager.workspaces
            .first(where: { $0.id == wsId })?.name ?? ""
        _wsRenameFresh = true
    }

    /// The pencil that appears on the hovered row. Renaming a workspace was
    /// previously only reachable through right-click > Rename, which is not a
    /// thing anyone finds; this puts it where the pointer already is, and
    /// only on the row being pointed at so the rail stays a plain list.
    private func _wsRenameAffordance(_ wsId: String) -> Widget {
        let fg = shellTheme.overlayText
        return HoverButton(
            builder: { _, states in
                DecoratedBox(
                    decoration: BoxDecoration(
                        color: states.isHovered ? Color(0x33FFFFFF)
                                                : Color(0x14FFFFFF),
                        borderRadius: BorderRadius.all(Radius(circular: 6))),
                    child: Center(child: MacosIcon(
                        icon: CupertinoIcons.pencil,
                        color: fg, size: 12)))
            },
            onPressed: { [self] in setState { _wsBeginRename(wsId) } })
    }

    /// Commit the rail's inline rename: a non-blank name sticks, a blank one
    /// leaves the old one alone. Shared by Enter and by the click-away
    /// catcher below, which have to agree — a name that saves on Enter but
    /// evaporates on a click elsewhere is the kind of thing nobody reports
    /// and everybody notices.
    func _wsCommitRename() {
        guard let renameId = _wsRenamingId else { return }
        let name = _wsRenameBuffer.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty,
           let ws = windowManager.workspaces.first(where: { $0.id == renameId }) {
            ws.name = name
        }
        _wsRenamingId = nil
    }

    /// Click-away catcher for the inline rename. Opening the editor
    /// automatically on `+ New` means the user can now walk away from one
    /// without pressing Enter, and an armed editor swallows every keystroke
    /// (see the key handler) — so the next click anywhere has to end it.
    /// It commits rather than cancels, the way a rename field that loses
    /// focus does.
    private func _workspaceRenameLayer() -> [Widget] {
        guard _wsRenamingId != nil else { return [] }
        return [Positioned(fill: (), child: GestureDetector(
            onTap: { [self] in setState { _wsCommitRename() } },
            onSecondaryTap: { [self] in setState { _wsCommitRename() } },
            behavior: .opaque,
            child: SizedBox(expand: ())))]
    }

    // MARK: Context menus

    /// The open tab / rail menu, plus the click-away catcher under it.
    private func _workspaceMenuLayer(_ w: Double, _ h: Double) -> [Widget] {
        guard _wsTabMenuWinId != nil || _wsRailMenuWsId != nil else { return [] }
        var items: [MacosMenuEntry] = []

        if let winId = _wsTabMenuWinId {
            let isDriver = windowManager.workspaces
                .contains { $0.driverWindowId == winId }
            items = [
                MacosMenuItem(text: "Move to Desktop", onPressed: { [self] in
                    setState {
                        _wsTabMenuWinId = nil
                        _wsMoveWindowToDesktop(winId)
                    }
                }),
                MacosMenuSeparator(),
                MacosMenuItem(
                    text: isDriver ? "Close Driver" : "Close",
                    onPressed: { [self] in
                        setState {
                            _wsTabMenuWinId = nil
                            windowManager.closeWindow(winId)
                        }
                    },
                    isDestructive: true),
            ]
        } else if let wsId = _wsRailMenuWsId {
            let count = windowManager.windows(inWorkspace: wsId).count
            let last = windowManager.workspaces.count <= 1
            items = [
                MacosMenuItem(text: "Rename", onPressed: { [self] in
                    setState { _wsBeginRename(wsId) }
                }),
                MacosMenuSeparator(),
                // Removing the last workspace would leave the space with
                // nothing to show, so it is refused rather than hidden.
                MacosMenuItem(
                    text: count == 0 ? "Remove Workspace"
                                     : "Remove (keeps \(count) open)",
                    onPressed: last ? nil : { [self] in
                        setState {
                            _wsRailMenuWsId = nil
                            // Windows outlive the workspace: they move to the
                            // desktop rather than being destroyed on a click.
                            for win in windowManager.windows(inWorkspace: wsId) {
                                _wsMoveWindowToDesktop(win.id)
                            }
                            windowManager.removeWorkspace(wsId)
                        }
                    },
                    isDestructive: true),
            ]
        }

        let menuW = 210.0
        return [
            Positioned(fill: (), child: GestureDetector(
                onTap: { [self] in
                    setState { _wsTabMenuWinId = nil; _wsRailMenuWsId = nil }
                },
                onSecondaryTap: { [self] in
                    setState { _wsTabMenuWinId = nil; _wsRailMenuWsId = nil }
                },
                behavior: .opaque,
                child: SizedBox(expand: ()))),
            Positioned(
                left: min(_wsMenuAt.dx, max(0, w - menuW - 8)),
                top: min(_wsMenuAt.dy, max(0, h - 90)),
                child: SizedBox(width: menuW, child: MacosMenu(items: items))),
        ]
    }

    // MARK: Launching

    /// Every launch out of the launcher, from the click list and from Enter
    /// alike. One function because the two used to be separate and drifted
    /// immediately: the click path learned about workspaces and Enter did not,
    /// so typing the app's name put it on the desktop instead.
    func _launchFromLauncher(_ appId: String) {
        let driverTarget = _launcherDriverTarget
        setState {
            _launcherOpen = false
            _launcherQuery = ""
            _launcherDriverTarget = nil
        }
        if let wsId = driverTarget {
            _launchIntoWorkspace(workspaceId: wsId, appId: appId, asDriver: true)
        } else if windowManager.activeSpace(onOutput: _launcherOutputId).isWorkspace,
                  let ws = windowManager.selectedWorkspace(onOutput: _launcherOutputId) {
            // Already have a driver and launched something else from in here:
            // it belongs beside it, not on the desktop we cannot see.
            _launchIntoWorkspace(workspaceId: ws.id, appId: appId,
                                 asDriver: ws.driverWindowId == nil)
        } else {
            _launchOrFocusApp(appId)
        }
    }

    /// Put `appId` in the workspace's driver slot.
    ///
    /// First-party apps only for now: they are child processes the shell
    /// starts and composites directly, so the window comes back with a
    /// texture we can put straight into the pane. Third-party apps (VS Code,
    /// Chrome) arrive asynchronously as Wayland clients and need the
    /// launch-chain claim in AgentWindows.swift — worth doing, not needed to
    /// make the layout work.
    func _launchIntoWorkspace(workspaceId: String, appId: String,
                              asDriver: Bool) {
        #if os(Linux)
        guard let ws = windowManager.workspaces.first(where: { $0.id == workspaceId })
        else { return }
        guard let rec = AppRegistry.shared.app(id: appId),
              rec.kind == AppRecord.Kind.firstParty else {
            FileHandle.standardError.write(Data((
                "[workspace] \(appId) is not a first-party app — "
                + "only those can drive a workspace today\n").utf8))
            return
        }
        guard let mgr = linuxProcessAppManager else { return }

        // Sized for the output DISPLAYING this workspace (per-output rail
        // selection), not the primary: a driver launched into a workspace
        // living on a 2560x1600 panel must not come up sized for a 1920x1080
        // one. A workspace nothing displays sizes for the launcher's output.
        let wsOutId = windowManager.selectedWorkspaceIdByOutput
            .first(where: { $0.value == workspaceId })?.key ?? _launcherOutputId
        let wsOut = displayLayout?.outputs.first(where: { $0.id == wsOutId })
            ?? displayLayout?.host
            ?? DisplayOutput(id: 0, name: "primary",
                             physicalWidth: Int(screenWidth * currentShellDpi),
                             physicalHeight: Int(screenHeight * currentShellDpi),
                             scale: currentShellDpi, originX: 0, originY: 0,
                             isHost: true, isPrimary: true, refreshMhz: 60000)
        let paneW = _workspaceDriverWidth(forOutputWidth: wsOut.logicalWidth) - 20
        let paneH = wsOut.logicalHeight - DesktopTheme.kStatusBarHeight - 20
        let title = rec.name
        // Namespaced per workspace.
        // Two things depend on it: keystrokes are routed by looking the
        // window's appId up in processTextureIds, so a workspace copy must
        // not share a key with the desktop copy of the same app; and a
        // composite id deliberately fails to resolve in the registry, which
        // is what keeps this window from lighting the dock.
        let paneAppId = "\(workspaceId):\(appId)"
        _ = mgr.launchDmaBufApp(
            executableName: rec.exec,
            contentWidth: Int(paneW),
            contentHeight: Int(paneH),
            onReady: { [self] (texId: Int64) in
                mgr.onFirstFrame(textureId: texId) { [self] in
                    setState {
                        processTextureIds[paneAppId] = texId
                        let winId = windowManager.addWindow(
                            title: title,
                            appId: paneAppId,
                            rect: Rect.fromLTWH(0, 0, paneW, paneH),
                            textureId: Int(texId),
                            onWindowClose: { mgr.destroyApp(textureId: texId) },
                            onPointerEvent: { (phase, x, y, buttons) in
                                mgr.sendPointerEvent(textureId: texId, phase: phase,
                                                     x: x, y: y, buttons: buttons)
                            },
                            onContentResize: { (w, h) in
                                mgr.sendResize(textureId: texId,
                                               width: Int(w), height: Int(h))
                            },
                            onScrollEvent: { (x, y, dx, dy) in
                                mgr.sendScrollEvent(textureId: texId,
                                                    x: x, y: y, dx: dx, dy: dy)
                            },
                            ownerAgentId: workspaceId,
                            appBuilder: { _ in SizedBox(expand: ()) })
                        if asDriver {
                            ws.driverWindowId = winId
                        } else {
                            // Show it straight away: opening something and
                            // having to hunt for its tab is not the point.
                            _workspaceActiveTab[workspaceId] = winId
                        }
                        windowManager.focusedWindowId = winId
                    }
                }
            },
            onTerminated: { [self] in
                // The workspace outlives its driver: drop the window and let
                // the middle column fall back to its empty state, leaving
                // everything else in this workspace untouched.
                setState {
                    processTextureIds.removeValue(forKey: paneAppId)
                    // Find the window by its own app id rather than assuming
                    // it is still the driver — by now it may be a tab, or the
                    // driver slot may hold something else entirely.
                    if let win = windowManager.windows.first(where: {
                        $0.appId == paneAppId && $0.ownerAgentId == workspaceId
                    }) {
                        windowManager.windows.removeAll { $0.id == win.id }
                        if windowManager.focusedWindowId == win.id {
                            windowManager.focusedWindowId = nil
                        }
                        if ws.driverWindowId == win.id { ws.driverWindowId = nil }
                        if _workspaceActiveTab[workspaceId] == win.id {
                            _workspaceActiveTab.removeValue(forKey: workspaceId)
                        }
                    }
                }
            })
        #endif
    }

    // MARK: Controls

    private func _workspaceButton(_ label: String, fontSize: Double = 12,
                                  onTap: @escaping () -> Void) -> Widget {
        GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Color(0x1FFFFFFF),
                    border: Border.all(color: Color(0x33FFFFFF), width: 1),
                    borderRadius: BorderRadius.all(Radius(circular: 7))),
                child: Center(child: Text(label, style: TextStyle(
                    color: shellTheme.overlayText,
                    fontSize: fontSize, fontWeight: .w600)))))
    }
}
