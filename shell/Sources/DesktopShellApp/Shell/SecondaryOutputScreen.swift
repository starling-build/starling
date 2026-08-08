// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Cross-tree shared state

/// The wallpaper GL texture, shared with secondary-output widget trees.
/// GL textures are engine-global; set by DesktopShell._loadWallpaperTexture.
nonisolated(unsafe) var sharedWallpaperTextureId: Int64 = -1

/// Flutter view id → DisplayOutput.id, for secondary outputs. Written on the
/// main thread at startup and on the ENGINE PLATFORM thread at hotplug (views
/// must be added there), so access is lock-guarded. Read by the multi-view
/// content builder and the shell.
final class SecondaryViewOutputsMap: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [Int: Int] = [:]
    private var nextViewId = 1

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return map.isEmpty
    }

    /// DisplayOutput ids that already have a Flutter view.
    var outputIds: [Int] {
        lock.lock(); defer { lock.unlock() }
        return Array(map.values)
    }

    subscript(viewId: Int) -> Int? {
        get { lock.lock(); defer { lock.unlock() }; return map[viewId] }
        set { lock.lock(); map[viewId] = newValue; lock.unlock() }
    }

    /// Unique, nonzero Flutter view id (0 is the implicit primary view).
    func allocateViewId() -> Int {
        lock.lock(); defer { lock.unlock() }
        let id = nextViewId
        nextViewId += 1
        return id
    }

    /// Drop mappings for outputs that no longer exist (monitor unplugged),
    /// so a reconnected output gets a fresh view.
    func removeMappings(notIn aliveOutputIds: Set<Int>) {
        lock.lock(); defer { lock.unlock() }
        map = map.filter { aliveOutputIds.contains($0.value) }
    }

    /// Forget the view on `outputId` (the output is becoming the host — the
    /// engine removes its explicit view). Returns the Flutter view id that
    /// was mapped, or nil if the output had none.
    @discardableResult
    func removeMapping(forOutput outputId: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = map.first(where: { $0.value == outputId }) else { return nil }
        map.removeValue(forKey: entry.key)
        return entry.key
    }
}

let secondaryViewOutputs = SecondaryViewOutputsMap()

/// Whether the workspace UI belongs on `output` right now: THIS output's
/// active space is a workspace. Each monitor in workspace mode shows its OWN
/// workspace (per-output rail selection), so there is no single owner any
/// more — every output whose space is the workspace draws one.
func workspaceIsOn(output: DisplayOutput) -> Bool {
    guard let shell = _shellState else { return false }
    return shell.windowManager.activeSpace(onOutput: output.id).isWorkspace
}

/// Whether Mission Control belongs on `output` — invoked-output-scoped, like
/// the workspace and launcher.
func missionControlIsOn(output: DisplayOutput) -> Bool {
    guard let shell = _shellState else { return false }
    return shell._missionControlOpen
        && shell._missionControlOutputId == output.id
}

/// Whether the app launcher belongs on `output` — it opens on whichever output
/// asked for it (the dock, or a workspace's `+`).
func launcherIsOn(output: DisplayOutput) -> Bool {
    guard let shell = _shellState else { return false }
    return shell._launcherOpen && shell._launcherOutputId == output.id
}

/// The topmost window shown on `output`, if it is fullscreen — the one whose
/// title bar the reveal zone uncovers. Shared by the screen's build and by the
/// host's rebuild signature, so the two cannot disagree about whether this
/// output is currently showing fullscreen chrome.
func fullscreenWindow(onOutput output: DisplayOutput) -> WindowInfo? {
    guard let wm = _shellState?.windowManager else { return nil }
    let top = wm.visibleWindows.last(where: { w in
        w.rect.right > output.logicalLeft && w.rect.left < output.logicalRight &&
        w.rect.bottom > output.logicalTop && w.rect.top < output.logicalBottom
    })
    guard let top, top.isFullscreen else { return nil }
    return top
}

