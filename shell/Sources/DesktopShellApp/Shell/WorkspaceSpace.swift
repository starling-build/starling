// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

//
// Workspace mode: the agent you are talking to on the left, and everything it
// opened on the right as tabs.
//
// TWO columns, and one workspace. The rail of workspaces this used to lead
// with is gone: on a 1280x800 laptop panel it spent a fifth of the width on a
// list that was almost always one row long, and the thing worth seeing —
// what the agent is doing — was left with a third of the screen. So the
// workspace is the mode rather than a place you keep, the left column is
// hideable when the agent's windows want the whole panel, and an agent
// nobody launched from here has its windows drawn in this one rather than in
// a row of its own (`_wsVisibleWindows`) — with no rail, that is the only
// place they would be drawn at all.
//
// The left column is nil-able on purpose — when the driver quits, the
// workspace and its other windows survive and it returns to its empty state.
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
    /// Width of the left edge left behind when the driver column is hidden:
    /// enough for the chip that brings it back, and nothing else.
    static let collapsedW: Double = 36
    static let driverMin: Double = 380
    static let driverMax: Double = 1100
    static let dividerW: Double = 8
    static let pad: Double = 14
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
        _applyAgentWindowThrottle()
        var layers: [Widget] = []
        let top = DesktopTheme.kStatusBarHeight

        // Dim scrim, so the space reads as its own mode rather than a desktop
        // that happens to have windows arranged on it. Near-opaque on purpose:
        // at half alpha the wallpaper read straight through the columns and
        // the mode looked like two empty outlines floating on the desktop.
        // The wallpaper survives as a tint, not as a picture.
        layers.append(Positioned(fill: (), child: ColoredBox(
            color: Color(0xF20E0F15), child: SizedBox(expand: ()))))

        guard let ws = windowManager.selectedWorkspace(onOutput: output.id) else {
            return Stack(children: layers)
        }

        // Hidden driver: a slim strip holds the chip that brings it back, and
        // the agent's windows take everything else. The driver window is not
        // drawn at all while hidden — it keeps running, and keeps the size it
        // had, so showing it again costs no reconfigure.
        if _wsDriverHidden {
            layers.append(contentsOf: _wsRevealStrip(ws, top: top, h: h))
            layers.append(contentsOf: _workspaceTabColumn(
                ws, left: WS.collapsedW, width: w - WS.collapsedW,
                top: top, h: h))
        } else {
            let driverW = _workspaceDriverWidth(forOutputWidth: w)
            let rightLeft = driverW + WS.dividerW

            layers.append(contentsOf: _workspaceDriverColumn(
                ws, left: 0, width: driverW, top: top, h: h))
            layers.append(contentsOf: _workspaceDivider(
                left: driverW, top: top, h: h))
            layers.append(contentsOf: _workspaceTabColumn(
                ws, left: rightLeft, width: w - rightLeft, top: top, h: h))
        }
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
                               w - WS.dividerW - WS.minTabColumnW)
        return min(min(WS.driverMax, maxForOutput), max(WS.driverMin, _workspaceDriverW))
    }

    /// What the tab column shows: this workspace's windows, plus the windows
    /// of any agent no workspace has claimed.
    ///
    /// The rail used to give such an agent a row of its own. With the rail
    /// gone this is where they are drawn instead, and it is not a cosmetic
    /// choice: an agent window drawn nowhere is exactly the state the whole
    /// take-over property exists to prevent. Ownership is untouched — they
    /// stay the agent's, so the pane still fits rather than resizes them and
    /// touching one is still a take-over.
    func _wsVisibleWindows(_ ws: WorkspaceInfo) -> [WindowInfo] {
        let own = windowManager.windows(inWorkspace: ws.id)
        let ownIds = Set(own.map(\.id))
        return own + windowManager.windows.filter {
            !ownIds.contains($0.id) && _isAgentOwned($0)
        }
    }

    // MARK: Left column chrome

    /// The one control the left column has: what is in it, and a chip that
    /// folds it away when the agent's windows want the whole panel.
    ///
    /// It also carries the workspace menu on right-click. That used to live
    /// on the rail row, and something has to keep it: "stop everything in
    /// here" is the only way to end a run without hunting each window down.
    private func _wsDriverStrip(_ ws: WorkspaceInfo, left: Double,
                                width: Double, top: Double) -> [Widget] {
        let win = _workspaceDriverWindow(ws)
        let wsId = ws.id
        let anchor = Offset(left + WS.paneGap, top + WS.tabTop + WS.tabH + 4)
        var row: [Widget] = []
        if let win {
            row.append(SizedBox(width: 13, height: 13, child: CustomPaint(
                painter: IconPainter(
                    _iconType(for: _wsBaseAppId(win.appId)),
                    color: shellTheme.overlayText))))
            row.append(SizedBox(width: 6))
        }
        row.append(Text(
            win.map { String($0.title.prefix(24)) } ?? "Workspace",
            style: TextStyle(color: shellTheme.overlayText,
                             fontSize: 11, fontWeight: .w600)))
        row.append(SizedBox(width: 8))
        row.append(Text("‹", style: TextStyle(
            color: shellTheme.overlayTextDim, fontSize: 13, fontWeight: .w600)))

        return [Positioned(
            left: left + WS.paneGap, top: top + WS.tabTop,
            width: min(WS.tabWMax, max(0, width - WS.paneGap * 2)),
            height: WS.tabH,
            child: GestureDetector(
                onTap: { [self] in setState { _wsDriverHidden = true } },
                onSecondaryTap: { [self] in
                    setState {
                        _wsTabMenuWinId = nil
                        _wsDriverMenuWsId = wsId
                        _wsMenuAt = anchor
                    }
                },
                behavior: .opaque,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x14FFFFFF),
                        border: Border.all(color: Color(0x1FFFFFFF), width: 1),
                        borderRadius: BorderRadius.all(Radius(circular: 6))),
                    child: Center(child: Row(
                        mainAxisAlignment: .center, children: row)))))]
    }

    /// What is left of the column while it is hidden: a strip the width of
    /// its own chip. Deliberately not zero — a panel that can only be brought
    /// back by a keystroke nobody was told about is a panel that is gone.
    private func _wsRevealStrip(_ ws: WorkspaceInfo, top: Double,
                                h: Double) -> [Widget] {
        [
            Positioned(
                left: 0, top: top, width: WS.collapsedW, height: h - top,
                child: IgnorePointer(child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0xE60F1118),
                        border: Border(
                            right: BorderSide(color: Color(0x26FFFFFF), width: 1))),
                    child: SizedBox(expand: ())))),
            Positioned(
                left: 6, top: top + WS.tabTop, width: 24, height: WS.tabH,
                child: _workspaceButton("›", fontSize: 14) { [self] in
                    setState { _wsDriverHidden = false }
                }),
        ]
    }

    // MARK: Driver column

    private func _workspaceDriverColumn(
        _ ws: WorkspaceInfo, left: Double, width: Double, top: Double, h outputH: Double
    ) -> [Widget] {
        // The pane starts where the tab column's does, so the two columns
        // line up and the strip above each one reads as the same row.
        var out: [Widget] = _wsDriverStrip(ws, left: left, width: width, top: top)
        let paneTop = top + WS.tabTop + WS.tabH + WS.paneGap
        let h = outputH - paneTop - WS.paneGap

        guard let driverId = ws.driverWindowId,
              let win = windowManager.windows.first(where: { $0.id == driverId }) else {
            // Empty state. A new workspace leads with the AGENTS it can run,
            // because that is the thing a workspace is for now — an agent
            // with what it opens beside it — and "choose an app" buries the
            // one answer most people want under a search box. Any other app
            // is still one click further down.
            //
            // The list comes from the registry (`Agent=1`), never from a
            // table here: a second agent app must be one file in catalog.d
            // and nothing else.
            let wsId = ws.id
            let agents = AppRegistry.shared.apps
                .filter { $0.agentApp && $0.installed }
                .sorted { $0.order < $1.order }
            var rows: [Widget] = [
                Text("Run an agent here", style: TextStyle(
                    color: shellTheme.overlayText,
                    fontSize: 15, fontWeight: .w600)),
                SizedBox(height: 4),
                Text("It works in this workspace, and what it opens "
                     + "appears beside it.", style: TextStyle(
                    color: shellTheme.overlayTextDim,
                    fontSize: 12, fontWeight: .w400)),
                SizedBox(height: 14),
            ]
            for rec in agents {
                let appId = rec.id
                rows.append(SizedBox(
                    width: 260, height: 40,
                    child: _workspaceButton(rec.name, fontSize: 13) { [self] in
                        _launchIntoWorkspace(workspaceId: wsId, appId: appId,
                                             asDriver: true)
                    }))
                rows.append(SizedBox(height: 8))
            }
            if agents.isEmpty {
                rows.append(Text("No agent app is installed — the App Store "
                                 + "has them.", style: TextStyle(
                    color: shellTheme.overlayTextDim,
                    fontSize: 12, fontWeight: .w400)))
                rows.append(SizedBox(height: 8))
            }
            rows.append(SizedBox(
                width: 260, height: 34,
                child: _workspaceButton("Choose any app…", fontSize: 12) {
                    [self] in openLauncher(driverTarget: wsId)
                }))
            out.append(Positioned(
                left: left + WS.paneGap, top: paneTop,
                width: width - WS.paneGap * 2, height: h,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: Color(0x14FFFFFF),
                        border: Border.all(color: Color(0x2EFFFFFF), width: 1),
                        borderRadius: BorderRadius.all(Radius(circular: 10))),
                    child: Center(child: Column(
                        mainAxisAlignment: .center, children: rows)))))
            return out
        }

        let focused = windowManager.focusedWindowId == win.id
        out.append(Positioned(
            key: ValueKey("ws-driver-\(win.id)"),
            left: left + WS.paneGap, top: paneTop,
            width: width - WS.paneGap * 2, height: h,
            child: _workspacePane(win, focused: focused,
                                  paneW: width - WS.paneGap * 2, paneH: h)))
        return out
    }

    // MARK: Tab column

    private func _workspaceTabColumn(
        _ ws: WorkspaceInfo, left: Double, width: Double, top: Double, h: Double
    ) -> [Widget] {
        var out: [Widget] = []
        // The driver is shown in its own column, never as a tab.
        let tabs = _wsVisibleWindows(ws)
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
                            _wsDriverMenuWsId = nil
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
                active, focused: windowManager.focusedWindowId == active.id,
                paneW: width - WS.paneGap * 2,
                paneH: h - paneTop - WS.paneGap)))
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
                    let w = event.position.dx - WS.dividerW / 2
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

    // MARK: Take-over

    /// True when this window belongs to a broker agent rather than to a
    /// workspace the human made. Both ride `ownerAgentId`, so the rail entry
    /// is what tells them apart.
    func _isAgentOwned(_ win: WindowInfo) -> Bool {
        guard let owner = win.ownerAgentId else { return false }
        return windowManager.workspaces.first(where: { $0.id == owner })?.isAgent
            ?? false
    }

    /// True when the pane must FIT this window rather than be filled by it.
    ///
    /// The distinction is the agent's own windows versus the app DRIVING it.
    /// An agent's window is never resized — its size is the coordinate space
    /// it is mid-task in. The driver is Claude Desktop, the human's own app,
    /// which is resized to its pane like any other workspace window and is
    /// not working from screenshot coordinates. It is also not something to
    /// take over: it was never the agent's.
    func _isFittedAgentWindow(_ win: WindowInfo) -> Bool {
        guard let owner = win.ownerAgentId else { return false }
        return windowManager.agents.contains { $0.id == owner }
    }

    /// The process that opened a window, for pairing an agent with the app
    /// that spawned it.
    ///
    /// Both window kinds, and the second one is not hypothetical: a Terminal
    /// running Claude Code is a first-party CHILD, which has no Wayland
    /// surface at all — so a surface-pid-only lookup finds nothing and the
    /// agent never binds to the workspace that Terminal is driving.
    func _windowPid(_ win: WindowInfo) -> pid_t? {
        if let wayland = waylandIntegration,
           let sid = wayland.surfaceId(forWindowId: win.id),
           let pid = wayland.clientPid(surfaceId: sid) {
            return pid
        }
        guard let tex = win.textureId else { return nil }
        return linuxProcessAppManager?.childPid(textureId: Int64(tex))
    }

    /// `/proc/<pid>/stat` field 4. nil at the top of the tree.
    ///
    /// The comm field is parenthesised AND may itself contain spaces or
    /// brackets, so the parse starts from the LAST ')' rather than splitting
    /// the whole line — a process called "claude (beta)" would otherwise
    /// shift every field after it.
    static func _parentPid(_ pid: pid_t) -> pid_t? {
        guard let s = try? String(contentsOfFile: "/proc/\(pid)/stat",
                                  encoding: .utf8),
              let close = s.lastIndex(of: ")"),
              s.index(close, offsetBy: 2, limitedBy: s.endIndex) != nil
        else { return nil }
        let rest = s[s.index(close, offsetBy: 2)...].split(separator: " ")
        guard rest.count > 1, let ppid = pid_t(rest[1]), ppid > 1 else { return nil }
        return ppid
    }

    /// The workspace's driver window, if it is still alive. `driverWindowId`
    /// alone is not enough: nothing clears it when the driver's window simply
    /// closes (only the explicit move-to-desktop does), so a dead id would
    /// hold the three-column layout open around an empty middle.
    func _workspaceDriverWindow(_ ws: WorkspaceInfo) -> WindowInfo? {
        guard let id = ws.driverWindowId else { return nil }
        return windowManager.windows.first(where: { $0.id == id })
    }

    /// Bind a newly connected broker agent to the workspace whose DRIVER
    /// spawned it, so what it opens appears beside the app driving it rather
    /// than in a rail entry of its own.
    ///
    /// The link is process ancestry, the only honest one available: an MCP
    /// server is a child of the app that launched it, and Claude Desktop's is
    /// a DIRECT child of the Electron main process — the same process holding
    /// the Wayland connection for its window. Nothing is matched on names.
    ///
    /// Returns true when a workspace claimed the agent. False means nobody
    /// launched it from one — agent-client.py from a terminal, a CI harness —
    /// and the caller falls back to giving it a rail entry of its own, so its
    /// windows are still watchable somewhere.
    /// Who owns the window belonging to `pid`, or to its nearest ancestor.
    ///
    /// Used to decide whose file dialog a portal request is. Chrome may make
    /// the D-Bus call from a child of the process holding the Wayland
    /// connection, which is why this walks UP rather than demanding an exact
    /// match. nil means the human's own app asked, and the dialog belongs
    /// where it always has: on their desktop.
    func _ownerForRequestingProcess(_ pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var here: pid_t? = pid
        for _ in 0..<8 {
            guard let cur = here else { return nil }
            if let win = windowManager.windows.first(where: { _windowPid($0) == cur }) {
                return win.ownerAgentId
            }
            here = Self._parentPid(cur)
        }
        return nil
    }

    /// Try the bind again from the agent's recorded pid — see
    /// `onAgentNeedsWorkspace` for why once is not enough.
    func _retryBindAgent(_ agentId: String) -> Bool {
        guard let agent = windowManager.agents.first(where: { $0.id == agentId })
        else { return false }
        return _bindAgentToWorkspace(agentId: agentId, pid: agent.clientPid)
    }

    @discardableResult
    func _bindAgentToWorkspace(agentId: String, pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        // Up the process tree from the broker client. One hop for Claude
        // Desktop; the bound guards against a /proc cycle, not a real depth —
        // nothing legitimate is eight processes deep from its own app.
        var here: pid_t? = pid
        for _ in 0..<8 {
            guard let cur = here else { return false }
            if let win = windowManager.windows.first(where: { _windowPid($0) == cur }),
               let owner = win.ownerAgentId,
               let ws = windowManager.workspaces.first(where: {
                   $0.id == owner && $0.driverWindowId == win.id
               }) {
                setState { ws.agentId = agentId }
                return true
            }
            here = Self._parentPid(cur)
        }
        return false
    }

    /// Any window the human currently holds.
    var _heldWindows: [WindowInfo] {
        windowManager.windows.filter { $0.humanHoldsControl }
    }

    /// Frame-throttle every agent window by whether anyone is looking at it.
    ///
    /// Broker windows are pinned to 200ms at birth because nothing draws
    /// them, and until now nothing ever revisited that: the fleet build the
    /// old comment refers to went with the AI Space. Left alone, the first
    /// agent window shown in the rail would animate at 5fps, and "watching
    /// the agent work" would look like the agent hanging.
    ///
    /// Diff-guarded — `setSurfaceThrottle` is a round trip to the server's
    /// loop thread, and this runs on every workspace build. First-party
    /// children have no surface id and were never throttled; they fall out
    /// through the lookup rather than needing a case.
    func _applyAgentWindowThrottle() {
        guard let wayland = waylandIntegration else { return }
        let outputs = displayLayout?.outputs.map(\.id) ?? [0]
        // One workspace, and it draws every agent's windows — so "is anyone
        // looking" is now the whole question. It used to be per rail row.
        let watching = outputs.contains {
            windowManager.activeSpace(onOutput: $0).isWorkspace
        }
        // EVERY owned window, not just the agent's. The driver is claimed
        // through the same launch path, so it is born at 200ms too — and
        // nothing ever lifted that, because this loop asked for an AGENT's
        // window. Claude Desktop therefore ran the whole session at 5fps in
        // the column the human types into, which reads as the app being slow
        // rather than as the shell throttling it.
        for win in windowManager.windows {
            guard win.ownerAgentId != nil else { continue }
            let want: UInt32 = watching ? 0 : 200
            guard _agentThrottleApplied[win.id] != want else { continue }
            guard let sid = wayland.surfaceId(forWindowId: win.id) else { continue }
            wayland.setSurfaceThrottle(surfaceId: sid, intervalMs: want)
            _agentThrottleApplied[win.id] = want
        }
    }

    /// Touching an agent's window takes it, until Esc.
    ///
    /// There is no confirmation and no modifier on purpose: the moment the
    /// human reaches for a window is the moment they need it, and a
    /// take-over that has to be armed first is one they will not reach for
    /// while something is going wrong.
    func _takeOverIfAgentWindow(_ win: WindowInfo) {
        guard _isFittedAgentWindow(win), !win.humanHoldsControl else { return }
        setState { win.humanHoldsControl = true }
    }

    /// Esc gives every held window back. Returns true when it consumed the
    /// key, so the caller can stop there.
    @discardableResult
    func _releaseTakenOverWindows() -> Bool {
        let held = _heldWindows
        guard !held.isEmpty else { return false }
        setState { for win in held { win.humanHoldsControl = false } }
        return true
    }

    // MARK: Panes

    /// A live window rendered into a pane: texture, Y-flip where the client
    /// needs it, and pointer/scroll forwarded in the window's own coordinates.
    private func _workspacePane(_ win: WindowInfo, focused: Bool,
                                paneW: Double, paneH: Double) -> Widget {
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

        // A WORKSPACE window is resized to its pane, so its texture fills the
        // pane exactly and a pointer position is already in the window's
        // coordinates — that is what the old comment here meant by "no scale
        // factor to undo".
        //
        // An AGENT's window is deliberately not resized: its size IS the
        // coordinate space it is mid-task in, and moving it would invalidate
        // the screenshot the agent is about to click into. So it is fitted
        // into the pane instead, letter-boxed, and every coordinate the
        // pointer reports has to have that fit divided back out. Get this
        // wrong and the picture still looks perfect while every click lands
        // somewhere else — which is the failure mode worth naming, because
        // nothing about it looks like a bug.
        //
        // The content size is spelled the way the BROKER spells it
        // (`rect.height - kTitleBarHeight`, AgentBroker's `capture`) rather
        // than derived some other way, so the human's view and the agent's
        // coordinate space cannot drift apart. Take-over depends on the two
        // agreeing.
        var scale = 1.0
        var offX = 0.0
        var offY = 0.0
        if _isFittedAgentWindow(win), paneW > 1, paneH > 1 {
            let cw = max(1.0, win.rect.width)
            let ch = max(1.0, win.rect.height - DesktopTheme.kTitleBarHeight)
            scale = min(paneW / cw, paneH / ch)
            offX = (paneW - cw * scale) / 2
            offY = (paneH - ch * scale) / 2
            content = Stack(children: [
                Positioned(left: offX, top: offY,
                           width: cw * scale, height: ch * scale,
                           child: content),
            ])
        }
        let toWinX: (Double) -> Double = { ($0 - offX) / scale }
        let toWinY: (Double) -> Double = { ($0 - offY) / scale }

        let forwarded: Widget = Listener(
            onPointerDown: { [self] event in
                if windowManager.focusedWindowId != winId {
                    setState { windowManager.focusedWindowId = winId }
                }
                // Touching an agent's window takes it from the agent until
                // Esc. Claiming it on the way DOWN rather than on the click
                // matters: the press itself must already be the human's, or
                // the agent could be mid-drag in the same window.
                _takeOverIfAgentWindow(win)
                win.onPointerEvent?(2, toWinX(event.localPosition.dx),
                                    toWinY(event.localPosition.dy),
                                    Int64(event.buttons))
            },
            onPointerMove: { event in
                win.onPointerEvent?(3, toWinX(event.localPosition.dx),
                                    toWinY(event.localPosition.dy),
                                    Int64(event.buttons))
            },
            onPointerUp: { event in
                win.onPointerEvent?(1, toWinX(event.localPosition.dx),
                                    toWinY(event.localPosition.dy), 0)
            },
            onPointerHover: { event in
                DesktopCursor.setShape(.default)
                win.onPointerEvent?(6, toWinX(event.localPosition.dx),
                                    toWinY(event.localPosition.dy), 0)
            },
            onPointerSignal: { event in
                if let scroll = event as? PointerScrollEvent {
                    win.onScrollEvent?(toWinX(scroll.localPosition.dx),
                                       toWinY(scroll.localPosition.dy),
                                       scroll.scrollDelta.dx, scroll.scrollDelta.dy)
                }
            },
            behavior: .opaque,
            child: content)
        // Held windows say so, and say how to give it back. Without this the
        // agent simply stops doing anything on that window and there is
        // nothing on screen to connect that to the click that caused it —
        // "the agent froze" is what a silent take-over looks like.
        var pane: Widget = DecoratedBox(
            decoration: BoxDecoration(
                border: Border.all(
                    color: win.humanHoldsControl ? Color(0xFFE0A030)
                        : (focused ? shellTheme.accent : Color(0x40FFFFFF)),
                    width: win.humanHoldsControl || focused ? 2 : 1),
                borderRadius: BorderRadius.all(Radius(circular: 6))),
            child: ClipRRect(
                borderRadius: BorderRadius.all(Radius(circular: 6)),
                child: forwarded))
        if win.humanHoldsControl {
            pane = Stack(children: [
                Positioned(fill: (), child: pane),
                // Along the BOTTOM edge, not the top: centred at the top it
                // sat squarely on the heading of whatever the agent had open
                // (Settings' "General", in the first run of this). The
                // bottom of a window is usually the emptiest part of it.
                //
                // Spans the full width and aligns inside it: a Positioned
                // anchored by one edge with no width lays out correctly and
                // hit-tests as nothing, and IgnorePointer would hide that.
                Positioned(
                    left: 0, right: 0, bottom: 10, height: 24,
                    child: IgnorePointer(child: Row(
                        mainAxisAlignment: .center,
                        children: [
                            DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Color(0xE6E0A030),
                                    borderRadius: BorderRadius.all(
                                        Radius(circular: 12))),
                                child: Padding(
                                    padding: EdgeInsets(
                                        horizontal: 10, vertical: 4),
                                    child: Text(
                                        "You have this window — Esc to give it back",
                                        style: TextStyle(
                                            color: Color(0xFF201400),
                                            fontSize: 11.5,
                                            fontWeight: .w600)))),
                        ]))),
            ])
        }
        return pane
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
        let rightLeft = _wsDriverHidden ? WS.collapsedW : driverW + WS.dividerW
        let paneTop = top + WS.tabTop + WS.tabH + WS.paneGap

        let driverSize = (w: driverW - WS.paneGap * 2,
                          h: out.logicalHeight - paneTop - WS.paneGap)
        let tabSize = (w: out.logicalWidth - rightLeft - WS.paneGap * 2,
                       h: out.logicalHeight - paneTop - WS.paneGap)

        for win in windowManager.windows(inWorkspace: ws.id) {
            let isDriver = win.id == ws.driverWindowId
            // An AGENT's own windows are not resized to their pane — only the
            // driver is. The size a broker window has is the coordinate space
            // the agent is working in: it screenshots, computes a click from
            // those pixels, and clicks. Resize it between those two steps and
            // the click lands somewhere else, for no reason the agent can
            // see. `_workspacePane` fits those into the pane instead. The
            // driver is the human's own app and is resized like any other
            // workspace window.
            if _isFittedAgentWindow(win) { continue }
            // Hidden, the driver is not on screen: leave it the size it had,
            // so folding the column away and back costs no reconfigure.
            if isDriver && _wsDriverHidden { continue }
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

    /// Delete a workspace outright: stop everything in it, then drop the row.
    ///
    /// The driver goes first — stopping it is the point, and apps it spawned
    /// are supposed to die with it — but nothing here trusts that cascade:
    /// a driver's descendants can outlive it (see the workspace-mode notes),
    /// so every remaining window is closed explicitly too. They are all
    /// owned by the workspace, so the sweep catches what the driver opened
    /// and what the + button did alike. `closeWindow` already speaks each
    /// kind's language: destroyApp for a first-party child process, the xdg
    /// close for a Wayland client.
    func _wsDeleteWorkspace(_ wsId: String) {
        // Ask, then insist — collected BEFORE the close, because the windows
        // are gone by the time anyone could look. A Wayland client is asked to
        // go through xdg_toplevel.close, and an Electron app may honour that
        // by hiding and staying resident: Claude Desktop does exactly that, so
        // "Stop Everything" left an empty workspace and a live process still
        // holding the session, its MCP server and half a gigabyte — and
        // launching it again did nothing visible, because the second instance
        // just handed off to the first. Anything still alive after the grace
        // period gets a TERM.
        let survivors: [pid_t] = windowManager.windows(inWorkspace: wsId)
            .compactMap { _windowPid($0) }
            .filter { $0 > 1 }

        var ids = windowManager.windows(inWorkspace: wsId).map(\.id)
        if let driverId = windowManager.workspaces
            .first(where: { $0.id == wsId })?.driverWindowId,
           let at = ids.firstIndex(of: driverId) {
            ids.remove(at: at)
            ids.insert(driverId, at: 0)
        }
        for id in ids { windowManager.closeWindow(id) }
        _workspaceActiveTab.removeValue(forKey: wsId)
        // There is one workspace, and "stop all of this" must not end with
        // an empty mode — so a fresh one replaces the emptied one. Order
        // matters: add, then remove, so removeWorkspace's count guard (it
        // refuses to remove the last) is satisfied.
        if windowManager.workspaces.count <= 1 {
            windowManager.addWorkspace(onOutput: _wsBuildOutputId)
        }
        windowManager.removeWorkspace(wsId)

        guard !survivors.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4)) {
            for pid in survivors where kill(pid, 0) == 0 {
                kill(pid, SIGTERM)
            }
        }
    }

    // MARK: Hover

    /// Cursor catch-all for the whole mode.
    ///
    /// The desktop's lives on the wallpaper, which the scrim buries — so
    /// without this, crossing the divider once leaves its resize arrows stuck
    /// to the whole mode. Order keeps the divider working: the probe is
    /// topmost, so its entry runs FIRST in the hit-test path and anything
    /// below (divider, panes) overwrites the shape within the same event.
    ///
    /// Translucent, so every click still lands on whatever is under it. It
    /// tracked the hovered rail row too, until there were no rows.
    private func _workspaceHoverProbe(top: Double) -> Widget {
        return Positioned(fill: (), child: Listener(
            onPointerHover: { _ in DesktopCursor.setShape(.default) },
            behavior: .translucent,
            child: SizedBox(expand: ())))
    }

    // MARK: Context menus

    /// The open tab / left-column menu, plus the click-away catcher under it.
    private func _workspaceMenuLayer(_ w: Double, _ h: Double) -> [Widget] {
        guard _wsTabMenuWinId != nil || _wsDriverMenuWsId != nil else { return [] }
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
        } else if let wsId = _wsDriverMenuWsId,
                  let ws = windowManager.workspaces.first(where: { $0.id == wsId }) {
            let count = _wsVisibleWindows(ws).count
            let driver = _workspaceDriverWindow(ws)
            items = [
                MacosMenuItem(text: "Hide This Column", onPressed: { [self] in
                    setState { _wsDriverMenuWsId = nil; _wsDriverHidden = true }
                }),
                MacosMenuSeparator(),
                // Rename and Remove went with the rail: with one workspace, a
                // name nothing displays is a name nobody needs, and Remove was
                // refused on the last row anyway. Stop is the item that had to
                // survive — it is the only way to end a run without hunting
                // every window down.
                MacosMenuItem(
                    text: driver.map { "Close \($0.title.prefix(18))" }
                        ?? "Close Driver",
                    onPressed: driver.map { win in { [self] in
                        setState {
                            _wsDriverMenuWsId = nil
                            windowManager.closeWindow(win.id)
                        }
                    } },
                    isDestructive: true),
                MacosMenuItem(
                    text: count == 0 ? "Stop Everything"
                                     : "Stop Everything (closes \(count))",
                    onPressed: { [self] in
                        setState {
                            _wsDriverMenuWsId = nil
                            _wsDeleteWorkspace(wsId)
                        }
                    },
                    isDestructive: true),
            ]
        }

        let menuW = 210.0
        return [
            Positioned(fill: (), child: GestureDetector(
                onTap: { [self] in
                    setState { _wsTabMenuWinId = nil; _wsDriverMenuWsId = nil }
                },
                onSecondaryTap: { [self] in
                    setState { _wsTabMenuWinId = nil; _wsDriverMenuWsId = nil }
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
                                 asDriver: _workspaceDriverWindow(ws) == nil)
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
        guard let rec = AppRegistry.shared.app(id: appId) else { return }

        // A HOST app (Claude Desktop, Chrome) arrives asynchronously as a
        // Wayland client, so it cannot be composited into a pane the way a
        // first-party child can. The launch-chain claim closes that gap and
        // already exists for the broker: arm the next toplevel from this
        // client for an owner id, and every later window from the same client
        // follows. Ownership ids are opaque, so a WORKSPACE id works there
        // exactly as an agent id does — which is what lets a workspace run
        // Claude Desktop as its driver at all.
        if rec.kind == .host {
            let started = _launchAgentHostApp(
                agentId: ws.id, recipe: rec.exec,
                discreteGpu: rec.discreteGpu,
                onWindow: { [weak self] winId in
                    guard let self else { return }
                    self.setState {
                        // Aliveness, not just nil-ness: an id left behind by a
                        // driver that has quit must not out-vote the window
                        // this launch just produced.
                        if asDriver, self._workspaceDriverWindow(ws) == nil {
                            ws.driverWindowId = winId
                        }
                    }
                })
            if !started {
                FileHandle.standardError.write(Data((
                    "[workspace] \(appId) could not be launched\n").utf8))
            }
            return
        }
        guard rec.kind == AppRecord.Kind.firstParty else {
            FileHandle.standardError.write(Data((
                "[workspace] \(appId) is neither first-party nor a host app — "
                + "android and x11 records cannot drive a workspace\n").utf8))
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
        // Namespaced per workspace AND per launch.
        // Two things depend on the composite: keystrokes are routed by looking
        // the window's appId up in processTextureIds, so a workspace copy must
        // not share a key with the desktop copy of the same app; and a
        // composite id deliberately fails to resolve in the registry, which
        // is what keeps this window from lighting the dock.
        //
        // The serial is the part that took a driver terminal with it. Keyed on
        // the workspace alone, a SECOND copy of the same app in one workspace
        // is indistinguishable from the first: `processTextureIds[paneAppId] =
        // texId` below overwrites the first copy's entry, so its keystrokes
        // start going to the newcomer, and `onTerminated` — which finds its
        // window with `windows.first(where: appId == paneAppId)` — matches the
        // OLDEST copy instead. Closing a second terminal in a workspace whose
        // driver was also a terminal therefore deleted the DRIVER's window
        // while leaving its process running with a dead texture: an empty
        // driver pane and an unreachable shell. The serial goes in the prefix,
        // before the ':', because `_wsBaseAppId` takes everything after the
        // first colon as the real app id — a suffix would break the icon and
        // registry lookups instead.
        _wsPaneSerial += 1
        let paneAppId = "\(workspaceId)/\(_wsPaneSerial):\(appId)"
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