/// Rebuild hooks for the secondary-output screens, keyed by output id.
/// Populated by SecondaryScreenHost states; poked by the primary shell
/// whenever its state changes (window moves, opens, closes, focus).
nonisolated(unsafe) var secondaryScreenInvalidators: [Int: () -> Void] = [:]

/// Unconditional-rebuild hooks, keyed by output id — the mailbox drop
/// recovery. A dropped frame means the panel is showing STALE content while
/// the signature (rects, focus, theme) is unchanged, so the gated
/// invalidator above would do nothing; this one bypasses the gate and
/// re-renders the view outright.
nonisolated(unsafe) var secondaryScreenForceRedraws: [Int: () -> Void] = [:]

/// Ask every secondary screen to re-check its content. Each host skips the
/// rebuild unless the windows visible on ITS output actually changed.
func invalidateSecondaryScreens() {
    for invalidate in secondaryScreenInvalidators.values {
        invalidate()
    }
}

/// Keep Wayland clients' wl_surface enter/leave in step with where their
/// windows sit in the virtual desktop. Diffing happens in WaylandIntegration
/// (per-surface mask cache), so calling this on every shell state change is
/// cheap; non-Wayland windows no-op.
func updateWaylandSurfaceOutputs() {
    guard let dl = displayLayout, dl.outputs.count > 1,
          let wl = waylandIntegration,
          let shell = _shellState else { return }
    for win in shell.windowManager.visibleWindows {
        wl.updateSurfaceOutputs(
            windowId: win.id,
            intersectingIds: dl.outputs(intersectingRect: win.rect).map { $0.id },
            // Frame pacing keys off the output the window MOSTLY sits on —
            // a straddler must not be paced by both panels' flips.
            paceOutputId: dl.owningOutput(ofRect: win.rect).id)
    }
}

// MARK: - SecondaryScreenHost

/// Hosts one secondary output's screen in its own widget tree and rebuilds it
/// when the shared shell state changes. Rebuilds are signature-gated: dock
/// animations and other primary-only churn don't re-present a static output.
class SecondaryScreenHost: StatefulWidget {
    let output: DisplayOutput

    init(output: DisplayOutput) {
        self.output = output
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _SecondaryScreenHostState(output: output)
    }
}

class _SecondaryScreenHostState: State<StatefulWidget> {
    /// The record this view was created with. Only its `id` is dependable —
    /// everything else (size on a mode change, `isPrimary` when the user picks
    /// a different primary display) is a snapshot from view-creation time.
    /// Read `output` instead, which re-resolves against the live layout.
    private let initialOutput: DisplayOutput
    private var _lastSignature = ""

    /// This output as it is right now.
    var output: DisplayOutput {
        displayLayout?.outputs.first(where: { $0.id == initialOutput.id })
            ?? initialOutput
    }

    init(output: DisplayOutput) {
        self.initialOutput = output
        super.init()
    }

    override func initState() {
        super.initState()
        secondaryScreenInvalidators[initialOutput.id] = { [weak self] in
            self?._poke()
        }
        secondaryScreenForceRedraws[initialOutput.id] = { [weak self] in
            self?.setState {}
        }
    }

    override func dispose() {
        secondaryScreenInvalidators.removeValue(forKey: initialOutput.id)
        secondaryScreenForceRedraws.removeValue(forKey: initialOutput.id)
        super.dispose()
    }

    /// What this output shows, as a comparable string: the windows that
    /// intersect it (id/rect/focus) plus the shared wallpaper texture and
    /// the active theme (an appearance switch must re-present).
    private func _signature() -> String {
        var sig = "wp:\(sharedWallpaperTextureId):\(shellTheme.name)"
        if let wm = _shellState?.windowManager {
            for win in wm.visibleWindows where _intersectsOutput(win.rect) {
                let r = win.rect
                sig += "|\(win.id):\(r.left),\(r.top),\(r.width),\(r.height)" +
                    ":\(win.id == wm.focusedWindowId ? 1 : 0):\(win.zIndex)"
            }
        }
        // Revealing a fullscreen window's title bar changes no rect, so
        // without this the hover would set the flag and nothing would ever
        // repaint — the bar would stay hidden and the window stay stuck.
        if let fs = fullscreenWindow(onOutput: output) {
            sig += "|tb:\(fs.id):\(_shellState?.topBarRevealed == true ? 1 : 0)"
        }
        // Whether this output is hosting a shell overlay. `_poke` bypasses the
        // gate WHILE hosting, but that is edge-blind on the way out: the moment
        // the overlay closes the bypass stops applying, and without this the
        // signature would be unchanged and the closed launcher would stay
        // painted. Caught exactly that way.
        // Same reasoning for the dock: `_poke` bypasses the gate while this
        // output is primary, so the *last* poke before it stops being primary
        // is the one that has to erase the dock — and by then the bypass no
        // longer applies.
        sig += "|ovl:\(workspaceIsOn(output: output) ? 1 : 0)"
            + ":\(launcherIsOn(output: output) ? 1 : 0)"
            + ":\(missionControlIsOn(output: output) ? 1 : 0)"
            + ":\(output.isPrimary ? 1 : 0)"
            + ":\(_shellState?.contextMenuWidget(forOutput: output) != nil ? 1 : 0)"
        return sig
    }

    private func _intersectsOutput(_ r: Rect) -> Bool {
        r.right > output.logicalLeft && r.left < output.logicalRight &&
        r.bottom > output.logicalTop && r.top < output.logicalBottom
    }

    private func _poke() {
        // While this output hosts the workspace UI, skip the gate entirely and
        // rebuild on every shell change. The workspace has far more state than
        // a signature could summarise — rail rows, window counts, tab strip,
        // active tab, divider — and an under-described signature here is a
        // stale pane, which is the same failure the traffic lights had.
        //
        // Same for the dock, once this output is the primary display. The gate
        // exists to keep "dock animations and other primary-only churn" from
        // re-presenting a static output — but when the dock is HERE that churn
        // is this output's own, and dropping it freezes magnification, the
        // running-app dots, and drag reordering mid-gesture.
        if workspaceIsOn(output: output) || launcherIsOn(output: output)
            || missionControlIsOn(output: output) || output.isPrimary {
            setState {}
            return
        }
        let sig = _signature()
        if sig != _lastSignature {
            setState {}
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        _lastSignature = _signature()
        return SecondaryOutputScreen(output: output).build()
    }
}

// MARK: - SecondaryOutputScreen

/// The desktop on an output other than the shell's host: per-output wallpaper
/// and menu bar (macOS policy — a menu bar on every display), plus every window
/// whose virtual-desktop rect intersects this output, positioned in
/// output-local coordinates. A window straddling the seam renders on both
/// outputs, each showing its own portion.
///
/// It draws the dock too when the user has made THIS output the primary
/// display. There is still exactly one dock: the shell's own tree stops drawing
/// it as soon as the host is not the primary (`dockIsOnHost`).
///
/// This widget lives in its own widget tree (one per Flutter view); shared
/// shell state is reached through the _shellState global and rebuilds arrive
/// via secondaryScreenInvalidators.
struct SecondaryOutputScreen {
    let output: DisplayOutput

    private func _statusBar() -> Widget {
        // Static clock: rendered at build time. Live per-output menu bar
        // content (frontmost app, ticking clock) arrives with the shared
        // window state work.
        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d"
        let combined = "\(timeFormatter.string(from: now))   \(dateFormatter.string(from: now))"

        return ClipRect(
            child: BackdropFilter(
                filter: ImageFilterFactory.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: shellTheme.barTint,
                        border: Border(bottom: BorderSide(color: shellTheme.barHairline, width: 1))),
                    child: Padding(
                        padding: EdgeInsets(left: 16, top: 0, right: 16, bottom: 0),
                        child: Row(
                            mainAxisAlignment: .spaceBetween,
                            crossAxisAlignment: .center,
                            children: [
                                Text(combined, style: TextStyle(
                                    color: shellTheme.fgPrimary, fontSize: 13,
                                    fontWeight: .w500)),
                                Text(output.name, style: TextStyle(
                                    color: shellTheme.fgSecondary, fontSize: 12)),
                            ])))))
    }

    private func _wallpaper() -> Widget {
        // The same wallpaper as the primary: the still image comes through
        // the shared GL texture; an animated preset self-animates here too
        // (its ticker drives this tree's own frames, independent of the
        // rebuild gate). `.slate` is only the nothing-to-show fallback now.
        let base: Widget
        #if os(Linux)
        if _shellState?.wallpaperPreset == .still, sharedWallpaperTextureId >= 0 {
            base = TextureWidget(
                textureId: Int(sharedWallpaperTextureId), filterQuality: .low)
        } else {
            base = DesktopBackground(preset: _shellState?.wallpaperPreset ?? .slate)
        }
        #else
        base = DesktopBackground(preset: _shellState?.wallpaperPreset ?? .slate)
        #endif
        // Right-click opens the desktop context menu HERE — the primary's
        // listener lives in another tree and never sees this monitor's
        // pointer. Same catch-all cursor reset as the primary's wallpaper.
        let outputId = output.id
        return Listener(
            onPointerDown: { event in
                if event.buttons & kSecondaryButton != 0 {
                    _shellState?.openContextMenu(
                        at: event.position, onOutput: outputId)
                }
            },
            onPointerHover: { _ in DesktopCursor.setShape(.default) },
            behavior: .opaque,
            child: base)
    }

    /// Windows intersecting this output, in output-local coordinates.
    /// Callbacks mutate the shared shell state, which re-invalidates every
    /// screen through the shell's setState.
    ///
    /// Chrome actions (the traffic lights, title-bar double-click) go through
    /// the shell's `requestWindow*` methods rather than being respelled here:
    /// this tree is a second set of `DesktopWindow`s, and anything it leaves
    /// nil is a button that draws normally and does nothing once the window is
    /// on this monitor.
    private func _windows() -> [Widget] {
        _windowWidgets(_shellState?.windowManager.visibleWindows ?? [])
    }

    /// The DesktopWindow widgets for `wins` that intersect this output, in
    /// output-local coordinates — factored from `_windows()` so a space
    /// slide can render one list per moving layer.
    private func _windowWidgets(_ wins: [WindowInfo]) -> [Widget] {
        guard let shell = _shellState else { return [] }
        let wm = shell.windowManager
        let fullscreenId = fullscreenWindow(onOutput: output)?.id
        var widgets: [Widget] = []
        for win in wins {
            let r = win.rect
            guard r.right > output.logicalLeft, r.left < output.logicalRight,
                  r.bottom > output.logicalTop, r.top < output.logicalBottom
            else { continue }
            let winId = win.id
            widgets.append(Positioned(
                key: ValueKey("sec\(output.id)-\(winId)"),
                left: r.left - output.originX,
                top: r.top - output.originY,
                width: r.width, height: r.height,
                child: DesktopWindow(
                    windowInfo: win,
                    isFocused: winId == wm.focusedWindowId,
                    isTopBarRevealed: winId == fullscreenId && shell.topBarRevealed,
                    onBringToFront: {
                        _shellState?.setState {
                            _shellState?.windowManager.bringToFront(winId)
                        }
                    },
                    onMove: { delta in
                        _shellState?.setState {
                            _shellState?.windowManager.moveWindowByDelta(winId, delta: delta)
                        }
                    },
                    onResize: { edge, delta in
                        _shellState?.setState {
                            _shellState?.windowManager.resizeWindow(winId, edge: edge, delta: delta)
                        }
                    },
                    onMinimize: { _shellState?.requestWindowMinimize(winId) },
                    onMaximize: { _shellState?.requestWindowMaximize(winId) },
                    onClose: { _shellState?.requestWindowClose(winId) },
                    onTitleBarDoubleTap: {
                        _shellState?.requestWindowTitleBarDoubleTap(winId)
                    })))
        }
        return widgets
    }

    func build() -> Widget {
        var layers: [Widget] = []
        if let shell = _shellState, let slide = shell._secondarySlides[output.id] {
            // Mid space-switch: two full-screen layers (wallpaper + that
            // space's windows) sliding past each other — the host's
            // animation, rendered by this tree from the shared slide state.
            // Windows owned by OTHER outputs stay put above the slide.
            let p = slide.curve.value
            let w = output.logicalWidth
            let pairs = [(slide.fromId, -slide.dir * p * w),
                         (slide.toId, slide.dir * (1.0 - p) * w)]
            for (sid, dx) in pairs {
                let wins = shell.windowManager.slideWindows(
                    inSpaceId: sid, onOutput: output.id)
                layers.append(Positioned(
                    left: dx, top: 0,
                    width: w, height: output.logicalHeight,
                    child: Stack(fit: .expand, children:
                        [Positioned(fill: (), child: _wallpaper())]
                        + _windowWidgets(wins))))
            }
            let sliding = Set(pairs.map { $0.0 })
            layers.append(contentsOf: _windowWidgets(
                shell.windowManager.visibleWindows
                    .filter { !sliding.contains($0.spaceId) }))
        } else {
            layers.append(Positioned(fill: (), child: _wallpaper()))
            layers.append(contentsOf: _windows())
        }
        if missionControlIsOn(output: output), let shell = _shellState {
            // Mission Control replaces this output's desktop layers — its
            // exposé re-renders the windows as cards, and the spaces strip
            // sits in the status bar's zone. The host's copy is gated off
            // by mcIsOnHost, so exactly one tree draws it.
            layers.removeAll(where: { _ in true })
            layers.append(Positioned(fill: (), child: _wallpaper()))
            layers.append(Positioned(
                fill: (),
                child: Builder { ctx in shell._buildMissionControl(ctx) }))
        } else {
            layers.append(Positioned(
                left: 0, top: 0,
                width: output.logicalWidth,
                height: DesktopTheme.kStatusBarHeight,
                child: _statusBar()))
        }

        // The dock, when this output is the primary display. There is one dock
        // and it lives on the primary (macOS); the shell's own tree drops it
        // the moment that is not the host output, so exactly one tree draws it.
        if let dock = _shellState?.dockWidget(forOutput: output) {
            layers.append(dock)
        }

        // The desktop context menu, when it was opened on this output —
        // barrier first, so a click elsewhere dismisses.
        if let menu = _shellState?.contextMenuWidget(forOutput: output) {
            layers.append(Positioned(
                fill: (),
                child: Listener(
                    onPointerDown: { _ in _shellState?.dismissContextMenu() },
                    behavior: .opaque,
                    child: ColoredBox(
                        color: Color(0x00000000),
                        child: SizedBox(expand: ())))))
            layers.append(menu)
        }

        // A dock icon's context menu belongs on the same screen as the icon,
        // with the usual click-anywhere-else barrier under it.
        if let menu = _shellState?.dockIconMenuWidget(forOutput: output) {
            layers.append(Positioned(
                fill: (),
                child: Listener(
                    onPointerDown: { _ in _shellState?.dismissDockIconMenu() },
                    behavior: .opaque,
                    // A ColoredBox hit-tests opaque even at alpha 0, which is
                    // exactly what a barrier wants; the bare SizedBox rule is
                    // for overlays that must let events through.
                    child: ColoredBox(
                        color: Color(0x00000000),
                        child: SizedBox(expand: ())))))
            layers.append(menu)
        }

        // Fullscreen chrome reveal, mirroring the primary's zones: a 4px
        // sliver at the top catches the approach, and once revealed the zone
        // grows to cover the status bar plus the title-bar overlay so moving
        // onto the traffic lights doesn't count as leaving it. Hovering below
        // hides it again. `.translucent` over a bare SizedBox — a ColoredBox
        // would hit-test opaque even at alpha 0 and eat the window's events.
        if fullscreenWindow(onOutput: output) != nil {
            let revealed = _shellState?.topBarRevealed == true
            let zoneH = revealed
                ? DesktopTheme.kStatusBarHeight + DesktopTheme.kTitleBarHeight
                : 4.0
            layers.append(Positioned(
                left: 0, top: 0, right: 0, height: zoneH,
                child: Listener(
                    onPointerHover: { _ in _shellState?.setTopBarRevealed(true) },
                    behavior: .translucent,
                    child: SizedBox(expand: ()))))
            // The dock's own sensor, and only where the dock actually is: a
            // sliver at the bottom reveals it, the band between the two zones
            // hides both. Without this, sending a window fullscreen on the
            // primary display would hide the dock with no way to get it back —
            // the primary tree's sensors are on a different monitor.
            let hasDock = output.isPrimary
            let dockZoneH = !hasDock ? 0.0
                : (_shellState?.dockRevealed == true
                    ? DesktopTheme.kDockBottomMargin + DesktopTheme.kDockContainerHeight
                    : 4.0)
            layers.append(Positioned(
                left: 0, top: zoneH, right: 0, bottom: dockZoneH,
                child: Listener(
                    onPointerHover: { _ in
                        _shellState?.setTopBarRevealed(false)
                        if hasDock { _shellState?.setDockRevealed(false) }
                    },
                    behavior: .translucent,
                    child: SizedBox(expand: ()))))
            if hasDock {
                layers.append(Positioned(
                    left: 0, right: 0, bottom: 0, height: dockZoneH,
                    child: Listener(
                        onPointerHover: { _ in _shellState?.setDockRevealed(true) },
                        behavior: .translucent,
                        child: SizedBox(expand: ()))))
            }
        }

        // The workspace UI, when this is the output it was invoked from. Drawn
        // over this output's desktop and in its own local coordinates — the
        // same code the primary runs, just handed a different output. It goes
        // last so it covers the status bar, exactly as on the primary.
        if workspaceIsOn(output: output), let shell = _shellState {
            layers.append(Positioned(
                key: ValueKey("workspace-space-\(output.id)"),
                left: 0, top: 0,
                width: output.logicalWidth, height: output.logicalHeight,
                child: shell._buildWorkspaceSpace(output: output)))
        }

        // The launcher, when it was opened from this output. Above the
        // workspace UI, which is what opens it from in here.
        if launcherIsOn(output: output), let shell = _shellState {
            layers.append(Positioned(
                fill: (),
                child: AppLauncher(
                    apps: shell._launcherFilteredApps(),
                    query: shell._launcherQuery,
                    caretOn: shell._launcherCaretOn,
                    onLaunch: { appId in shell._launchFromLauncher(appId) },
                    onDismiss: {
                        shell.setState {
                            shell._launcherOpen = false
                            shell._launcherQuery = ""
                            shell._launcherDriverTarget = nil
                        }
                    })))
        }

        // This tree has no MacosApp above it, so establish text direction
        // ourselves — Stack/Row alignment resolution traps without it.
        // The outer Listener reports which monitor the pointer is on, so a
        // workspace toggled from here opens here (observation only; it
        // consumes nothing). It also drives dock magnification, which the
        // primary tree's hook cannot: its pointer events are on another panel.
        return Directionality(
            textDirection: .ltr,
            child: Listener(
                onPointerDown: { _ in _shellState?.notePointerOutput(output.id) },
                onPointerHover: { event in
                    _shellState?.notePointerOutput(output.id)
                    _shellState?._updateDockHover(
                        x: event.position.dx, y: event.position.dy,
                        outputId: output.id)
                },
                behavior: .translucent,
                child: Stack(fit: .expand, children: layers)))
    }
}
