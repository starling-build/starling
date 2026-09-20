// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation
import StarlingRegistry

// MARK: - The 3D desktop (docs/plans/desktop-3d.md)
//
// A room you are standing in, with a real camera. 2D is today's desktop,
// pixel for pixel; 3D puts you inside a hall built out of your wallpaper,
// with the windows hanging in it as panes of glass at real places. You
// walk with the keyboard. Approach a window and it grows the way a thing
// in a room grows; stand at the right distance, square on, and it is
// pixel-exact again.
//
// WORLD UNITS ARE METRES. y is up, the picture hangs on the wall at
// z = 0, and the viewer starts back down the hall looking at it. One
// logical pixel of a window is `k3DMetresPerPx` across, so a window has a
// real size in the room and "1:1" is a real distance you can walk to.
//
// Windows stay in the Flutter layer tree under a `Transform` carrying the
// whole projection · view · model chain. That is what buys the two things
// a hand-rolled GL desktop would have to rebuild: the engine rasterises
// each window's external texture through the matrix, and
// RenderTransform's hit test runs the same matrix backwards with the
// homogeneous divide — so a click on a window across the room lands on
// the right client pixel with no new input code at all.
//
// `_desktop3DT` is still the one number the enter/leave tween moves, and
// t = 0 is still EXACTLY the flat desktop: at t = 0 no window gets a
// matrix at all (identity would resample), and the room's surfaces have
// collapsed onto the picture's edges. The camera's home position is the
// one place in the room where the picture fills the view precisely, so
// the flat desktop is simply "standing at the right spot", and entering
// 3D is the room unfolding around you from there.

/// Where a window stands in the room: the centre of its pane, in metres,
/// and which way it faces. Kept beside `WindowInfo.rect`, never derived
/// from it by 2D and never written by it, so leaving 3D changes nothing
/// here and re-entering finds the arrangement again.
struct WindowPose3D: Equatable {
    var x = 0.0
    var y = 0.0
    var z = 0.0
    /// Radians about the world's y axis. 0 faces +z, down the hall.
    var yaw = 0.0
    /// How big the pane is against its 1:1 size: 1 on a wall, a fraction
    /// as a moon in the orrery, and back to 1 when it is picked up.
    var scale = 1.0
    /// False until the window has been given a place in the room; the
    /// first entry into 3D lays every window out and sets it.
    var placed = false
}

/// The viewer: a real camera standing in the room.
struct Camera3D: Equatable {
    var x = 0.0
    var y = 0.0
    var z = 0.0
    /// Radians. 0 looks down -z, at the picture.
    var yaw = 0.0
    var pitch = 0.0
}

/// Where one window ends up on screen this frame.
enum Desktop3DPlacement {
    /// 2D, or t = 0: no matrix at all, the plain-translation paint path,
    /// pixel-exact.
    case flat
    /// In the room: the full transform, and the pivot its coordinates are
    /// centred on (handed to `Transform` as `origin`, made window-local).
    case posed(Matrix4, Offset)
    /// Behind the viewer, past the near plane, or turned away. `Transform`
    /// does no near-plane clipping and Skia draws garbage past it, so the
    /// window is not drawn at all.
    case hidden
}

/// The light one window sits in. Resolved per window from the wallpaper
/// itself: the room's back wall IS the picture, so "what is behind this
/// window" is the part of the picture the window stands in front of.
///
/// The two things this does NOT do were both measured out rather than
/// skipped — see `docs/plans/desktop-3d.md`, Phase 2a.
struct RoomLight: Equatable {
    /// The average colour of the picture behind the window.
    var color: Color
    /// How much of that colour veils the window. Aerial perspective: the
    /// depth cue that works on a flat screen, because it does not need
    /// two eyes or a moving head.
    var haze: Double
    /// How far off the room the window reads as floating, 0 to 1 with the
    /// enter/leave tween. Scales the drop shadow.
    var separation: Double
    /// What the pane's four edges catch of the room's light, lit by the
    /// same sky as the room itself. A pane with no edge is infinitely
    /// thin and reads as a decal stuck to the view; give it a few
    /// millimetres that take the light and it becomes an object. The
    /// side facing the windows comes up bright and the side facing away
    /// stays dark, which is the whole cue.
    var edgeTop: Color = Color(0x00000000)
    var edgeRight: Color = Color(0x00000000)
    var edgeBottom: Color = Color(0x00000000)
    var edgeLeft: Color = Color(0x00000000)
}

extension _DesktopShellState {

    // MARK: The room, in metres

    /// A game lens, not a desktop one. The flat desktop's implied lens is
    /// long and flattening; standing in a room wants something near what
    /// a person actually sees.
    static let k3DFovX = 70.0 * Double.pi / 180
    /// How big a window is in the room: one logical pixel across. A
    /// 1280-pixel window comes out 2.6 m wide and reads 1:1 from about
    /// 1.8 m — a step and a half away, which is where you would stand to
    /// read something on a wall.
    static let k3DMetresPerPx = 0.0019
    /// Where the viewer stands when the room opens: back in the room,
    /// looking at the windows, at eye height.
    static let k3DEyeHeight = 1.68
    static let k3DHomeZ = 9.3

    /// Where the windows are put when the room first lays them out, and
    /// how wide the fan is.
    static let k3DArcRadius = 3.7
    static let k3DArcSpread = 52.0 * Double.pi / 180

    /// Walking. One key press (or repeat) is one step.
    static let k3DStep = 0.22
    static let k3DTurn = 2.6 * Double.pi / 180
    static let k3DTransitionMs = 600
    static let k3DDollyTransitionMs = 1000

    var _desktop3DActive: Bool { _desktop3DT > 0 }

    /// Whether the room renderer draws the windows itself, as panes in
    /// its scene (Filament), rather than the layer tree drawing them over
    /// the room. The widget stays either way: it is what the pointer hits.
    var _desktop3DScene: Bool {
        #if os(Linux)
        return _environment is FilamentRoomRenderer
        #else
        return false
        #endif
    }

    /// The world the renderer is showing (nil before it exists, or for
    /// the GL room, which is always the room).
    var _desktop3DWorld: World3D? {
        #if os(Linux)
        return (_environment as? FilamentRoomRenderer)?.world
        #else
        return nil
        #endif
    }
    var _desktop3DOrrery: Bool { _desktop3DWorld?.kind == .orrery }
    /// A world walked on the ground with the windows standing round a
    /// square (the voxel city).
    var _desktop3DVoxel: Bool { _desktop3DWorld?.kind == .voxel }
    /// Out in a world there is no desktop chrome: no dock, no status bar.
    var _desktop3DChromeless: Bool { _desktop3DT > 0 && (_desktop3DOrrery || _desktop3DVoxel) }

    /// The orrery's tilt: the ring of planets is a disc tipped toward the
    /// viewer, as an orrery on a stand is, so from eye level it reads as
    /// an ellipse and not a line of beads.
    static let k3DOrreryTilt = 20.0 * Double.pi / 180

    /// A point on a tilted ring round the hub: `phi` runs round the ring,
    /// with phi = pi/2 nearest the home viewer (+z).
    func _desktop3DRingPoint(_ w: World3D, radius: Double, phi: Double,
                             about centre: (x: Double, y: Double, z: Double)? = nil)
        -> (x: Double, y: Double, z: Double) {
        let c = centre ?? w.hub
        let a = Self.k3DOrreryTilt
        return (c.x + radius * cos(phi),
                c.y - radius * sin(phi) * sin(a),
                c.z + radius * sin(phi) * cos(a))
    }

    /// Where windows hang when the room draws them: on the side walls,
    /// alternately left and right, from the far end (in view from the
    /// door) toward the viewer. Centre height, first slot's z and the
    /// spacing along the wall; a 1280-px window is 2.4 m wide.
    static let k3DWallHeight = 1.6
    static let k3DWallFirstZ = 1.5
    static let k3DWallSpacing = 2.7
    /// Off the wall by the frame's depth and a little air.
    static let k3DWallOffset = 0.045

    /// STARLING_3D_LOG=1: what the camera is doing, on stderr.
    func _desktop3DLog(_ m: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["STARLING_3D_LOG"] == "1" else { return }
        FileHandle.standardError.write(Data("[3D] \(m())\n".utf8))
    }

    /// The focal length in logical pixels that the room's lens implies on
    /// this output.
    func _desktop3DFocalPx(_ host: Rect) -> Double {
        (host.width / 2) / tan(Self.k3DFovX / 2)
    }

    /// Where the viewer stands when the room opens: back in the room with
    /// the windows ahead, at eye height.
    func _desktop3DHomeCamera(_ host: Rect) -> Camera3D {
        if let w = _desktop3DWorld, w.kind == .orrery {
            return Camera3D(x: w.hub.x, y: w.hub.y + w.cameraHeight,
                            z: w.hub.z + w.cameraRadius, yaw: 0, pitch: 0)
        }
        if let w = _desktop3DWorld, w.kind == .voxel {
            if let nav = w.navigation {
                let p = nav.spawn
                return Camera3D(x: p[0], y: w.ground(p[0], p[1]) + nav.eye_height,
                                z: p[1], yaw: p[2] * .pi / 180, pitch: p[3] * .pi / 180)
            }
            let z = w.hub.z + w.cameraRadius
            return Camera3D(x: w.hub.x, y: w.ground(w.hub.x, z) + w.eyeHeight + w.cameraHeight,
                            z: z, yaw: 0, pitch: atan2(w.cameraHeight, w.cameraRadius + 35))
        }
        return Camera3D(x: 0, y: Self.k3DEyeHeight, z: Self.k3DHomeZ, yaw: 0, pitch: 0)
    }

    /// The camera the orbit state describes: on a circle round the hub at
    /// `theta`, looking at the hub.
    func _desktop3DOrbitCamera(_ o: (theta: Double, radius: Double, height: Double)) -> Camera3D {
        let w = _desktop3DWorld ?? World3D()
        return Camera3D(x: w.hub.x + o.radius * sin(o.theta), y: w.hub.y + o.height,
                        z: w.hub.z + o.radius * cos(o.theta), yaw: -o.theta, pitch: 0)
    }

    /// Where a window hangs when it is simply showing its 2D rect: the
    /// plane in front of `camera` at which one logical pixel is one
    /// screen pixel. The camera is the tween's (`_desktop3DTweenCamera`),
    /// so while the entrance dollies the viewer forward the flat windows
    /// ride along in front of it, and t = 0 is the exact 2D desktop from
    /// wherever the dolly starts. (Assumes the camera looks down -z,
    /// which every world's home does.)
    func _desktop3DFlatPose(rect: Rect, host: Rect, camera: Camera3D) -> WindowPose3D {
        let d1 = _desktop3DFocalPx(host) * Self.k3DMetresPerPx
        return WindowPose3D(
            x: camera.x + (rect.center.dx - host.center.dx) * Self.k3DMetresPerPx,
            y: camera.y - (rect.center.dy - host.center.dy) * Self.k3DMetresPerPx,
            z: camera.z - d1,
            yaw: 0, placed: true)
    }

    /// Where the entrance starts: the world's dolly length behind the
    /// home spot, along its facing. The home spot itself in a world with
    /// no dolly (the room), so nothing there changes.
    func _desktop3DDollyStart(_ host: Rect) -> Camera3D {
        var c = _desktop3DHomeCamera(host)
        let d = _desktop3DWorld?.cameraDolly ?? 0
        guard d > 0 else { return c }
        c.x -= sin(c.yaw) * d
        c.z += cos(c.yaw) * d
        return c
    }

    // MARK: Laying the windows out

    /// Give any window that has no place in the room one: a fan in front
    /// of wherever the viewer is standing, ordered left to right by where
    /// the windows already were on screen, so nothing teleports and the
    /// arrangement the user had is still legible.
    ///
    /// Called from the window-stack builder rather than only on entry,
    /// because windows appear at every moment — a fresh launch, a restore
    /// from minimise, and the case that caught this out, a session that
    /// came up with the room ALREADY open, where entering never happened
    /// at all. It only ever writes to a window that has no place, so it
    /// settles on the first build and does nothing on every later one.
    @discardableResult
    func _desktop3DPlaceWindows() -> Bool {
        let host = _desktop3DHost
        guard host.width > 0 else { return false }
        let fresh = windowManager.visibleWindows
            .filter { !$0.pose3D.placed }
            .sorted { $0.rect.center.dx < $1.rect.center.dx }
        guard !fresh.isEmpty else { return false }
        #if os(Linux)
        if _desktop3DVoxel, let w = _desktop3DWorld {
            // The city: a new window takes the next place on the arc round
            // the square — unless its app was just double-clicked in the
            // pile, in which case it pops up in front of the viewer, at
            // reading size, with the keyboard, the way a window opens on
            // the flat desktop.
            var taken = windowManager.visibleWindows.filter { $0.pose3D.placed }.count
            for win in fresh {
                let previousView = _desktop3DViewOverride
                _desktop3DViewOverride = _desktop3DOutputId(for: win)
                defer { _desktop3DViewOverride = previousView }
                if let outputId = _desktop3DLaunchOutputs.removeValue(forKey: _desktop3DAppId(of: win)),
                   let output = displayLayout?.outputs.first(where: { $0.id == outputId }) {
                    let delta = output.logicalRect.center - win.rect.center
                    windowManager.moveWindowByDelta(win.id, delta: delta)
                    win.spaceId = windowManager.activeSpaceId(onOutput: outputId)
                    _desktop3DViewOverride = outputId
                }
                if _desktop3DPopUp == _desktop3DAppId(of: win) || w.navigation != nil {
                    _desktop3DPopUp = nil
                    _desktop3DPopUpWindow(win, host: _desktop3DHost, w: w)
                    let id = win.id
                    // After this build: focus is state, and this runs inside one.
                    let work: () -> Void = { [weak self] in
                        guard let self else { return }
                        self.setState {
                            self.windowManager.bringToFront(id)
                            self.windowManager.focusedWindowId = id
                        }
                    }
                    DispatchQueue.main.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
                } else {
                    win.pose3D = _desktop3DArcPose(slot: taken, rect: win.rect, w: w)
                    taken += 1
                }
            }
            return true
        }
        if _desktop3DScene {
            let taken = windowManager.visibleWindows.filter { $0.pose3D.placed }.count
            let off = Room3D.halfW - Self.k3DWallOffset
            for (i, win) in fresh.enumerated() {
                let slot = taken + i
                let left = slot % 2 == 0
                win.pose3D = WindowPose3D(
                    x: left ? -off : off,
                    y: Self.k3DWallHeight,
                    z: Self.k3DWallFirstZ + Double(slot / 2) * Self.k3DWallSpacing,
                    // Facing into the room: +x off the left wall, -x off the right.
                    yaw: left ? .pi / 2 : -.pi / 2,
                    placed: true)
            }
            return true
        }
        #endif
        // In front of the viewer, not in front of the door: a window that
        // opens while you are down the other end of the hall should be
        // where you are looking.
        let eye = _camera3D
        let taken = windowManager.visibleWindows.filter { $0.pose3D.placed }.count
        let n = fresh.count + taken
        for (i, win) in fresh.enumerated() {
            let slot = taken + i
            let f = n == 1 ? 0.0 : Double(slot) / Double(n - 1) - 0.5
            let a = f * Self.k3DArcSpread + eye.yaw
            win.pose3D = WindowPose3D(
                x: eye.x + Self.k3DArcRadius * sin(a),
                y: eye.y,
                z: eye.z - Self.k3DArcRadius * cos(a),
                // Turn to face the spot the viewer is standing in.
                yaw: -a,
                placed: true)
        }
        return true
    }

    /// A place on the arc round the square for the window in `slot`:
    /// facing the hub, on the ground, flanking the middle — first to the
    /// right, then the left, and on round — so nothing stands straight
    /// behind the pile from the door.
    func _desktop3DArcPose(slot: Int, rect: Rect, w: World3D) -> WindowPose3D {
        let s = Self.k3DMetresPerPx
        let k = Double(slot / 2), side = slot % 2 == 0 ? 1.0 : -1.0
        let phi = -Double.pi / 2 + side * (Self.k3DTowerClearDeg + 30.0 * k) * Double.pi / 180
        let x = w.hub.x + w.ringRadius * cos(phi), z = w.hub.z + w.ringRadius * sin(phi)
        let h = rect.height * s
        return WindowPose3D(x: x, y: w.ground(x, z) + h / 2 + 0.05, z: z,
                            yaw: atan2(w.hub.x - x, w.hub.z - z), scale: 1, placed: true)
    }

    /// The pose that shows a window exactly where its flat rect is on the
    /// viewer's screen, from where they stand and look now: the plane in
    /// front of them at which one logical pixel is one screen pixel,
    /// facing them — the "pop up". Kept off the ground.
    func _desktop3DPoseInFront(rect: Rect, host: Rect, w: World3D) -> WindowPose3D {
        let s = Self.k3DMetresPerPx
        let c = _camera3D
        let d1 = _desktop3DFocalPx(host) * s
        let right = (x: cos(c.yaw), z: sin(c.yaw)), fwd = (x: sin(c.yaw), z: -cos(c.yaw))
        let centre = w.workspaceRail.isEmpty ? rect.center
            : (displayLayout?.owningOutput(ofRect: rect).logicalRect.center ?? host.center)
        let ox = (centre.dx - host.center.dx) * s
        let oy = -(centre.dy - host.center.dy) * s
        let x = c.x + right.x * ox + fwd.x * d1, z = c.z + right.z * ox + fwd.z * d1
        let y = max(c.y + oy, w.ground(x, z) + rect.height * s / 2 + 0.05)
        return WindowPose3D(x: x, y: y, z: z, yaw: -c.yaw, scale: 1, placed: true)
    }

    /// A window pops up in front of the viewer, and whatever already
    /// stands on that plane steps back behind it — a slab's depth and a
    /// hand each, nearest first — so the newest is the one in front and
    /// the rest read as a pile behind it, the way a new window lands on
    /// top on the flat desktop. Two panes on one plane fight for every
    /// pixel, and the one drawn last wins, whichever has the keyboard.
    func _desktop3DPopUpWindow(_ win: WindowInfo, host: Rect, w: World3D) {
        // Reading planes are vertical. A downhill walking pitch projects a
        // screen-sized window above the viewport and hides its title bar.
        if w.navigation != nil && _camera3D.pitch != 0 {
            _camera3D.pitch = 0
            _desktop3DPublishCamera()
        }
        let pose = _desktop3DPoseInFront(rect: win.rect, host: host, w: w)
        win.pose3D = pose
        let c = _camera3D
        let fwd = (x: sin(c.yaw), z: -cos(c.yaw))
        let along = { (p: WindowPose3D) in (p.x - c.x) * fwd.x + (p.z - c.z) * fwd.z }
        let front = along(pose)
        let step = (w.paneFrame?.depth ?? 0.035) + 0.05
        let s = Self.k3DMetresPerPx
        // The pile: every other placed window within a few steps of the
        // plane, nearest first, the higher of two at one depth first.
        var pile: [(win: WindowInfo, at: Double)] = []
        for other in windowManager.visibleWindows where other.id != win.id && other.pose3D.placed && _desktop3DOutputId(for: other) == _desktop3DViewId {
            let at: Double = along(other.pose3D)
            if at > front - step / 2, at < front + 6 * step { pile.append((other, at)) }
        }
        pile.sort { (a: (win: WindowInfo, at: Double), b: (win: WindowInfo, at: Double)) -> Bool in
            if abs(a.at - b.at) > 0.01 { return a.at < b.at }
            return a.win.zIndex > b.win.zIndex
        }
        for (i, entry) in pile.enumerated() {
            let other = entry.win, at = entry.at
            let want: Double = front + Double(i + 1) * step
            guard abs(want - at) > 0.001 else { continue }
            var p = other.pose3D
            p.x += fwd.x * (want - at)
            p.z += fwd.z * (want - at)
            p.y = max(p.y, w.ground(p.x, p.z) + other.rect.height * s / 2 + 0.05)
            other.pose3D = p
        }
        _desktop3DLog("pop up \(win.title): \(pile.count) behind")
    }

    /// The app a window belongs to, for the city: a third-party window
    /// arrives with a synthetic id (`wayland-N`), and its owner is resolved
    /// through the registry the way the dock does it — else Chrome's pane
    /// wore the nameplate "wayland-13" and its brick could not find it.
    func _desktop3DAppId(of win: WindowInfo) -> String {
        _appOwning(win)?.id ?? win.wmClass.flatMap { $0.isEmpty ? nil : $0 } ?? win.appId
    }

    /// A brick was clicked (a press that never became a drag): its app
    /// opens, the way one click on the dock opens an app. The second click
    /// of a double-click — the same brick again within half a second — is
    /// let through as nothing, so a double-click opens the app once too.
    static let k3DDoubleClick = 0.5

    func _desktop3DBrickClicked(_ app: String) {
        let now = Date.timeIntervalSinceReferenceDate
        if let last = _desktop3DBrickClick, last.app == app, now - last.at < Self.k3DDoubleClick {
            _desktop3DBrickClick = nil
            return
        }
        _desktop3DBrickClick = (app, now)
        _desktop3DOpenApp(app)
    }

    /// Open an app from its brick: a window it already has pops up in
    /// front of the viewer and takes the keyboard; otherwise the app is
    /// started and its first window will (see _desktop3DPlaceWindows).
    func _desktop3DOpenApp(_ app: String) {
        _desktop3DLog("open \(app)")
        guard let w = _desktop3DWorld else { return }
        let candidates = w.workspaceRail.isEmpty ? windowManager.visibleWindows : _desktop3DRailWindows()
        if let win = candidates.filter({ _desktop3DAppId(of: $0) == app && !$0.isFullscreen
                && _desktop3DOutputId(for: $0) == _desktop3DViewId })
            .max(by: { $0.zIndex < $1.zIndex }) {
            setState {
                if win.isMinimized { windowManager.restoreWindow(win.id) }
                _desktop3DPopUpWindow(win, host: _desktop3DHost, w: w)
                windowManager.bringToFront(win.id)
                windowManager.focusedWindowId = win.id
            }
            _desktop3DPublishCamera()
            return
        }
        _desktop3DPopUp = app
        _launchOrFocusApp(app)
    }

    // MARK: One active window per display

    /// Each display shows its focused, last shown, or front-most window.
    /// Other displays retain their active pane. The rest are out of sight until
    /// Alt+Tab brings them onto the ring — and stay in sight while they
    /// glide back from it. A fullscreen window is the screen and is
    /// always drawn; nothing is hidden on the flat desktop, nor while the
    /// city is being left, so windows fly home with the rest.
    func _desktop3DIsShown(_ win: WindowInfo) -> Bool {
        guard _desktop3DOutputId(for: win) == _desktop3DViewId else { return false }
        guard _desktop3DVoxel, _desktop3DOn, _desktop3DT > 0 else { return true }
        if win.isFullscreen || _desktop3DShownByOutput.values.contains(win.id) { return true }
        if let sw = _desktop3DSwitcher, sw.ids.contains(win.id) { return true }
        return _desktop3DPoseTweens[win.id] != nil
    }

    /// Decide which window the city shows this build, and when that
    /// changes to a window that is not in front of the viewer, bring it
    /// there: gliding in while the city is up (a window closing hands the
    /// screen to the next, which flies in from wherever it stood), and
    /// simply placed there during the entrance, before anything is seen.
    func _desktop3DUpdateShown() {
        guard _desktop3DVoxel, _desktop3DOn else {
            _desktop3DShownByOutput.removeAll()
            _desktop3DShownRectByOutput.removeAll()
            return
        }
        let candidates = windowManager.visibleWindows.filter { !$0.isFullscreen && $0.pose3D.placed }
        let signature = displayLayout?.outputs.map {
            "\($0.id):\($0.logicalRect):\($0.isPrimary)"
        }.joined(separator: "|") ?? "single"
        if signature != _desktop3DDisplaySignature {
            _desktop3DDisplaySignature = signature
            _desktop3DShownRectByOutput.removeAll()
        }
        let groups = Dictionary(grouping: candidates, by: { _desktop3DOutputId(for: $0) })
        _desktop3DShownByOutput = _desktop3DShownByOutput.filter { groups[$0.key] != nil }
        for (output, windows) in groups {
            let previousView = _desktop3DViewOverride
            _desktop3DViewOverride = output
            defer { _desktop3DViewOverride = previousView }
            let host = _desktop3DHost
            let shown = windows.first { $0.id == windowManager.focusedWindowId }
                ?? windows.first { $0.id == _desktop3DShownByOutput[output] }
                ?? windows.max { $0.zIndex < $1.zIndex }
            guard let win = shown else { continue }
            let previous = _desktop3DShownRectByOutput[output]
            let resized = previous?.width != win.rect.width || previous?.height != win.rect.height
            let changed = _desktop3DShownByOutput[output] != win.id
            _desktop3DShownByOutput[output] = win.id
            _desktop3DShownRectByOutput[output] = win.rect
            guard changed || resized, let world = _desktop3DWorld,
                  resized || _desktop3DPoseTweens[win.id] == nil else { continue }
            let target = _desktop3DPoseInFront(rect: win.rect, host: host, w: world)
            if _desktop3DT >= 1 { _desktop3DTween(win, to: target) } else { win.pose3D = target }
        }
    }
    /// ring turning, a chosen window flying forward. Instant pose writes
    /// elsewhere are untouched. A tween already in flight for the window
    /// restarts from wherever it has got to; the yaw turns the short way.
    func _desktop3DTween(_ win: WindowInfo, to pose: WindowPose3D, ms: Double = k3DSwitchMs) {
        var from = win.pose3D, to = pose
        from.placed = true; to.placed = true
        let d = to.yaw - from.yaw
        to.yaw = from.yaw + atan2(sin(d), cos(d))
        _desktop3DPoseTweens[win.id] = (from, to, Date.timeIntervalSinceReferenceDate, ms)
        if _poseTicker == nil {
            _poseTicker = createTicker { [weak self] _ in
                guard let self else { return }
                let now = Date.timeIntervalSinceReferenceDate
                var done: [String] = []
                for (id, t) in self._desktop3DPoseTweens {
                    guard let w = self.windowManager.windows.first(where: { $0.id == id }) else {
                        done.append(id); continue
                    }
                    let k = min(1.0, max(0.0, (now - t.start) / (t.ms / 1000)))
                    // easeInOutCubic, like the camera's glide.
                    let e = k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
                    w.pose3D = WindowPose3D(
                        x: t.from.x + (t.to.x - t.from.x) * e, y: t.from.y + (t.to.y - t.from.y) * e,
                        z: t.from.z + (t.to.z - t.from.z) * e, yaw: t.from.yaw + (t.to.yaw - t.from.yaw) * e,
                        scale: t.from.scale + (t.to.scale - t.from.scale) * e, placed: true)
                    if k >= 1 { done.append(id) }
                }
                for id in done { self._desktop3DPoseTweens[id] = nil }
                if self._desktop3DPoseTweens.isEmpty { self._poseTicker?.stop() }
                self.setState {}
            }
        }
        if !(_poseTicker?.isActive ?? false) { _ = _poseTicker?.start() }
    }

    // MARK: The switcher — Alt+Tab swings the windows round the viewer

    /// The ring the windows stand on while you choose, and how close the
    /// chosen one comes; the angle between neighbours; the widest a
    /// window is let be on the ring (bigger ones are scaled down, so a
    /// browser and a calculator both read as one thing each); how long
    /// every move takes.
    static let k3DSwitchRadius = 3.8
    static let k3DSwitchNearRadius = 2.8
    static let k3DSwitchStepDeg = 30.0
    static let k3DSwitchMaxWidth = 1.7
    static let k3DSwitchMs = 260.0

    /// Alt+Tab and what follows it, in the city. Tab with Alt held opens
    /// the ring — or, open, moves the choice on (Shift: back); Alt up
    /// settles on the chosen window; Escape puts everything back. True
    /// when the key was the switcher's and must go no further.
    func _desktop3DSwitcherKey(_ key: KeyData, shift: Bool) -> Bool {
        let phys = Int(key.physical)
        let isAlt = phys == 0xE2 || phys == 0xE6
        if _desktop3DSwitcher != nil {
            if isAlt, key.type == .up { _desktop3DSwitcherCommit(); return true }
            if key.type == .up { return false }
            if phys == 0x29 { _desktop3DSwitcherCancel(); return true }              // Escape
            if phys == 0x2B { _desktop3DSwitcherMove(shift ? -1 : 1); return true }   // Tab
            // Anything else pressed while the ring is up is the ring's:
            // a keystroke mid-switch belongs to no app.
            return !isAlt && phys != 0xE1 && phys != 0xE5
        }
        guard phys == 0x2B, key.type == .down, _altPressed, _desktop3DVoxel, _desktop3DT >= 1 else { return false }
        _desktop3DSwitcherOpen()
        return true
    }

    func _desktop3DSwitcherOpen() {
        // Most recent first, as every switcher orders them, and the first
        // press means "the one before this".
        let wins = (_desktop3DWorld?.workspaceRail.isEmpty == false
            ? _desktop3DRailWindows() : windowManager.visibleWindows)
            .filter { !$0.isFullscreen && $0.pose3D.placed && _desktop3DOutputId(for: $0) == _desktop3DViewId }
            .sorted { $0.zIndex > $1.zIndex }
        guard !wins.isEmpty else { return }
        var before: [String: WindowPose3D] = [:]
        for w in wins { before[w.id] = w.pose3D }
        _desktop3DSwitcher = (wins.map { $0.id }, wins.count > 1 ? 1 : 0, before)
        _desktop3DLog("switcher open: \(wins.map { $0.title })")
        _desktop3DSwitcherLayout()
    }

    func _desktop3DSwitcherMove(_ by: Int) {
        guard var sw = _desktop3DSwitcher, !sw.ids.isEmpty else { return }
        sw.selected = (sw.selected + by + sw.ids.count) % sw.ids.count
        _desktop3DSwitcher = sw
        if let w = windowManager.windows.first(where: { $0.id == sw.ids[sw.selected] }) {
            _desktop3DLog("switcher select \(w.title)")
        }
        _desktop3DSwitcherLayout()
    }

    /// The ring: the chosen window straight ahead and a little nearer,
    /// the rest round the viewer at even steps to either side, all at eye
    /// height, all facing in, each scaled to fit its slot — and every
    /// window glides to its place, so a Tab reads as the ring turning.
    func _desktop3DSwitcherLayout() {
        guard let sw = _desktop3DSwitcher, let world = _desktop3DWorld else { return }
        let c = _camera3D
        let s = Self.k3DMetresPerPx
        let step = Self.k3DSwitchStepDeg * Double.pi / 180
        for (i, id) in sw.ids.enumerated() {
            guard let w = windowManager.windows.first(where: { $0.id == id }) else { continue }
            let chosen = i == sw.selected
            let a = c.yaw + Double(i - sw.selected) * step
            let r = chosen ? Self.k3DSwitchNearRadius : Self.k3DSwitchRadius
            let scale = min(1.0, Self.k3DSwitchMaxWidth / max(0.1, w.rect.width * s))
            let x = c.x + sin(a) * r, z = c.z - cos(a) * r
            let y = max(c.y, world.ground(x, z) + w.rect.height * s * scale / 2 + 0.05)
            _desktop3DTween(w, to: WindowPose3D(x: x, y: y, z: z, yaw: -a, scale: scale, placed: true))
        }
    }

    /// Alt up: the chosen window flies up to the front, 1:1, with the
    /// keyboard, and the rest go back where they stood — with whatever
    /// was already at the front stepping back behind the chosen one, as a
    /// pop-up does. Destinations are worked out on the windows' OLD places,
    /// not the ring, so the pile settles where it belongs.
    func _desktop3DSwitcherCommit() {
        guard let sw = _desktop3DSwitcher else { return }
        _desktop3DSwitcher = nil
        let chosenId = sw.ids[sw.selected]
        func find(_ id: String) -> WindowInfo? { windowManager.windows.first(where: { $0.id == id }) }
        var ring: [String: WindowPose3D] = [:]
        for id in sw.ids {
            guard let w = find(id) else { continue }
            ring[id] = w.pose3D
            if let b = sw.before[id] { w.pose3D = b }
        }
        guard let win = find(chosenId), let world = _desktop3DWorld else { return }
        let host = _desktop3DHost
        _desktop3DPopUpWindow(win, host: host, w: world)
        for id in sw.ids {
            guard let w = find(id), let from = ring[id] else { continue }
            let to = w.pose3D
            w.pose3D = from
            _desktop3DTween(w, to: to)
        }
        _desktop3DLog("switcher commit \(win.title)")
        setState {
            if win.isMinimized { windowManager.restoreWindow(win.id) }
            let apps = _desktop3DRailApps()
            if let index = apps.firstIndex(of: _desktop3DAppId(of: win)) {
                _desktop3DRailStart = WorkspaceRailPage(count: apps.count, start: _desktop3DRailStart).revealing(index)
            }
            windowManager.bringToFront(win.id)
            windowManager.focusedWindowId = win.id
        }
        _desktop3DPublishCamera()
    }

    /// Escape: nothing chosen, everything back where it stood.
    func _desktop3DSwitcherCancel() {
        guard let sw = _desktop3DSwitcher else { return }
        _desktop3DSwitcher = nil
        for (id, pose) in sw.before {
            if let w = windowManager.windows.first(where: { $0.id == id }) { _desktop3DTween(w, to: pose) }
        }
        _desktop3DLog("switcher cancel")
        setState {}
    }

    // MARK: The camera

    var _camera3D: Camera3D {
        get {
            let id = _desktop3DViewId
            if let c = _cameras3D[id] { return c }
            return _desktop3DHomeCamera(_desktop3DHost)
        }
        set { _cameras3D[_desktop3DViewId] = newValue }
    }

    /// The camera as this frame should see it: folded back toward the
    /// home spot by the enter/leave tween. At t = 0 it IS the home spot —
    /// the one place where the picture fills the view — so leaving 3D
    /// walks the viewer back to their desk however far they had wandered,
    /// and the flat desktop it lands on is exact rather than approximate.
    func _desktop3DEffectiveCamera(_ t: Double) -> Camera3D {
        let c = _desktop3DTweenCamera(t)
        return t > 0 ? _desktop3DLeaned(c, t) : c
    }

    /// The camera the tween puts the viewer at, before the lean: from the
    /// dolly start (the home spot, or the world's dolly length behind it)
    /// to wherever they are standing. Entering, that is a glide up to the
    /// home spot; leaving, it walks them back from wherever they wandered.
    func _desktop3DTweenCamera(_ t: Double) -> Camera3D {
        let start = _desktop3DDollyStart(_desktop3DHost)
        guard t > 0 else { return start }
        if t >= 1 { return _camera3D }
        let c = _camera3D
        return Camera3D(x: start.x + (c.x - start.x) * t,
                        y: start.y + (c.y - start.y) * t,
                        z: start.z + (c.z - start.z) * t,
                        yaw: start.yaw + (c.yaw - start.yaw) * t,
                        pitch: start.pitch + (c.pitch - start.pitch) * t)
    }

    // MARK: The lean — parallax from the pointer

    /// A monitor shows one image to a still head, so the depth cues two
    /// eyes and a moving head would give are both gone. What is left is
    /// MOTION parallax, and the pointer is the only thing that moves.
    ///
    /// So the eye leans a few centimetres toward the pointer and keeps
    /// looking at the same spot. That last part is what makes it parallax
    /// rather than a pan: turning the camera slides everything together
    /// and reads as a wobble, while TRANSLATING it slides the near things
    /// against the far ones — the floor against the back wall, a near
    /// window against a far one — which is the whole cue.
    ///
    /// How far the eye leans at the edge of the screen, in metres. Head
    /// sway when someone leans to see around something is 5-15 cm; this is
    /// the quiet end of that, because the pointer reaches the edge far
    /// more often than a head does.
    static let k3DLeanX = 0.055
    static let k3DLeanY = 0.035
    /// What the eye keeps its gaze on while it leans: the FAR WALL, not
    /// the arc the windows sit on.
    ///
    /// This is the whole difference between parallax and a wobble, and it
    /// was measured the wrong way round first. Leaning by `s` slides a
    /// thing at distance `d` across the screen by `focal·s/d`, and turning
    /// back toward the pivot slides everything by a uniform `focal·s/pivot`
    /// the other way — so the net motion goes as `1/pivot − 1/d`, and
    /// anything NEARER than the pivot moves one way while anything beyond
    /// it moves the other. Pivot on the arc (3.7 m) and every piece of
    /// furniture in the room is beyond it, so the far wall swung 3.7× as
    /// far as the near sofa: the exact inverse of what leaning does, and
    /// it reads as the room sliding rather than the eye moving.
    ///
    /// Pivot on the wall instead and the wall holds still while the room
    /// swings across it, near things most — which is what a head actually
    /// sees. Measured at the end of Phase 5.
    static let k3DLeanPivotMin = 3.0
    /// Seconds for the lean to cover most of the distance to a new
    /// pointer position. Long enough that the scene glides rather than
    /// snapping to every jitter, short enough that it is not lag.
    static let k3DLeanTau = 0.11
    /// Below this, the lean has arrived: stop the ticker rather than
    /// rebuild the window stack forever for motion nobody can see.
    static let k3DLeanSettled = 0.002

    /// Apply the current lean to a camera. Scaled by the enter/leave
    /// tween, so the flat desktop never leans and entering 3D brings the
    /// parallax up with everything else.
    func _desktop3DLeaned(_ c: Camera3D, _ t: Double) -> Camera3D {
        let s = _lean3D.x * Self.k3DLeanX * t
        // Screen y runs down; leaning toward the pointer means the eye
        // drops when the pointer is low.
        let u = -_lean3D.y * Self.k3DLeanY * t
        guard s != 0 || u != 0 else { return c }
        var out = c
        // Right of the camera is (cos yaw, 0, sin yaw): forward is
        // (sin yaw, 0, -cos yaw), the same convention walking uses.
        out.x += cos(c.yaw) * s
        out.z += sin(c.yaw) * s
        out.y += u
        // Turn back toward the pivot by the small angle the step subtends,
        // so the spot being looked at stays put. Lean right, turn left.
        // The picture wall is at z = 0, so the eye's own z IS its distance
        // to what it is looking at, and walking toward the wall shortens
        // the lever exactly as it should.
        let pivot = max(Self.k3DLeanPivotMin, c.z)
        out.yaw -= s / pivot
        out.pitch -= u / pivot
        return out
    }

    /// Called from the root Listener on every pointer event. Cheap and
    /// silent unless the room is open: it only records where the lean is
    /// heading, and the ticker does the moving.
    func _desktop3DNotePointer() {
        guard _desktop3DActive else { return }
        // Frozen while a button is down. A window being dragged should
        // follow the pointer and nothing else; a scene that leans under
        // the drag makes the target move as you reach for it.
        guard _lastButtons == 0 else { return }
        let host = _desktop3DHost
        let f = (x: (_lastPointer.dx - host.left) / max(1, host.width),
                 y: (_lastPointer.dy - host.top) / max(1, host.height))
        let want = (x: max(-1, min(1, (f.x - 0.5) * 2)),
                    y: max(-1, min(1, (f.y - 0.5) * 2)))
        guard abs(want.x - _lean3DTarget.x) > 0.001
                || abs(want.y - _lean3DTarget.y) > 0.001 else { return }
        _lean3DTarget = want
        _desktop3DStartLean()
    }

    /// Ease the lean toward the pointer, one step per frame, and stop as
    /// soon as it has arrived. Every tick that moves rebuilds the window
    /// stack (the windows ride the same eye as the room), which is why
    /// this must stop rather than idle.
    func _desktop3DStartLean() {
        if _lean3DTicker == nil {
            _lean3DTicker = createTicker { [weak self] elapsed in
                guard let self else { return }
                let now = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) * 1e-18
                let dt = max(0, min(0.1, now - self._lean3DClock))
                self._lean3DClock = now
                guard self._desktop3DActive else {
                    self._lean3DTicker?.stop()
                    self._lean3D = (0, 0)
                    self._lean3DTarget = (0, 0)
                    return
                }
                var settled = true
                self._forEachDesktop3DOutput {
                    let k = 1 - exp(-dt / Self.k3DLeanTau)
                    var next = (x: self._lean3D.x + (self._lean3DTarget.x - self._lean3D.x) * k,
                                y: self._lean3D.y + (self._lean3DTarget.y - self._lean3D.y) * k)
                    let done = abs(next.x - self._lean3DTarget.x) < Self.k3DLeanSettled
                        && abs(next.y - self._lean3DTarget.y) < Self.k3DLeanSettled
                    if done { next = self._lean3DTarget } else { settled = false }
                    self.setState { self._lean3D = next }
                }
                if settled { self._lean3DTicker?.stop() }
                self._desktop3DPublishCamera()
            }
        }
        if !(_lean3DTicker?.isActive ?? false) {
            _lean3DClock = 0
            _ = _lean3DTicker?.start()
        }
    }

    /// World -> view: undo the camera's place and heading. The camera
    /// looks along (sin yaw, 0, -cos yaw) — what walking, stepping up and
    /// the room renderer all use — and with the SDK's rotation matrices
    /// that is rotationY(+yaw), not the -yaw the words "undo the heading"
    /// suggest. The two signs were mirrored here for as long as every pane
    /// faced straight down the hall (yaw 0 either way); the first pane on
    /// a side wall vanished behind the near plane while the room showed
    /// it dead ahead. Checked against EnvironmentRenderer.view numerically.
    static func _view(_ c: Camera3D) -> Matrix4 {
        var m = Matrix4.rotationX(c.pitch)
        m.multiply(Matrix4.rotationY(c.yaw))
        m.multiply(Matrix4.translationValues(-c.x, -c.y, -c.z))
        return m
    }

    /// View -> what `Transform` wants: x and y scaled by the focal length,
    /// w carrying the distance, so the engine's own divide IS the
    /// perspective divide. Screen y runs down, world y runs up.
    ///
    /// The z row has to be a real projection row even though nothing reads
    /// the z: with a trivial one the matrix is SINGULAR (two rows differing
    /// by a sign), and `RenderTransform` neither paints nor hit-tests a
    /// matrix it cannot invert — every window simply vanishes, with no
    /// error anywhere.
    static func _screenFromView(focal: Double) -> Matrix4 {
        let near = 0.05, far = 200.0
        var p = Matrix4.zero()
        p.setEntry(0, 0, focal)
        p.setEntry(1, 1, -focal)
        p.setEntry(2, 2, -(far + near) / (far - near))
        p.setEntry(2, 3, -2 * far * near / (far - near))
        p.setEntry(3, 2, -1)
        return p
    }

    // MARK: The pose

    /// Where a window lands on screen: the full projection · view · model
    /// chain, over coordinates centred on the host's centre (the same
    /// convention `Transform`'s `origin` is given).
    ///
    /// The tween is in the WORLD, not on the matrix: at t the window is
    /// interpolated between the pose that reproduces its 2D rect exactly
    /// and the pose it has in the room, so entering 3D lifts each window
    /// off the flat desktop from precisely where it was.
    func _desktop3DPlacement(rect: Rect, t: Double, camera: Camera3D,
                             pose: WindowPose3D) -> Desktop3DPlacement {
        let host = _desktop3DHost
        guard host.width > 0, host.height > 0, t > 0 else { return .flat }
        let p = _desktop3DLerpPose(rect: rect, host: host, t: t, pose: pose)

        // Turned away from the viewer: a pane has one side.
        let n = Vector3(sin(p.yaw), 0, cos(p.yaw))
        let toCam = Vector3(camera.x - p.x, camera.y - p.y, camera.z - p.z)
        if n.dot(toCam) <= 0.02 { return .hidden }

        let focal = _desktop3DFocalPx(host)
        let s = Self.k3DMetresPerPx
        // The window's own centre, in the coordinates the matrix is given.
        let wcx = rect.center.dx - host.center.dx
        let wcy = rect.center.dy - host.center.dy

        var m = Self._screenFromView(focal: focal)
        m.multiply(Self._view(camera))
        m.multiply(Matrix4.translationValues(p.x, p.y, p.z))
        m.multiply(Matrix4.rotationY(p.yaw))
        m.multiply(Matrix4.diagonal3Values(s * p.scale, -s * p.scale, s * p.scale))
        m.multiply(Matrix4.translationValues(-wcx, -wcy, 0))

        // Near plane, on the four corners. Either the whole pane is in
        // front of the camera or it is not drawn.
        let l = rect.left - host.center.dx, r = rect.right - host.center.dx
        let tp = rect.top - host.center.dy, b = rect.bottom - host.center.dy
        let row3 = m.getRow(3)
        for (x, y) in [(l, tp), (r, tp), (l, b), (r, b)] {
            if row3.x * x + row3.y * y + row3.w <= 0.25 { return .hidden }
        }
        return .posed(m, host.center)
    }

    /// The window's place this frame: between the pose that reproduces
    /// its flat rect and the pose it has in the room.
    ///
    /// In a world entered by dolly the windows move on t², so they stay
    /// on the desktop while the world comes up and the glide begins, and
    /// take their places in the square as the viewer arrives — and,
    /// leaving, come home first while the world is still there.
    func _desktop3DLerpPose(rect: Rect, host: Rect, t: Double,
                            pose: WindowPose3D) -> WindowPose3D {
        let flat = _desktop3DFlatPose(rect: rect, host: host, camera: _desktop3DTweenCamera(t))
        let target = pose.placed ? pose : flat
        let k = (_desktop3DWorld?.cameraDolly ?? 0) > 0 ? t * t : t
        return WindowPose3D(
            x: flat.x + (target.x - flat.x) * k,
            y: flat.y + (target.y - flat.y) * k,
            z: flat.z + (target.z - flat.z) * k,
            yaw: flat.yaw + (target.yaw - flat.yaw) * k,
            scale: 1 + (target.scale - 1) * k,
            placed: true)
    }

    /// How far the camera is from a window's pane — what the far-to-near
    /// draw order sorts on, since the layer tree has no z-buffer between
    /// its children.
    func _desktop3DDistance(rect: Rect, t: Double, camera: Camera3D,
                            pose: WindowPose3D) -> Double {
        let host = _desktop3DHost
        let p = _desktop3DLerpPose(rect: rect, host: host, t: t, pose: pose)
        let dx = camera.x - p.x, dy = camera.y - p.y, dz = camera.z - p.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    // MARK: Walking

    /// True when the keyboard should drive the camera rather than a
    /// window: the room is open and nothing has the keyboard. Clicking a
    /// window takes the keys; clicking the room gives them back.
    var _desktop3DWalking: Bool {
        _desktop3DOn && _desktop3DT > 0 && windowManager.focusedWindowId == nil
    }

    /// One step of the camera, from a key. Returns true if the key was
    /// ours. HID usage codes, like the rest of the shortcut table.
    ///
    /// `forced` is Alt held: the camera answers even while a window has
    /// the keyboard, because otherwise the room is unreachable in
    /// practice — something is focused almost all of the time.
    func _desktop3DKey(_ usage: Int, fast: Bool, forced: Bool = false) -> Bool {
        guard _desktop3DOn, _desktop3DT > 0 else { return false }
        guard forced || _desktop3DWalking else { return false }
        var c = _camera3D
        let step = Self.k3DStep * (fast ? 2.5 : 1)
        let turn = Self.k3DTurn * (fast ? 2.5 : 1)
        if _desktop3DOrrery, let w = _desktop3DWorld {
            // Round the hub, not through it: the keys move the viewer on
            // a circle about the sun, always facing it.
            var o = _orbit3D ?? (theta: 0.0, radius: w.cameraRadius, height: w.cameraHeight)
            switch usage {
            case 0x50, 0x14, 0x04: o.theta -= turn                        // Left, Q, A
            case 0x4F, 0x08, 0x07: o.theta += turn                        // Right, E, D
            case 0x1A, 0x52:       o.radius -= step                       // W, Up: closer
            case 0x16, 0x51:       o.radius += step                       // S, Down: away
            case 0x15:             o.height += step                       // R
            case 0x09:             o.height -= step                       // F
            case 0x4A:             o = (0, w.cameraRadius, w.cameraHeight) // Home
            case 0x2C:             return _desktop3DStepUp()              // Space
            default:               return false
            }
            o.radius = min(14, max(1.0, o.radius))
            o.height = min(4, max(-2, o.height))
            _orbit3D = o
            setState { _camera3D = _desktop3DOrbitCamera(o) }
            _desktop3DPublishCamera()
            return true
        }
        // Forward is where the camera is looking, flattened: walking, not
        // flying, unless the rise/sink keys are used.
        let fx = sin(c.yaw), fz = -cos(c.yaw)
        switch usage {
        case 0x1A, 0x52: c.x += fx * step; c.z += fz * step     // W, Up
        case 0x16, 0x51: c.x -= fx * step; c.z -= fz * step     // S, Down
        case 0x04:       c.x += fz * step; c.z -= fx * step     // A, strafe
        case 0x07:       c.x -= fz * step; c.z += fx * step     // D, strafe
        case 0x50, 0x14: c.yaw -= turn                          // Left, Q
        case 0x4F, 0x08: c.yaw += turn                          // Right, E
        case 0x15:       c.y += step                            // R, rise
        case 0x09:       c.y -= step                            // F, sink
        case 0x4A:                                              // Home
            c = _desktop3DHomeCamera(_desktop3DHost)
        case 0x2C:       return _desktop3DStepUp()               // Space
        default:         return false
        }
        _desktop3DLog("key \(usage) -> \(c.x),\(c.z) yaw \(c.yaw)")
        if let w = _desktop3DWorld, w.kind == .voxel {
            // On foot: the eye rides the ground, and the world has edges.
            let x0 = Double(w.heightOrigin.x) + 1, x1 = Double(w.heightOrigin.x + w.heightSize.x) - 1
            let z0 = Double(w.heightOrigin.z) + 1, z1 = Double(w.heightOrigin.z + w.heightSize.z) - 1
            if let nav = w.navigation {
                if usage != 0x4A { // Home deliberately resets to the exported spawn.
                    let at = nav.move(x: _camera3D.x, z: _camera3D.z,
                                      dx: c.x - _camera3D.x, dz: c.z - _camera3D.z)
                    c.x = at.x; c.z = at.z
                }
                c.y = w.ground(c.x, c.z) + nav.eye_height
            } else {
                c.x = min(x1, max(x0, c.x))
                c.z = min(z1, max(z0, c.z))
                c.y = w.ground(c.x, c.z) + w.eyeHeight + w.cameraHeight
            }
            c.pitch = min(1.2, max(-1.2, c.pitch))
        } else {
            // Stay inside the room, and out of the walls.
            let m = 0.45
            c.x = min(Room3D.halfW - m, max(-Room3D.halfW + m, c.x))
            c.y = min(Room3D.height - 0.3, max(0.5, c.y))
            c.z = min(Room3D.depth - m, max(m, c.z))
            c.pitch = min(1.2, max(-1.2, c.pitch))
        }
        setState { _camera3D = c }
        _desktop3DPublishCamera()
        return true
    }

    /// Walk up to the window most nearly in front of the viewer and stand
    /// square on at the distance where its pixels are its pixels. This is
    /// the answer to the oldest objection to a 3D desktop — that
    /// perspective-sampled text is unusable — and it is an answer a room
    /// can give and a flat desktop cannot: you step up to the thing.
    @discardableResult
    func _desktop3DStepUp() -> Bool {
        let host = _desktop3DHost
        let c = _camera3D
        let fx = sin(c.yaw), fz = -cos(c.yaw)
        var best: (WindowInfo, Double)? = nil
        for win in windowManager.visibleWindows where win.pose3D.placed && _desktop3DIsShown(win) {
            let p = win.pose3D
            let dx = p.x - c.x, dz = p.z - c.z
            let len = (dx * dx + dz * dz).squareRoot()
            guard len > 0.01 else { continue }
            let facing = (dx * fx + dz * fz) / len       // 1 = dead ahead
            guard facing > 0.2 else { continue }
            let score = facing / (1 + len * 0.15)
            if best == nil || score > best!.1 { best = (win, score) }
        }
        _desktop3DLog("step up: \(windowManager.visibleWindows.count) windows, "
                      + "\(windowManager.visibleWindows.filter { $0.pose3D.placed }.count) placed, "
                      + "best \(best?.0.title ?? "none")")
        guard let winner = best?.0 else { return false }
        _desktop3DStepUp(to: winner)
        return true
    }

    /// Whether a window is further off than reading distance — past 1.3x
    /// the 1:1 spot — so that a click on it means "take me there" rather
    /// than a click on its content.
    func _desktop3DFarFromPane(_ win: WindowInfo) -> Bool {
        let host = _desktop3DHost
        guard win.pose3D.placed else { return false }
        let d1 = _desktop3DFocalPx(host) * Self.k3DMetresPerPx
        let c = _camera3D, p = win.pose3D
        let dx = p.x - c.x, dz = p.z - c.z
        return (dx * dx + dz * dz).squareRoot() > d1 * 1.3
    }

    /// Stand square in front of one window at its 1:1 distance, and give
    /// it the focus. In the orrery this is also what a click on a moon
    /// does: the moon grows to a window and the viewer steps up to it.
    func _desktop3DStepUp(to winner: WindowInfo) {
        let previousView = _desktop3DViewOverride
        _desktop3DViewOverride = _desktop3DOutputId(for: winner)
        defer { _desktop3DViewOverride = previousView }
        // On the ring, a click on a window is a choice, not a walk.
        if var sw = _desktop3DSwitcher, let i = sw.ids.firstIndex(of: winner.id) {
            sw.selected = i
            _desktop3DSwitcher = sw
            _desktop3DSwitcherCommit()
            return
        }
        let host = _desktop3DHost
        // Keep the walker on the reviewed route: bring the selected app to
        // reading distance instead of gliding through buildings to its old pose.
        if let world = _desktop3DWorld, world.navigation != nil {
            _desktop3DPopUpWindow(winner, host: host, w: world)
            setState {
                windowManager.bringToFront(winner.id)
                windowManager.focusedWindowId = winner.id
            }
            return
        }
        let p = winner.pose3D
        let d1 = _desktop3DFocalPx(host) * Self.k3DMetresPerPx
        _desktop3DLog("step up to \(winner.title): pose=\(p) cam=\(_camera3D)")
        setState { windowManager.bringToFront(winner.id) }
        // Square on to the pane, at the 1:1 distance, eye on its centre.
        // The pane's normal is (sin yaw, 0, cos yaw) and the camera
        // looks along (sin yaw, 0, -cos yaw), so looking back down the
        // normal is yaw NEGATED — the same number only for a pane that
        // faces straight down the hall, which is all the arc ever made,
        // and which hid this: on a side wall the old value turned the
        // viewer to face the opposite wall.
        _desktop3DGlide(to: Camera3D(x: p.x + sin(p.yaw) * d1, y: p.y,
                                     z: p.z + cos(p.yaw) * d1,
                                     yaw: -p.yaw, pitch: 0))
    }

    /// How long a step-up takes to get there.
    static let k3DGlideMs = 380

    /// Move the viewer to `target` over a short glide rather than a cut,
    /// so a step-up reads as walking there — a cut from across the square
    /// to a window filling the screen reads as nothing happening and then
    /// being somewhere else. Turns the short way round. A new glide
    /// restarts from wherever the last one had got to.
    func _desktop3DGlide(to target: Camera3D) {
        let from = _camera3D
        var to = target
        let dyaw = to.yaw - from.yaw
        to.yaw = from.yaw + atan2(sin(dyaw), cos(dyaw))
        _desktop3DGlidePath = (from, to)
        if _desktop3DGlide == nil {
            let outputId = _desktop3DViewId
            let c = AnimationController(duration: .milliseconds(Self.k3DGlideMs), vsync: self)
            let curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic)
            curve.addListener { [weak self] in
                guard let self else { return }
                let previousView = self._desktop3DViewOverride
                self._desktop3DViewOverride = outputId
                defer { self._desktop3DViewOverride = previousView }
                guard let p = self._desktop3DGlidePath else { return }
                let k = curve.value
                self.setState {
                    self._camera3D = Camera3D(
                        x: p.from.x + (p.to.x - p.from.x) * k,
                        y: p.from.y + (p.to.y - p.from.y) * k,
                        z: p.from.z + (p.to.z - p.from.z) * k,
                        yaw: p.from.yaw + (p.to.yaw - p.from.yaw) * k,
                        pitch: p.from.pitch + (p.to.pitch - p.from.pitch) * k)
                }
                self._desktop3DPublishCamera()
            }
            _desktop3DGlide = c
            _desktop3DGlideCurve = curve
        }
        _desktop3DGlide!.value = 0
        _ = _desktop3DGlide!.forward()
    }

    // MARK: The light

    /// How much of the room's colour a window at the back of the hall
    /// takes. Enough that distance reads; not so much that a window you
    /// might want to glance at stops being legible.
    static let k3DHazeMax = 0.30
    /// How far a window's glass leans from the theme's tint toward the
    /// light actually behind it.
    static let k3DGlassRoomMix = 0.55
    /// The distance at which haze reaches its maximum.
    static let k3DHazeFar = 9.0

    /// What the pane's edge is made of, as the fraction of the light
    /// falling on it that it returns. This is an albedo and it has to be
    /// one: with the edge treated as a perfect reflector, the sun (whose
    /// baked colour runs to 9.9) drove the two lit sides clean past white
    /// and the pane came out with a hard graphic border instead of a
    /// bevel. At 0.55 — anodised metal, near enough — the four sides land
    /// at 0.85, 0.79, 0.31 and 0.21, which is a lit edge and a dark one.
    static let k3DEdgeAlbedo = 0.55

    /// What the baked sky gives a surface facing `n`, in exactly the terms
    /// the room's own shader uses — the nine spherical-harmonic
    /// coefficients, the share of the sky a room can actually see, the
    /// bounce off the floor that no sky supplies, and the sun. Mirrored
    /// rather than shared because the room is drawn on the raster thread
    /// in GLSL and this is one number per window on the platform thread;
    /// if one is ever changed the other has to follow, or the panes will
    /// be lit by a different day than the room they hang in.
    func _desktop3DSkyLight(_ nx: Double, _ ny: Double, _ nz: Double) -> [Double] {
        #if os(Linux)
        guard let sh = _roomAsset?.mesh.sh, sh.count == 27,
              let sun = _roomAsset?.mesh.sunDir,
              let sunCol = _roomAsset?.mesh.sunColour else { return [0.3, 0.3, 0.3] }
        let c1 = 0.429043, c2 = 0.511664, c3 = 0.743125, c4 = 0.886227, c5 = 0.247708
        // How much of the sky this room can see facing that way: the walls
        // block most of it and the windows are where it gets in.
        let toWin = max(-nz, 0)
        let down = min(1, max(0, 0.5 - ny * 0.5))
        let ndl = max(0, nx * Double(sun.0) + ny * Double(sun.1) + nz * Double(sun.2))
        let sunRGB = [Double(sunCol.0), Double(sunCol.1), Double(sunCol.2)]
        let bounceRGB = [1.0, 0.90, 0.76]
        var out = [Double](repeating: 0, count: 3)
        for k in 0..<3 {
            func s(_ i: Int) -> Double { Double(sh[i * 3 + k]) }
            let irr = c1 * s(8) * (nx * nx - ny * ny)
                + c3 * s(6) * nz * nz
                + c4 * s(0) - c5 * s(6)
                + 2 * c1 * (s(4) * nx * ny + s(7) * nx * nz + s(5) * ny * nz)
                + 2 * c2 * (s(3) * nx + s(1) * ny + s(2) * nz)
            let sky = max(0, irr) * (0.17 + 0.62 * toWin) * 0.318
            let bounce = bounceRGB[k] * (0.10 + 0.26 * down) * (0.35 + 0.06 * sunRGB[1])
            out[k] = sky + bounce + sunRGB[k] * ndl * 0.318
        }
        return out
        #else
        return [0.3, 0.3, 0.3]
        #endif
    }

    /// The four edges of a pane at this heading, lit by the room's sky.
    /// The pane hangs in the open with nothing to shadow it, so the sun
    /// term is a plain N·L — the only thing that varies is which way each
    /// edge faces.
    ///
    /// Depends on the pane's YAW and nothing else, so it survives every
    /// step the viewer takes and only changes when the window is moved
    /// around the arc. That matters: this feeds `_windowChildCache`.
    func _desktop3DPaneEdges(yaw: Double)
        -> (top: Color, right: Color, bottom: Color, left: Color) {
        // The pane's normal is (sin yaw, 0, cos yaw), so its right-hand
        // edge faces (cos yaw, 0, -sin yaw) and its top faces straight up.
        let rx = cos(yaw), rz = -sin(yaw)
        func edge(_ nx: Double, _ ny: Double, _ nz: Double) -> Color {
            let l = _desktop3DSkyLight(nx, ny, nz)
            func ch(_ x: Double) -> Double {
                // The room's own filmic shoulder, so an edge in a sun
                // patch rolls off instead of clipping to white.
                let v = x * Self.k3DEdgeAlbedo
                return min(1, max(0, (v / (v + 0.78)) * 1.62))
            }
            // Quantised for the same reason the rest of the light is: an
            // unrounded colour would miss the widget cache forever.
            func q(_ x: Double) -> Double { (x * 32).rounded() / 32 }
            return Color(alpha: 1, red: q(ch(l[0])), green: q(ch(l[1])), blue: q(ch(l[2])))
        }
        return (top: edge(0, 1, 0), right: edge(rx, 0, rz),
                bottom: edge(0, -1, 0), left: edge(-rx, 0, -rz))
    }

    /// The light behind one window: the average colour of the part of the
    /// picture it stands in front of, plus the haze its distance earns.
    /// The sampling point is where the ray from the eye through the
    /// window's centre meets the picture's wall.
    ///
    /// Quantised, because this feeds `_windowChildCache`: an unrounded
    /// colour would miss the cache on every step and rebuild every
    /// window's subtree for a change nobody can see.
    func _desktop3DRoomLight(rect: Rect, t: Double, camera: Camera3D,
                             pose: WindowPose3D) -> RoomLight? {
        #if os(Linux)
        guard t > 0, let grid = _wallpaperLight, grid.cols > 0, grid.rows > 0 else { return nil }
        let host = _desktop3DHost
        guard host.width > 0, host.height > 0 else { return nil }
        let p = _desktop3DLerpPose(rect: rect, host: host, t: t, pose: pose)

        // The view outside is scenery at infinity, so where a pane sits
        // against it depends only on the DIRECTION from the eye — which is
        // its position on screen, in the frame the view exactly fills.
        let tanH = tan(Self.k3DFovX / 2)
        let fwd = (sin(camera.yaw), -cos(camera.yaw))
        let right = (cos(camera.yaw), sin(camera.yaw))
        let dx = p.x - camera.x, dy = p.y - camera.y, dz = p.z - camera.z
        let along = dx * fwd.0 + dz * fwd.1
        var u = 0.5, v = 0.5
        if along > 0.05 {
            let side = dx * right.0 + dz * right.1
            u = 0.5 + (side / along) / (2 * tanH)
            v = 0.5 - (dy / along) / (2 * tanH) * (host.width / host.height)
        }
        let halfU = (rect.width * Self.k3DMetresPerPx) / (2 * max(along, 0.1) * tanH) / 2
        let halfV = halfU
        func cell(_ a: Double, _ n: Int) -> Int { min(n - 1, max(0, Int(a * Double(n)))) }
        let x0 = cell(u - halfU, grid.cols), x1 = cell(u + halfU, grid.cols)
        let y0 = cell(v - halfV, grid.rows), y1 = cell(v + halfV, grid.rows)
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for gy in min(y0, y1)...max(y0, y1) {
            for gx in min(x0, x1)...max(x0, x1) {
                let c = grid.cells[gy * grid.cols + gx]
                r += c.r; g += c.g; b += c.b; n += 1
            }
        }
        guard n > 0 else { return nil }
        // Nothing hazes until it is further off than reading distance.
        let d1 = _desktop3DFocalPx(host) * Self.k3DMetresPerPx
        let dist = _desktop3DDistance(rect: rect, t: t, camera: camera, pose: pose)
        let haze = Self.k3DHazeMax
            * min(1, max(0, (dist - d1) / (Self.k3DHazeFar - d1)))
        func q(_ x: Double) -> Double { (x * 24).rounded() / 24 }
        let edges = _desktop3DPaneEdges(yaw: p.yaw)
        return RoomLight(
            color: Color(alpha: 1.0, red: q(r / n), green: q(g / n), blue: q(b / n)),
            haze: (haze * 40).rounded() / 40,
            separation: (t * 20).rounded() / 20,
            edgeTop: edges.top, edgeRight: edges.right,
            edgeBottom: edges.bottom, edgeLeft: edges.left)
        #else
        return nil
        #endif
    }

    // MARK: The mode

    /// Enter or leave, animated (600 ms) unless told otherwise. The choice
    /// persists like tiling and appearance.
    func _setDesktop3D(_ on: Bool, animated: Bool = true) {
        _desktop3DLog("set on=\(on) animated=\(animated) was on=\(_desktop3DOn) t=\(_desktop3DT) chromeless=\(_desktop3DChromeless)")
        if on == _desktop3DOn, animated { return }
        _desktop3DOn = on
        _desktop3DPersist()
        #if os(Linux)
        linuxProcessAppManager?.broadcastDesktop3D(on: on)
        #endif
        if on {
            // Start from the one spot where the room looks like the flat
            // desktop, and give every window a place in the hall. The room
            // renderer has to exist FIRST: which layout the windows get
            // (the arc, or the walls of the Filament room) is decided by
            // which renderer is there, and on the first entry of a session
            // there was none yet — every window went to the arc, placed
            // for good, and the walls stayed bare.
            _ = _ensureEnvironment()
            _orbit3D = nil
            _camera3D = _desktop3DHomeCamera(_desktop3DHost)
            _desktop3DPlaceWindows()
            // The window that had the keyboard on the flat desktop keeps
            // it: the city shows it in front at full size, so the keys
            // plainly belong to it (Alt + the walking keys still drive the
            // camera). This used to hand the keys to the camera on entry —
            // right when windows stood far off on the arc, and wrong now:
            // "hello" typed on arrival walked the viewer instead. With no
            // window focused the keys are the camera's, as before.
        }
        if !animated {
            setState { _desktop3DT = on ? 1 : 0 }
            _desktop3DPublishCamera()
            if !on { _releaseEnvironment() }
            return
        }
        if _desktop3DController == nil {
            // A world entered by dolly gets a longer tween: the glide is
            // the entrance, and 600 ms of it reads as a lurch.
            let ms = (_desktop3DWorld?.cameraDolly ?? 0) > 0 ? Self.k3DDollyTransitionMs : Self.k3DTransitionMs
            let c = AnimationController(
                duration: .milliseconds(ms), vsync: self)
            let curve = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic)
            curve.addListener { [weak self] in
                guard let self else { return }
                self.setState { self._desktop3DT = curve.value }
                self._desktop3DPublishCamera()
            }
            c.addStatusListener { [weak self] status in
                guard let self, status == .dismissed else { return }
                // Back in 2D: the wallpaper slot already shows the plain
                // texture (t = 0 built above). Let that frame land before
                // the environment's texture goes away under it.
                let work: () -> Void = { [weak self] in
                    guard let self, self._desktop3DT == 0 else { return }
                    self._releaseEnvironment()
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(120),
                    execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
            }
            // A session that comes up with 3D already on (the preference)
            // reaches here at t = 1 with a fresh controller sitting at 0,
            // and a reverse from 0 is a no-op: the scene never came down,
            // and with the orrery's chrome hidden the dock never came
            // back. Start the controller where the tween actually is.
            c.value = _desktop3DT
            _desktop3DController = c
            _desktop3DCurve = curve
        }
        // Make sure the room exists before the first tween frame asks for
        // it — the wallpaper slot swaps to the environment at t > 0.
        if on { _ = _ensureEnvironment() }
        if on { _ = _desktop3DController!.forward() } else { _ = _desktop3DController!.reverse() }
    }

    private static var _desktop3DFile: String { LoginUser.configDir + "/desktop-3d" }

    func _desktop3DPersist() {
        let path = Self._desktop3DFile
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try? (_desktop3DOn ? "on" : "off").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// At launch: come up in whichever mode was chosen, with no transition.
    func _loadDesktop3DPreference() {
        var on = (ProcessInfo.processInfo.environment["STARLING_3D_SPIKE"] ?? "") == "1"
        if let s = try? String(contentsOfFile: Self._desktop3DFile, encoding: .utf8) {
            on = s.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
        }
        _desktop3DOn = on
        _desktop3DT = on ? 1 : 0
    }

    /// Hand the environment what the platform thread decided; it renders
    /// on the raster thread at the next engine frame.
    func _desktop3DPublishCamera() {
        _forEachDesktop3DOutput { _desktop3DPublishCameraOutput() }
    }

    private func _desktop3DPublishCameraOutput() {
        #if os(Linux)
        guard let env = _environment, let registry = drmTextureRegistry,
              let wl = waylandIntegration, environmentTextureId >= 0 else { return }
        let host = _desktop3DHost
        let c = _desktop3DEffectiveCamera(_desktop3DT)
        let canvas = _desktop3DCanvas
        let lens = DesktopSceneLens(width: canvas.width, height: canvas.height,
            focal: _desktop3DFocalPx(host))
        let sky = shellMica ?? Color(alpha: 1, red: 0.55, green: 0.60, blue: 0.70)
        let changed = env.setCamera(EnvironmentCamera(
            t: _desktop3DT, x: c.x, y: c.y, z: c.z, yaw: c.yaw, pitch: c.pitch,
            tanHalfFovX: lens.tanHalfFovX,
            lensShiftX: lens.shiftX, lensShiftY: lens.shiftY,
            lightR: sky.r, lightG: sky.g, lightB: sky.b))
        if changed { registry.markGLTextureDirty(engine: wl.engine, id: environmentTextureId) }
        #endif
    }

    /// The windows as the room renderer should draw them this frame:
    /// every visible window with a client texture, at the pose the layer
    /// tree is about to give its widget, so the two coincide.
    func _desktop3DPublishPanes() {
        _forEachDesktop3DOutput { _desktop3DPublishPanesOutput() }
    }

    private func _desktop3DPublishPanesOutput() {
        #if os(Linux)
        guard let env = _environment as? FilamentRoomRenderer,
              let registry = drmTextureRegistry, let wl = waylandIntegration,
              environmentTextureId >= 0 else { return }
        let host = _desktop3DHost
        let t = _desktop3DT
        let s = Self.k3DMetresPerPx
        let titleH = shellMetrics.titleBarHeight
        var specs: [ScenePane] = []
        let sceneWindows = windowManager.visibleWindows + _desktop3DRailWindows().filter {
            $0.isMinimized && (_desktop3DSwitcher?.ids.contains($0.id) ?? false)
        }
        for win in sceneWindows where !win.isFullscreen && _desktop3DIsShown(win) {
            guard let texId = win.textureId, win.rect.height > titleH else { continue }
            let p = _desktop3DLerpPose(rect: win.rect, host: host, t: t, pose: win.pose3D)
            let k = s * p.scale
            specs.append(ScenePane(
                id: Int64(texId), x: p.x, y: p.y, z: p.z, yaw: p.yaw,
                width: win.rect.width * k, height: win.rect.height * k,
                contentDy: -titleH / 2 * k,
                contentWidth: win.rect.width * k,
                contentHeight: (win.rect.height - titleH) * k,
                // Filament's materials take texture row 0 as the TOP (its
                // default flipUV), the opposite of the engine's external
                // textures — so a buffer the widget flips, the pane does not.
                flipY: !win.flipTextureY,
                focused: win.id == windowManager.focusedWindowId))
        }
        // Previews are scene-only copies: selecting one focuses the real
        // window; no miniature client receives pointer or keyboard input.
        for bay in _desktop3DWorkspaceRails() {
            guard let win = _desktop3DRailWindows()
                .filter({ _desktop3DAppId(of: $0) == bay.app })
                .max(by: { $0.zIndex < $1.zIndex }),
                  let texture = win.textureId, win.rect.width > 0,
                  win.rect.height > titleH else { continue }
            let ratio = win.rect.width / (win.rect.height - titleH)
            let width = min(bay.width, bay.height * ratio)
            let height = width / ratio
            specs.append(ScenePane(id: -Int64(texture) - 1, textureId: Int64(texture),
                x: bay.x, y: bay.y, z: bay.z, yaw: 0,
                width: width, height: height, contentDy: 0,
                contentWidth: width, contentHeight: height,
                flipY: !win.flipTextureY, focused: false))
        }
        if env.setPanes(specs) {
            registry.setSceneMirror(ids: Set(specs.map { $0.textureId ?? $0.id }), target: environmentTextureId)
            registry.markGLTextureDirty(engine: wl.engine, id: environmentTextureId)
        }
        #endif
    }

    // MARK: The orrery

    /// Lay the desktop out round the sun: one planet per open app on a
    /// tilted ring, its windows as moons round it, each moon a small pane
    /// that grows to full size when it has the focus. Recomputed every
    /// build — nothing here is arranged by hand, so the layout is a pure
    /// function of what is open — and handed to the renderer with the
    /// orbs and the labels.
    func _desktop3DLayoutOrrery() {
        _forEachDesktop3DOutput { _desktop3DLayoutOrreryOutput() }
    }

    private func _desktop3DLayoutOrreryOutput() {
        #if os(Linux)
        guard let env = _environment as? FilamentRoomRenderer, env.world.kind == .orrery,
              let registry = drmTextureRegistry, let wl = waylandIntegration,
              environmentTextureId >= 0 else { return }
        let w = env.world
        let windows = windowManager.visibleWindows.filter { !$0.isFullscreen && _desktop3DOutputId(for: $0) == _desktop3DViewId }
        let apps = Array(Set(windows.map { $0.appId })).sorted()
        var orbs: [SceneOrb] = [
            SceneOrb(id: 1, x: w.hub.x, y: w.hub.y, z: w.hub.z, radius: w.sunRadius,
                     r: 1.0, g: 0.80, b: 0.45, glow: 3.0),
        ]
        var labels: [SceneLabel] = []
        for (i, appId) in apps.enumerated() {
            let phi = Double.pi / 2 - 2 * Double.pi * Double(i) / Double(max(apps.count, 1))
            let planet = _desktop3DRingPoint(w, radius: w.planetOrbit, phi: phi)
            let rec = AppRegistry.shared.installedApps.first { $0.id == appId }
            let colour = rec.map { Color(Int($0.color) | 0xFF00_0000) } ?? Color(0xFF6B7280)
            orbs.append(SceneOrb(id: 100 + Int64(i), x: planet.x, y: planet.y, z: planet.z,
                                 radius: w.planetRadius,
                                 r: colour.r, g: colour.g, b: colour.b, glow: 0))
            if let tex = _desktop3DAppLabelTexture(appId) {
                labels.append(SceneLabel(id: tex, texture: tex, x: planet.x, y: planet.y + w.planetRadius + 0.26,
                                         z: planet.z, width: 0.40, height: 0.47))
            }
            let moons = windows.filter { $0.appId == appId }.sorted { $0.id < $1.id }
            for (j, win) in moons.enumerated() {
                let psi = phi + 2 * Double.pi * Double(j) / Double(max(moons.count, 1))
                let m = _desktop3DRingPoint(w, radius: w.moonOrbit, phi: psi, about: planet)
                let focused = win.id == windowManager.focusedWindowId
                // A moon faces out from its planet; the one being used
                // turns to the viewer, who has stepped up to it.
                let cam = _camera3D
                let yaw = focused ? atan2(cam.x - m.x, cam.z - m.z)
                                  : atan2(m.x - planet.x, m.z - planet.z)
                let pose = WindowPose3D(x: m.x, y: m.y, z: m.z, yaw: yaw,
                                        scale: focused ? 1.0 : w.moonScale, placed: true)
                if win.pose3D != pose { win.pose3D = pose }
            }
        }
        var changed = env.setOrbs(orbs)
        if env.setLabels(labels) { changed = true }
        if changed { registry.markGLTextureDirty(engine: wl.engine, id: environmentTextureId) }
        #endif
    }

    /// The square: every open window stands in a ring round the hub at
    /// ground level, facing outward, grouped by app, with the app's
    /// nameplate floating over its group. Recomputed every build, like
    /// the orrery.
    func _desktop3DLayoutVoxel() {
        _forEachDesktop3DOutput { _desktop3DLayoutVoxelOutput() }
        #if os(Linux)
        // The cache belongs to all outputs. An output's own label list must
        // not release a title bar that another scene still displays.
        let liveBars = Set(windowManager.visibleWindows.filter {
            !$0.isFullscreen && $0.pose3D.placed && $0.textureId != nil
        }.map { $0.id })
        if let registry = drmTextureRegistry, let wl = waylandIntegration {
            for id in _sceneTitleBars.keys where !liveBars.contains(id) {
                if let old = _sceneTitleBars[id] {
                    registry.unregisterTexture(engine: wl.engine, id: old.tex)
                }
                _sceneTitleBars[id] = nil
            }
        }
        #endif
    }

    private func _desktop3DLayoutVoxelOutput() {
        #if os(Linux)
        guard let env = _environment as? FilamentRoomRenderer, env.world.kind == .voxel,
              let registry = drmTextureRegistry, let wl = waylandIntegration,
              environmentTextureId >= 0 else { return }
        let w = env.world
        let s = Self.k3DMetresPerPx
        // Where the windows stand is decided when they arrive
        // (_desktop3DPlaceWindows: the arc, or in front of the viewer for
        // a pop-up) and kept; here their nameplates, the pile and the door
        // are laid out round them.
        let windows = windowManager.visibleWindows.filter { !$0.isFullscreen && $0.pose3D.placed && _desktop3DIsShown($0) }
        var labels: [SceneLabel] = []
        // No nameplate over a window: its title bar names it, and with one
        // window on screen (or the ring, where each is read at once) the
        // icon and name floating over the roof said nothing more (user:
        // "I think it's unnecessary"). A hovered brick still wears its name.
        // Each window's title bar, in the scene on its pane — where a brick
        // in front of the window covers it, as it covers the picture.
        let titleH = shellMetrics.titleBarHeight
        for win in windows where win.pose3D.placed && win.textureId != nil {
            guard let tex = _desktop3DTitleBarTexture(win) else { continue }
            let p = win.pose3D
            let k = s * p.scale
            let up = (win.rect.height / 2 - titleH / 2) * k
            // A hair in front of the pane's picture (which is 3 mm off the slab).
            let n = (x: sin(p.yaw), z: cos(p.yaw))
            labels.append(SceneLabel(id: Self.k3DTitleIdBase + tex, texture: tex,
                                     x: p.x + n.x * 0.005, y: p.y + up, z: p.z + n.z * 0.005,
                                     width: win.rect.width * k, height: titleH * k, yaw: p.yaw))
        }
        // The signs: the dock's apps, standing round the near side of the
        // pool. Their key is offset from the nameplates', which share the
        // same textures.
        for s in _desktop3DSigns() {
            guard let tex = _desktop3DWorkspaceRails().isEmpty
                ? _desktop3DAppLabelTexture(s.app)
                : _desktop3DAppFaceTexture(s.app, hovered: s.app == _desktop3DHoveredSign) else { continue }
            labels.append(SceneLabel(id: Self.k3DSignIdBase + tex, texture: tex,
                                     x: s.x, y: s.y, z: s.z, width: s.w, height: s.h, yaw: s.yaw))
        }
        for bay in _desktop3DWorkspaceRails() {
            let count = _desktop3DRailWindows().filter { _desktop3DAppId(of: $0) == bay.app }.count
            if count > 1, let tex = _desktop3DNameTexture("rail-count:\(count)", "\(count)") {
                labels.append(SceneLabel(id: 9_000_000 + Int64(labels.count), texture: tex,
                    x: bay.x + bay.width / 2 - 0.25, y: bay.y + bay.height / 2 + 0.16,
                    z: bay.z + 0.03, width: 0.36, height: 0.36, yaw: 0))
            }
        }
        // The clock tower: the time on each of its four sides, a hair off
        // the stone, redrawn on the minute.
        if let ck = w.clock, let tex = _desktop3DClockTexture() {
            let off = ck.half + 0.01
            for (i, yaw) in [0.0, Double.pi / 2, Double.pi, -Double.pi / 2].enumerated() {
                labels.append(SceneLabel(id: Self.k3DClockIdBase + Int64(i), texture: tex,
                                         x: ck.x + sin(yaw) * off, y: ck.y, z: ck.z + cos(yaw) * off,
                                         width: ck.size, height: ck.size, yaw: yaw))
            }
            _desktop3DScheduleClock()
        }
        // The sculpture: the dock's apps as blocks in a spiral round the
        // post in the pool; the one under the pointer wears its name.
        var blocks: [SceneBlock] = []
        let bricks = _desktop3DSculpture()
        for b in bricks {
            guard let tex = _desktop3DAppFaceTexture(b.app, hovered: b.app == _desktop3DHoveredSign) else { continue }
            blocks.append(SceneBlock(id: Self.k3DBlockIdBase + tex, texture: tex,
                                     x: b.x, y: b.y, z: b.z, yaw: b.yaw, roll: b.roll, size: b.size))
            if b.app == _desktop3DHoveredSign, let name = _desktop3DAppLabelTexture(b.app) {
                // The nameplate stands over the roof, above the brick's
                // column: over the brick itself would be inside the next
                // course, and in front of it would hide its face.
                let roof = bricks.filter { abs($0.x - b.x) < b.size && abs($0.z - b.z) < b.size }
                    .map { $0.y + $0.size / 2 }.max() ?? (b.y + b.size / 2)
                labels.append(SceneLabel(id: Self.k3DSignIdBase + name, texture: name,
                                         x: b.x, y: roof + 0.65, z: b.z, width: 0.8, height: 0.94))
            }
        }
        for (i, c) in _desktop3DControls().enumerated() {
            guard let tex = _desktop3DControlTexture(c.id, hovered: c.id == _desktop3DHoveredSign) else { continue }
            blocks.append(SceneBlock(id: Self.k3DControlIdBase + Int64(i), texture: tex,
                                     x: c.x, y: c.y, z: c.z, yaw: c.yaw, roll: 0, size: c.size))
            if c.id == _desktop3DHoveredSign, let name = _desktop3DNameTexture(c.id, "Back to the desktop") {
                labels.append(SceneLabel(id: Self.k3DSignIdBase + name, texture: name,
                                         x: c.x, y: c.y + c.size / 2 + 0.3, z: c.z, width: 1.2, height: 0.27))
            }
        }
        var changed = env.setOrbs([])
        if env.setBlocks(blocks) { changed = true }
        if env.setLabels(labels.sorted { $0.id < $1.id }) { changed = true }
        if changed { registry.markGLTextureDirty(engine: wl.engine, id: environmentTextureId) }
        #endif
    }

    // MARK: The clock tower

    static let k3DClockIdBase: Int64 = 5_000_000

    /// The clock's face for this minute — a round dial with blocky hour
    /// marks and two hands — in one texture the four faces share. Drawn
    /// into two textures turn and turn about, never freed: a changed
    /// texture id is what makes the labels differ from the frame before,
    /// so the room draws a new frame with the new name bound. Drawing
    /// into ONE texture every minute showed nothing new (equal labels, no
    /// frame — and a picture uploaded into a texture the renderer's own
    /// context had already sampled needs the flush in sceneTexture too);
    /// a FRESH texture every minute, the last freed, vanished on the
    /// second minute (the driver hands a freed name straight back).
    func _desktop3DClockTexture() -> Int64? {
        #if os(Linux)
        guard let registry = drmTextureRegistry, let wl = waylandIntegration else { return nil }
        let now = Date()
        let minute = Int(now.timeIntervalSince1970 / 60)
        if let f = _clockFace, f.minute == minute { return _clockFaceTextures[f.which] }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let h = Double(comps.hour ?? 0), m = Double(comps.minute ?? 0)
        let n = 256, c = 128.0
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        let ink = Paint(); ink.color = Color(0xFF26262B)
        let face = Paint(); face.color = Color(0xFFF3E9D0)
        canvas.drawCircle(Offset(c, c), 124, ink)
        canvas.drawCircle(Offset(c, c), 112, face)
        // Hour marks: squared-off ticks, the quarters longer.
        for i in 0..<12 {
            canvas.save()
            canvas.translate(c, c)
            canvas.rotate(Double(i) * Double.pi / 6)
            let long = i % 3 == 0
            canvas.drawRect(Rect.fromLTWH(long ? -5 : -3.5, -108, long ? 10 : 7, long ? 26 : 16), ink)
            canvas.restore()
        }
        // The hands: 12 o'clock is straight up, and a canvas rotation is
        // clockwise on screen, so the hour hand turns by its share of the
        // dial and the minute hand by its own.
        for (angle, length, width) in [((h.truncatingRemainder(dividingBy: 12) + m / 60) / 12, 60.0, 14.0),
                                       (m / 60, 90.0, 10.0)] {
            canvas.save()
            canvas.translate(c, c)
            canvas.rotate(angle * 2 * Double.pi)
            canvas.drawRect(Rect.fromLTWH(-width / 2, -length, width, length + 16), ink)
            canvas.restore()
        }
        canvas.drawCircle(Offset(c, c), 9, ink)
        canvas.drawCircle(Offset(c, c), 3.5, face)
        let picture = recorder.endRecording()
        guard let image = picture.toImageSync(width: n, height: n) else { return nil }
        defer { image.dispose() }
        guard let bytes = try? image.toByteData(format: .rawRgba) else { return nil }
        if _clockFaceTextures.isEmpty {
            _clockFaceTextures = [registry.registerTexture(engine: wl.engine),
                                  registry.registerTexture(engine: wl.engine)]
        }
        let which = _clockFace.map { ($0.which + 1) % 2 } ?? 0
        let id = _clockFaceTextures[which]
        bytes.withUnsafeBytes { raw in
            registry.updatePixelData(engine: wl.engine, id: id, data: raw.baseAddress!, width: n, height: n)
        }
        _clockFace = (minute, which)
        _desktop3DLog(String(format: "clock %02d:%02d", Int(h), Int(m)))
        return id
        #else
        return nil
        #endif
    }

    /// One wake just after the next minute boundary, while the city is
    /// up: the build it asks for redraws the face and books the wake
    /// after. The desktop's own clock keeps time the same way (ShellClock):
    /// a wake a minute is the whole idle cost, and none once 3D is off.
    func _desktop3DScheduleClock() {
        guard !_clockWakePending else { return }
        _clockWakePending = true
        let t = Date().timeIntervalSince1970
        let delay = 60 - t.truncatingRemainder(dividingBy: 60) + 0.05
        let fire: () -> Void = { [weak self] in
            guard let self else { return }
            self._clockWakePending = false
            guard self._desktop3DActive, self._desktop3DWorld?.clock != nil else {
                self._desktop3DLog("clock: minute wake with the city down, no more")
                return
            }
            self.setState {}
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay,
                                      execute: unsafeBitCast(fire, to: (@Sendable () -> Void).self))
    }

    // MARK: The signs — the dock, standing in the square

    static let k3DSignIdBase: Int64 = 1_000_000
    /// The ring the signs stand on, as a fraction of the windows' ring:
    /// round the pool, inside the arc the windows make.
    static let k3DSignRing = 0.6
    static let k3DSignWidth = 0.8
    static let k3DSignHeight = 0.94        // the label texture's 256x300
    static let k3DSignHoverScale = 1.2

    /// A sign to the next, centre to centre; the most in one row before
    /// the row is wider than the view from the entrance; and where the
    /// rows behind stand — up and back, like seats, so each row shows
    /// over the one in front.
    static let k3DSignPitch = 1.25
    static let k3DSignsPerRow = 6
    static let k3DSignRowRise = 1.05
    static let k3DSignRowBack = 0.7
    /// On the tower: the signs' floor pitch, the first floor above the
    /// pool, and how far in front of the wall they hang.
    static let k3DTowerFloor = 1.0
    static let k3DTowerFirstFloor = 1.5
    static let k3DTowerSignOut = 0.04
    /// The first window's angle from dead ahead, so it clears the tower.
    static let k3DTowerClearDeg = 32.0

    // MARK: The title bars, in the scene

    static let k3DTitleIdBase: Int64 = 4_000_000

    /// A window's block title bar as a texture for the scene: drawn again
    /// only when its title, focus, width or hovered block changes.
    func _desktop3DTitleBarTexture(_ win: WindowInfo) -> Int64? {
        #if os(Linux)
        guard let registry = drmTextureRegistry, let wl = waylandIntegration else { return nil }
        let focused = win.id == windowManager.focusedWindowId
        let hovered = _sceneTitleHover[win.id]
        let width = win.rect.width
        let key = "\(win.title)|\(focused)|\(Int(width))|\(hovered.map(String.init) ?? "-")"
        if let cur = _sceneTitleBars[win.id], cur.key == key { return cur.tex }
        let scale = 2.0
        let w = Int(width * scale), h = Int(shellMetrics.titleBarHeight * scale)
        guard w > 0, h > 0 else { return nil }
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        _BlockyTitleBarState.paint(canvas, width: width, tile: _worldFrameTile, title: win.title,
                             focused: focused, hovered: hovered, scale: scale)
        let picture = recorder.endRecording()
        guard let image = picture.toImageSync(width: w, height: h) else { return nil }
        defer { image.dispose() }
        guard let bytes = try? image.toByteData(format: .rawRgba) else { return nil }
        let tex = registry.registerTexture(engine: wl.engine)
        bytes.withUnsafeBytes { raw in
            registry.updatePixelData(engine: wl.engine, id: tex, data: raw.baseAddress!, width: w, height: h)
        }
        if let old = _sceneTitleBars[win.id] { registry.unregisterTexture(engine: wl.engine, id: old.tex) }
        _sceneTitleBars[win.id] = (key, tex)
        return tex
        #else
        return nil
        #endif
    }

    // MARK: The way out

    static let k3DControlIdBase: Int64 = 3_000_000
    static let k3DControlExit = "@exit"
    static let k3DControlSize = 0.7

    /// One block on the pool's front rim, to the right of the way in: a
    /// door out of the world, back to the flat desktop. The chromeless
    /// world has no status bar to keep such a thing in, and the keyboard
    /// is not a way anyone finds. (A power block stood beside it for an
    /// afternoon; shutting the machine down is the desk's business.)
    func _desktop3DControls() -> [(id: String, x: Double, y: Double, z: Double, yaw: Double, size: Double)] {
        guard let w = _desktop3DWorld, w.kind == .voxel else { return [] }
        if !w.workspaceRail.isEmpty {
            return [(Self.k3DControlExit, 11.8, w.hub.y + 0.45, 7, 0, Self.k3DControlSize)]
        }
        guard let sc = w.sculpture else { return [] }
        let s = Self.k3DControlSize
        return [(Self.k3DControlExit, sc.x + 2.4, sc.base + s / 2, sc.z + 3.5, 0, s)]
    }

    /// The door block's face: a dark block, a door frame in white and an
    /// arrow leaving through it.
    func _desktop3DControlTexture(_ id: String, hovered: Bool = false) -> Int64? {
        #if os(Linux)
        let key = hovered ? id + "#hover" : id
        if let t = _appFaceTextures[key] { return t }
        guard let registry = drmTextureRegistry, let wl = waylandIntegration else { return nil }
        let s = 128
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        let paint = Paint()
        _desktop3DPaintCitySign(canvas, color: Color(0xFF355E58), hovered: hovered)
        paint.style = .stroke
        paint.strokeWidth = 9
        paint.color = Color(0xFFFFE9BE)
        let door = Path()
        door.moveTo(84, 30); door.lineTo(40, 30); door.lineTo(40, 98); door.lineTo(84, 98)
        canvas.drawPath(door, paint)
        canvas.drawLine(Offset(58, 64), Offset(104, 64), paint)
        paint.style = .fill
        let head = Path()
        head.moveTo(112, 64); head.lineTo(94, 50); head.lineTo(94, 78); head.close()
        canvas.drawPath(head, paint)
        let picture = recorder.endRecording()
        guard let image = picture.toImageSync(width: s, height: s) else { return nil }
        defer { image.dispose() }
        guard let bytes = try? image.toByteData(format: .rawRgba) else { return nil }
        let tex = registry.registerTexture(engine: wl.engine)
        bytes.withUnsafeBytes { raw in
            registry.updatePixelData(engine: wl.engine, id: tex, data: raw.baseAddress!, width: s, height: s)
        }
        _appFaceTextures[key] = tex
        return tex
        #else
        return nil
        #endif
    }

    /// A name alone, white over a hard shadow, for a nameplate over a
    /// control block (an app's plate carries its tile; these have none).
    func _desktop3DNameTexture(_ key: String, _ title: String) -> Int64? {
        #if os(Linux)
        if let t = _appLabelTextures[key] { return t }
        guard let registry = drmTextureRegistry, let wl = waylandIntegration else { return nil }
        let badge = key.hasPrefix("rail-count:")
        let w = badge ? 72 : 320, h = 72
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        if badge {
            let background = Paint(); background.color = Color(0xFF574028)
            canvas.drawCircle(Offset(36, 36), 35, background)
        }
        for (dx, dy, c) in [(3.0, 3.0, Color(0xC0000000)), (0.0, 0.0, Color(0xFFFFFFFF))] {
            let pb = NativeParagraphBuilder(ParagraphStyle(textAlign: .center, fontSize: 30, fontWeight: .w600))
            pb.pushStyle(TextStyle(color: c, fontWeight: .w600, fontSize: 30))
            pb.addText(title)
            let para = pb.build()
            para.layout(ParagraphConstraints(width: Double(w)))
            canvas.drawParagraph(para, Offset(dx, 14 + dy))
        }
        let picture = recorder.endRecording()
        guard let image = picture.toImageSync(width: w, height: h) else { return nil }
        defer { image.dispose() }
        guard let bytes = try? image.toByteData(format: .rawRgba) else { return nil }
        let tex = registry.registerTexture(engine: wl.engine)
        bytes.withUnsafeBytes { raw in
            registry.updatePixelData(engine: wl.engine, id: tex, data: raw.baseAddress!, width: w, height: h)
        }
        _appLabelTextures[key] = tex
        return tex
        #else
        return nil
        #endif
    }

    /// The door pressed: leave the world for the flat desktop.
    func _desktop3DControlActivate(_ id: String) {
        _desktop3DLog("control \(id)")
        if id == Self.k3DControlExit { _setDesktop3D(false) }
    }

    // MARK: The sculpture — the dock as a spiral of blocks

    static let k3DBlockIdBase: Int64 = 2_000_000
    static let k3DSculptSize = 0.9
    /// How far the brick under the pointer comes out of the wall.
    static let k3DSculptHoverOut = 0.14
    /// How far in front of the wall a dragged brick rides.
    static let k3DSculptDragOut = 0.4
    /// Bricks with weight: gravity, how fast a tipping brick turns, how
    /// far a brick's centre may sit past the edge of what holds it before
    /// it tips, and how far from the pool's middle a brick may go.
    static let k3DBrickGravity = 9.8
    static let k3DBrickTipRate = 4.5
    static let k3DBrickTipMargin = 0.02
    /// How high a carried brick rides over the ground it is pointed at.
    static let k3DBrickCarry = 0.3

    /// The dock's apps as bricks with weight, standing in the pool. They
    /// start as a small building — courses of k, each course a quarter
    /// brick over from the one below, so every brick rests three
    /// quarters on the one beneath and the end bricks overhang a
    /// quarter, which stands — and from then on they are bodies: pull
    /// one out and what it held up tips off and falls; drop one and it
    /// lands on whatever is under it. A new app drops in from above.
    /// The one under the pointer comes out of the wall a little; a
    /// click on it opens its app.
    func _desktop3DSculpture() -> [(app: String, x: Double, y: Double, z: Double, yaw: Double, roll: Double, size: Double)] {
        guard let w = _desktop3DWorld, w.kind == .voxel, let sc = w.sculpture else { return [] }
        guard w.workspaceRail.isEmpty else { return [] }
        let apps = _dockDisplayApps.filter { $0 != "launcher" }
        guard !apps.isEmpty else { return [] }
        let s = Self.k3DSculptSize
        _desktop3DSettleBricks(apps, sc: sc)
        let host = _desktop3DHost
        return apps.compactMap { app in
            guard var b = _desktop3DBricks[app] else { return nil }
            if b.mode == .held, let d = _desktop3DBrickDrag, d.app == app {
                // The brick being carried rides the ground the pointer
                // points at, a little above it — anywhere in the city.
                let cam = _desktop3DEffectiveCamera(_desktop3DT)
                if let p = _desktop3DBrickCarryPoint(d.at, camera: cam, host: host, sc: sc, w: w) {
                    b.x = p.x; b.y = p.y; b.z = p.z; b.roll = 0; b.yaw = 0
                    _desktop3DBricks[app] = b
                }
                return (app, b.x, b.y, b.z, 0, 0, s)
            }
            // (The one under the pointer is lit, not moved: a brick that
            // came toward the viewer went into the brick beside it.)
            return (app, b.x, b.y, b.z, b.yaw, b.roll, s)
        }
    }

    /// The pool: a raised block, seven metres square and a metre high,
    /// whose blocks run from −3 to +4 about the hub (a block covers
    /// [i, i + 1)), so its centre is half a metre past the hub.
    static let k3DPoolHalf = 3.5
    static let k3DPoolOffset = 0.5
    func _desktop3DPoolCentre(_ sc: (x: Double, z: Double, radius: Double, base: Double)) -> (x: Double, z: Double) {
        (sc.x + Self.k3DPoolOffset, sc.z + Self.k3DPoolOffset)
    }
    func _desktop3DOverPool(_ x: Double, _ z: Double, sc: (x: Double, z: Double, radius: Double, base: Double)) -> Bool {
        let c = _desktop3DPoolCentre(sc)
        return max(abs(x - c.x), abs(z - c.z)) <= Self.k3DPoolHalf
    }

    /// The ground a brick stands on at a spot: the water's top over the
    /// pool, the walkable surface elsewhere.
    func _desktop3DBrickGround(_ x: Double, _ z: Double, sc: (x: Double, z: Double, radius: Double, base: Double), w: World3D) -> Double {
        if _desktop3DOverPool(x, z, sc: sc) { return sc.base }
        return w.ground(x, z)
    }

    /// What of a brick's footprint the ground holds up, as intervals in
    /// x and z, or nil when the ground is not at its foot. On the pool:
    /// the footprint within the pool's square. On the plaza: the
    /// footprint less what hangs over the pool's square — which is the
    /// rim's wall there, not the plaza. So a brick set down on the rim's
    /// edge tips to whichever side its centre is on, as one would.
    func _desktop3DGroundSupport(_ b: BrickBody, sc: (x: Double, z: Double, radius: Double, base: Double), w: World3D)
        -> (lox: Double, hix: Double, loz: Double, hiz: Double)? {
        let s = Self.k3DSculptSize, bottom = b.y - s / 2
        var lox = b.x - s / 2, hix = b.x + s / 2, loz = b.z - s / 2, hiz = b.z + s / 2
        let c = _desktop3DPoolCentre(sc), h = Self.k3DPoolHalf
        let sx = (lo: c.x - h, hi: c.x + h), sz = (lo: c.z - h, hi: c.z + h)
        let ix = (lo: max(lox, sx.lo), hi: min(hix, sx.hi)), iz = (lo: max(loz, sz.lo), hi: min(hiz, sz.hi))
        let straddles = ix.lo < ix.hi && iz.lo < iz.hi
        if abs(bottom - sc.base) < 0.03 {
            guard straddles else { return nil }
            return (ix.lo, ix.hi, iz.lo, iz.hi)
        }
        guard abs(bottom - w.ground(b.x, b.z)) < 0.03 else { return nil }
        if straddles {
            // Cut the part over the pool away, along whichever axis loses
            // the least of the footprint.
            let cutX = ix.hi - ix.lo, cutZ = iz.hi - iz.lo
            if cutX <= cutZ {
                if ix.lo > lox { hix = ix.lo } else { lox = ix.hi }
            } else {
                if iz.lo > loz { hiz = iz.lo } else { loz = iz.hi }
            }
            guard lox < hix, loz < hiz else { return nil }
        }
        return (lox, hix, loz, hiz)
    }

    /// Where a carried brick goes for a pointer: under the pointer, at
    /// the DISTANCE it was picked up at — it moves across the view with
    /// the mouse and keeps its depth, and the wheel changes the depth.
    /// Never below the ground under it: pushed down, it slides along the
    /// ground. (Standing the brick on whatever ground the pointer pointed
    /// at was tried first and flung it to the horizon: a brick sits at
    /// eye level, so the ray through it is nearly level, and the ground
    /// it meets is forty metres off.)
    func _desktop3DBrickCarryPoint(_ screen: Offset, camera: Camera3D, host: Rect,
                                   sc: (x: Double, z: Double, radius: Double, base: Double), w: World3D)
        -> (x: Double, y: Double, z: Double)? {
        guard let d = _desktop3DBrickDrag else { return nil }
        let s = Self.k3DSculptSize
        let (o, dir) = _desktop3DRay(screen, camera: camera, host: host)
        // `dir` has view-space z = −1, so `depth` along it is view depth.
        var x = o.x + dir.x * d.depth, y = o.y + dir.y * d.depth, z = o.z + dir.z * d.depth
        let lim = Double(min(w.heightSize.x, w.heightSize.z)) / 2 - 1.5
        x = min(max(x, w.hub.x - lim), w.hub.x + lim)
        z = min(max(z, w.hub.z - lim), w.hub.z + lim)
        y = max(y, _desktop3DBrickGround(x, z, sc: sc, w: w) + s / 2 + 0.02)
        // Over bricks, not through them: carried into a brick, it rides
        // up onto that brick, and onto the one on that.
        for _ in 0..<8 {
            var lifted = false
            for (app, o) in _desktop3DBricks where app != d.app && o.mode != .held {
                if abs(o.x - x) < s - 0.01, abs(o.z - z) < s - 0.01, abs(o.y - y) < s - 0.01 {
                    y = o.y + s + 0.02; lifted = true
                }
            }
            if !lifted { break }
        }
        return (x, y, z)
    }

    /// The wheel while a brick is carried: away for a scroll up, nearer
    /// for a scroll down, within arm's reach and the square.
    static let k3DBrickDepthMin = 1.2
    static let k3DBrickDepthMax = 30.0
    static let k3DBrickDepthStep = 0.4

    func _desktop3DBrickWheel(_ dy: Double) {
        guard var d = _desktop3DBrickDrag, d.dragging, dy != 0 else { return }
        d.depth = min(Self.k3DBrickDepthMax, max(Self.k3DBrickDepthMin,
                      d.depth + (dy < 0 ? Self.k3DBrickDepthStep : -Self.k3DBrickDepthStep)))
        setState { _desktop3DBrickDrag = d }
    }

    /// Give every app a brick: the whole building the first time, laid
    /// as courses; later arrivals fall in from above. Bricks of apps
    /// that have gone go too.
    func _desktop3DSettleBricks(_ apps: [String], sc: (x: Double, z: Double, radius: Double, base: Double)) {
        let s = Self.k3DSculptSize
        for app in _desktop3DBricks.keys where !apps.contains(app) { _desktop3DBricks[app] = nil }
        if _desktop3DBricks.isEmpty {
            let n = apps.count
            let k = max(2, Int(Double(n).squareRoot().rounded(.up)))
            var i = 0, course = 0
            while i < n {
                let m = min(k, n - i)
                for j in 0..<m {
                    let x = sc.x + (Double(j) - Double(m - 1) / 2) * s + (course % 2 == 1 ? s / 4 : 0)
                    _desktop3DBricks[apps[i + j]] = BrickBody(x: x, y: sc.base + s / 2 + Double(course) * s, z: sc.z)
                }
                i += m; course += 1
            }
            return
        }
        var spawned = false
        for app in apps where _desktop3DBricks[app] == nil {
            // Somewhere over the pile, by the name, so it is the same
            // spot each time.
            let h = app.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
            let x = sc.x + (Double(h % 200) / 100 - 1) * s
            let top = _desktop3DBricks.values.map { $0.y + s / 2 }.max() ?? sc.base
            _desktop3DBricks[app] = BrickBody(x: x, y: top + 2.5 * s, z: sc.z, mode: .fall)
            spawned = true
        }
        if spawned { _desktop3DStartBricks() }
    }

    /// Run the bricks until every one is at rest.
    func _desktop3DStartBricks() {
        if _brickTicker == nil {
            _brickTicker = createTicker { [weak self] elapsed in
                guard let self else { return }
                let now = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) * 1e-18
                let dt = max(0, min(0.05, now - self._brickClock))
                self._brickClock = now
                guard self._desktop3DActive, let w = self._desktop3DWorld, let sc = w.sculpture else {
                    self._brickTicker?.stop()
                    return
                }
                // A pile that has not settled in twenty seconds is fighting
                // itself: stop, and say so, rather than burn a core.
                if now > 20 {
                    self._desktop3DLog("bricks did not settle in 20 s — stopping")
                    self._brickTicker?.stop()
                    return
                }
                var moving = self._desktop3DBrickStep(dt, sc: sc)
                // Settled: onto the grid, and if that moved anything, once
                // more round for its footing.
                if !moving, self._desktop3DSnapBricks(sc: sc, w: w) { moving = true }
                if !moving {
                    self._brickTicker?.stop()
                    self._desktop3DLog("bricks settled: " + self._desktop3DBricks.sorted { $0.key < $1.key }.map {
                        String(format: "%@(%.2f,%.2f,%.2f %@)", $0.key, $0.value.x, $0.value.y, $0.value.z, "\($0.value.mode)")
                    }.joined(separator: " "))
                }
                self.setState {}
            }
        }
        if !(_brickTicker?.isActive ?? false) {
            _brickClock = 0
            _ = _brickTicker?.start()
        }
    }

    /// The grid: a quarter of a brick. A pile of bricks at odd offsets
    /// reads as bricks sunk into each other — two flush faces a third of
    /// a brick apart are one lump from the front — and Lego does not
    /// allow it. So a brick that has come to rest is moved to the nearest
    /// quarter-brick point, when that spot is free and on the same ground,
    /// lowest bricks first. The building's courses are on this grid.
    static let k3DBrickGrid = k3DSculptSize / 4

    func _desktop3DSnapBricks(sc: (x: Double, z: Double, radius: Double, base: Double), w: World3D) -> Bool {
        let s = Self.k3DSculptSize, g = Self.k3DBrickGrid
        var changed = false
        let order = _desktop3DBricks.filter { $0.value.mode == .rest }.sorted { $0.value.y < $1.value.y }.map { $0.key }
        for app in order {
            guard var b = _desktop3DBricks[app], b.mode == .rest else { continue }
            let sx = sc.x + ((b.x - sc.x) / g).rounded() * g, sz = sc.z + ((b.z - sc.z) / g).rounded() * g
            guard abs(sx - b.x) > 0.001 || abs(sz - b.z) > 0.001 else { continue }
            guard _desktop3DBrickGround(sx, sz, sc: sc, w: w) == _desktop3DBrickGround(b.x, b.z, sc: sc, w: w) else { continue }
            var free = true
            for (other, o) in _desktop3DBricks where other != app && o.mode != .held {
                if s - abs(o.x - sx) > 0.002, s - abs(o.y - b.y) > 0.002, s - abs(o.z - sz) > 0.002 { free = false; break }
            }
            // Nor into the pool's rim: the grid is the hub's and the pool
            // is half a metre off it, and a brick beside the rim would be
            // snapped into it and pushed out of it for ever.
            let pc = _desktop3DPoolCentre(sc)
            if Self.k3DPoolHalf + s / 2 - abs(sx - pc.x) > 0.002, 0.5 + s / 2 - abs(b.y - (sc.base - 0.5)) > 0.002,
               Self.k3DPoolHalf + s / 2 - abs(sz - pc.z) > 0.002 { free = false }
            guard free else { continue }
            b.x = sx; b.z = sz
            _desktop3DBricks[app] = b
            changed = true
        }
        return changed
    }

    /// One step of the bricks' physics, over the whole city. A resting
    /// brick stands on the ground under it or on resting bricks under it;
    /// with nothing under it, it falls; with its centre past the edge of
    /// what holds it — along x or along z — it tips about that edge, a
    /// quarter turn, then it is a square again and falls from there. A
    /// falling brick lands on the first resting brick under it or on the
    /// ground, and slides off a brick it is beside unless it is mostly
    /// over it. Returns whether anything is still moving.
    func _desktop3DBrickStep(_ dt: Double, sc: (x: Double, z: Double, radius: Double, base: Double)) -> Bool {
        guard let w = _desktop3DWorld else { return false }
        let s = Self.k3DSculptSize, m = Self.k3DBrickTipMargin
        let before = _desktop3DBricks
        var moving = false
        // A brick that has just come to rest has not had its footing
        // checked: one more step for that, or a brick that landed with its
        // centre past the edge of what it landed on would hang there —
        // the ticker stopped the moment it touched down.
        var landed = false
        func overlapXZ(_ a: BrickBody, _ b: BrickBody, _ slack: Double) -> Bool {
            abs(a.x - b.x) < s - slack && abs(a.z - b.z) < s - slack
        }
        for (app, b0) in before {
            var b = b0
            switch b.mode {
            case .held:
                continue
            case .rest:
                let bottom = b.y - s / 2
                var lox = Double.infinity, hix = -Double.infinity, loz = Double.infinity, hiz = -Double.infinity
                if let g = _desktop3DGroundSupport(b, sc: sc, w: w) {
                    lox = g.lox; hix = g.hix; loz = g.loz; hiz = g.hiz
                }
                for (other, o) in before where other != app && o.mode == .rest {
                    guard overlapXZ(o, b, 0.01), abs((o.y + s / 2) - bottom) < 0.03 else { continue }
                    lox = min(lox, max(o.x - s / 2, b.x - s / 2)); hix = max(hix, min(o.x + s / 2, b.x + s / 2))
                    loz = min(loz, max(o.z - s / 2, b.z - s / 2)); hiz = max(hiz, min(o.z + s / 2, b.z + s / 2))
                }
                if lox > hix {
                    b.mode = .fall; b.vy = 0
                } else if b.x < lox + m || b.x > hix - m {
                    // Over the edge along x: tip that way.
                    b.mode = .tumble; b.alongZ = false; b.angle = 0
                    b.sigma = b.x < lox + m ? -1 : 1
                    let edge = b.sigma < 0 ? lox : hix
                    b.pivot = (edge, bottom); b.rel = (b.x - edge, s / 2)
                } else if b.z < loz + m || b.z > hiz - m {
                    b.mode = .tumble; b.alongZ = true; b.angle = 0
                    b.sigma = b.z < loz + m ? -1 : 1
                    let edge = b.sigma < 0 ? loz : hiz
                    b.pivot = (edge, bottom); b.rel = (b.z - edge, s / 2)
                }
            case .fall:
                b.vy += Self.k3DBrickGravity * dt
                let bottom = b.y - s / 2
                var land = _desktop3DBrickGround(b.x, b.z, sc: sc, w: w)
                for (other, o) in before where other != app && o.mode == .rest {
                    let top = o.y + s / 2
                    // Any brick under it, however little of it: it lands
                    // there, and tips off if that is not enough to hold it.
                    guard overlapXZ(o, b, 0.02), top <= bottom + 0.001 else { continue }
                    land = max(land, top)
                }
                if bottom - b.vy * dt <= land {
                    b.y = land + s / 2; b.vy = 0; b.mode = .rest; landed = true
                } else {
                    b.y -= b.vy * dt
                }
            case .tumble:
                b.angle = min(Double.pi / 2, b.angle + Self.k3DBrickTipRate * dt)
                let th = b.angle, sg = b.sigma
                // The centre swings about the edge, out past it and down.
                let along = b.pivot.a + b.rel.a * cos(th) + sg * b.rel.y * sin(th)
                b.y = b.pivot.y + b.rel.y * cos(th) - sg * b.rel.a * sin(th)
                if b.alongZ {
                    b.z = along; b.yaw = Double.pi / 2; b.roll = sg * th
                } else {
                    b.x = along; b.yaw = 0; b.roll = -sg * th
                }
                if b.angle >= Double.pi / 2 {
                    // A quarter turn on: a square again, falling.
                    b.roll = 0; b.yaw = 0; b.mode = .fall; b.vy = Self.k3DBrickTipRate * s / 2
                }
            }
            if b.mode != .rest { moving = true }
            _desktop3DBricks[app] = b
        }
        // No two bricks in the same place: every pair of boxes that
        // overlap are pushed apart along the axis they overlap least on
        // — up (the upper one, which then rests on the lower) when that
        // is up, else half each sideways — a few passes, so a push that
        // makes a new overlap is undone too. A brick in the hand and a
        // brick mid-tumble are left alone; they settle when they are
        // squares on the ground again. A resting brick pushed off its
        // support finds out next step, and tips.
        let apps = Array(_desktop3DBricks.keys).sorted()
        for _ in 0..<4 {
            var pushed = false
            for i in 0..<apps.count {
                for j in (i + 1)..<apps.count {
                    guard var a = _desktop3DBricks[apps[i]], var b = _desktop3DBricks[apps[j]],
                          a.mode != .held, b.mode != .held, a.mode != .tumble, b.mode != .tumble else { continue }
                    let px = s - abs(a.x - b.x), py = s - abs(a.y - b.y), pz = s - abs(a.z - b.z)
                    guard px > 0.002, py > 0.002, pz > 0.002 else { continue }
                    pushed = true
                    if py <= px && py <= pz {
                        // The upper one up, onto the lower.
                        let upperIsA = a.y >= b.y
                        if upperIsA { a.y = b.y + s + 0.001; a.vy = 0; if a.mode == .fall { a.mode = .rest } }
                        else { b.y = a.y + s + 0.001; b.vy = 0; if b.mode == .fall { b.mode = .rest } }
                    } else if px <= pz {
                        let d = (a.x < b.x ? -1.0 : 1.0) * (px / 2 + 0.001)
                        a.x += d; b.x -= d
                    } else {
                        let d = (a.z < b.z ? -1.0 : 1.0) * (pz / 2 + 0.001)
                        a.z += d; b.z -= d
                    }
                    _desktop3DBricks[apps[i]] = a; _desktop3DBricks[apps[j]] = b
                }
            }
            if !pushed { break }
            moving = true
        }
        // The pool is a block too: a brick pushed into its rim comes out
        // of it — up onto the pool when that is the short way, else
        // sideways onto the plaza.
        let pc = _desktop3DPoolCentre(sc)
        let poolMid = sc.base - 0.5, poolHalfY = 0.5
        for (app, var b) in _desktop3DBricks where b.mode != .held && b.mode != .tumble {
            let px = Self.k3DPoolHalf + s / 2 - abs(b.x - pc.x), py = poolHalfY + s / 2 - abs(b.y - poolMid)
            let pz = Self.k3DPoolHalf + s / 2 - abs(b.z - pc.z)
            guard px > 0.002, py > 0.002, pz > 0.002 else { continue }
            moving = true
            if py <= px && py <= pz, b.y >= poolMid {
                b.y = sc.base + s / 2 + 0.001; b.vy = 0; if b.mode == .fall { b.mode = .rest }
            } else if px <= pz {
                b.x += (b.x < pc.x ? -1 : 1) * (px + 0.001)
            } else {
                b.z += (b.z < pc.z ? -1 : 1) * (pz + 0.001)
            }
            _desktop3DBricks[app] = b
        }
        for (app, var b) in _desktop3DBricks where b.mode != .held {
            let floor = _desktop3DBrickGround(b.x, b.z, sc: sc, w: w) + s / 2
            if b.y < floor { b.y = floor; b.vy = 0; if b.mode == .fall { b.mode = .rest }; _desktop3DBricks[app] = b; landed = true }
        }
        return moving || landed
    }

    /// An app's block face: its colour to the edges, its glyph in white —
    /// the tile with no rounded corners, since a block has none. Hovered:
    /// lighter, with a white rim, so the pointer's brick shows without
    /// moving.
    /// An app's own icon as a decoded image, for the nameplates and brick
    /// faces of apps that have one (third-party apps, whose registry
    /// record points at a PNG): nil until it has been decoded, and the
    /// caller paints the catalog glyph meanwhile. The first ask starts the
    /// decode; when it lands, that app's textures are dropped and the
    /// shell rebuilt, so the next build paints them again with the icon.
    /// The dock decodes the same file for its tiles (_loadIconTexture),
    /// but flipped for the GL path, and into a texture rather than an
    /// image a canvas can draw.
    func _desktop3DIconImage(_ appId: String) -> Image? {
        #if os(Linux)
        if let img = _desktop3DIconImages[appId] { return img }
        guard !_desktop3DIconDecodes.contains(appId),
              let path = AppRegistry.shared.app(id: appId)?.iconPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        _desktop3DIconDecodes.insert(appId)
        Task { @MainActor in
            guard let codec = try? await FlutterSwiftBridge.instantiateImageCodec([UInt8](data)),
                  let frame = try? await codec.getNextFrame() else { return }
            codec.dispose()
            guard let shell = _shellState else { frame.image.dispose(); return }
            shell._desktop3DIconImages[appId] = frame.image
            // The glyph versions go; a new texture id means a new label or
            // block in the scene, which is what makes the renderer pick the
            // fresh picture up.
            if let registry = drmTextureRegistry, let wl = waylandIntegration {
                for key in [appId, appId + "#hover"] {
                    if let old = shell._appFaceTextures.removeValue(forKey: key) {
                        registry.unregisterTexture(engine: wl.engine, id: old)
                    }
                }
                if let old = shell._appLabelTextures.removeValue(forKey: appId) {
                    registry.unregisterTexture(engine: wl.engine, id: old)
                }
            }
            shell.setState {}
        }
        return nil
        #else
        return nil
        #endif
    }

    /// Painted shop signs: warm timber edges, a cream bevel, muted enamel
    /// panels and brass corner pins. Drawn in the shell so installed apps
    /// keep their own recognizable mark and hover stays instantaneous.
    func _desktop3DPaintCitySign(_ canvas: NativeCanvas, color: Color, hovered: Bool) {
        let paint = Paint()
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: Color) {
            paint.color = c
            canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint)
        }
        rect(0, 0, 128, 128, Color(0xFF44382E))
        rect(3, 3, 122, 122, hovered ? Color(0xFFFFE9AD) : Color(0xFFC2A77C))
        rect(6, 6, 116, 116, Color(0xFFF0DDB7))
        rect(9, 9, 110, 110, Color(0xFF75644E))
        let lift = hovered ? 0.12 : 0.0
        let enamel = Color(alpha: 1,
            red: min(1, color.r * 0.68 + 0.12 + lift),
            green: min(1, color.g * 0.68 + 0.11 + lift),
            blue: min(1, color.b * 0.68 + 0.08 + lift))
        rect(11, 11, 106, 106, enamel)
        // Shallow panel seams and an inset highlight catch the same
        // light as the city's clapboard and window trim.
        for y in stride(from: 28.0, through: 100.0, by: 24.0) {
            rect(12, y, 104, 1, Color(alpha: 0.09, red: 0.12, green: 0.09, blue: 0.06))
            rect(12, y + 1, 104, 1, Color(alpha: 0.07, red: 1, green: 0.94, blue: 0.8))
        }
        rect(12, 12, 104, 2, Color(alpha: 0.22, red: 1, green: 0.94, blue: 0.8))
        rect(12, 114, 104, 2, Color(alpha: 0.2, red: 0.1, green: 0.08, blue: 0.06))
        for x in [7.0, 117.0] {
            for y in [7.0, 117.0] {
                rect(x, y, 4, 4, Color(0xFF80633D))
                rect(x, y, 3, 2, Color(0xFFFFE6A0))
            }
        }
    }

    func _desktop3DAppFaceTexture(_ appId: String, hovered: Bool = false) -> Int64? {
        #if os(Linux)
        let key = hovered ? appId + "#hover" : appId
        if let id = _appFaceTextures[key] { return id }
        guard let registry = drmTextureRegistry, let wl = waylandIntegration else { return nil }
        let rec = AppRegistry.shared.installedApps.first { $0.id == appId }
        let bg = rec.map { Color(Int($0.color) | 0xFF00_0000) } ?? Color(0xFF355E58)
        let s = 128
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        _desktop3DPaintCitySign(canvas, color: bg, hovered: hovered)
        if let icon = _desktop3DIconImage(appId) {
            canvas.drawImageRect(icon, Rect.fromLTWH(0, 0, Double(icon.width), Double(icon.height)),
                                 Rect.fromLTWH(28, 28, 72, 72), Paint())
        } else {
            canvas.save()
            canvas.translate(30, 31)
            IconPainter(_iconType(for: appId), color: Color(0xFF4B4034)).paint(canvas, Size(72, 72))
            canvas.restore()
            canvas.save()
            canvas.translate(28, 28)
            IconPainter(_iconType(for: appId), color: Color(0xFFFFE9BE)).paint(canvas, Size(72, 72))
            canvas.restore()
        }
        let picture = recorder.endRecording()
        guard let image = picture.toImageSync(width: s, height: s) else { return nil }
        defer { image.dispose() }
        guard let bytes = try? image.toByteData(format: .rawRgba) else { return nil }
        let id = registry.registerTexture(engine: wl.engine)
        bytes.withUnsafeBytes { raw in
            registry.updatePixelData(engine: wl.engine, id: id, data: raw.baseAddress!,
                                     width: s, height: s)
        }
        _appFaceTextures[key] = id
        return id
        #else
        return nil
        #endif
    }

    func _desktop3DRailWindows() -> [WindowInfo] {
        windowManager.windows.filter {
            $0.textureId != nil && $0.ownerAgentId == nil
                && _desktop3DOutputId(for: $0) == _desktop3DViewId
                && $0.spaceId == windowManager.activeSpaceId(onOutput: _desktop3DViewId)
        }
    }

    func _desktop3DRailApps() -> [String] {
        let running = Set(_desktop3DRailWindows().map { _desktop3DAppId(of: $0) })
        return _dockDisplayApps.filter { $0 != "launcher" && running.contains($0) }
            + running.filter { !_dockDisplayApps.contains($0) && $0 != "launcher" }.sorted()
    }

    func _desktop3DRailMove(_ delta: Int) {
        let page = WorkspaceRailPage(count: _desktop3DRailApps().count, start: _desktop3DRailStart)
        setState { _desktop3DRailStart = page.moved(delta); _desktop3DHoveredSign = nil }
    }

    /// Wheel only over the exposed rail; never scroll the rail through a client or modal.
    func _desktop3DRailScroll(_ event: PointerScrollEvent) -> Bool {
        guard _desktop3DT >= 1, !_launcherOpen, !_missionControlOpen,
              _desktop3DBrickDrag == nil, let world = _desktop3DWorld,
              let rail = world.workspaceRail.first, _desktop3DRailApps().count > 5,
              _desktop3DPaneUnder(event.position) == nil else { return false }
        let host = _desktop3DHost
        let pose = WindowPose3D(x: rail.x, y: rail.y, z: rail.z, placed: true)
        guard let (x, y) = _desktop3DPlaneHit(event.position,
            camera: _desktop3DEffectiveCamera(_desktop3DT), host: host, pose: pose),
              abs(x) < 9, abs(y) < 1.7 else { return false }
        let delta = abs(event.scrollDelta.dx) > abs(event.scrollDelta.dy)
            ? event.scrollDelta.dx : event.scrollDelta.dy
        _desktop3DRailWheel += delta
        if abs(_desktop3DRailWheel) >= 40 {
            _desktop3DRailMove(_desktop3DRailWheel > 0 ? 1 : -1)
            _desktop3DRailWheel = 0
        }
        return true
    }

    /// Five readable cards at most, independent of the total running count.
    func _desktop3DWorkspaceRails() -> [(app: String, x: Double, y: Double, z: Double, width: Double, height: Double)] {
        guard let world = _desktop3DWorld, world.kind == .voxel, !world.workspaceRail.isEmpty else { return [] }
        let all = _desktop3DRailApps()
        let page = WorkspaceRailPage(count: all.count, start: _desktop3DRailStart)
        let apps = Array(all[page.range])
        let pitch = min(4.2, 16.0 / Double(max(apps.count, 1)))
        return apps.enumerated().map { i, app in
            let bay = world.workspaceRail[0]
            let x = (Double(i) - Double(apps.count - 1) / 2) * pitch
            let width = min(bay.width, pitch * 0.9)
            let height = bay.height * width / bay.width
            return (app, bay.x + x, bay.y - (bay.height - height) / 2,
                    bay.z + 0.04 * x * x, width, height)
        }
    }

    func _desktop3DSigns() -> [(app: String, x: Double, y: Double, z: Double, w: Double, h: Double, yaw: Double?)] {
        if let world = _desktop3DWorld, !world.workspaceRail.isEmpty { return [] }
        guard let w = _desktop3DWorld, w.kind == .voxel, w.sculpture == nil else { return [] }
        let apps = _dockDisplayApps.filter { $0 != "launcher" }
        let n = apps.count
        guard n > 0 else { return [] }
        if let t = w.tower {
            // The app tower: signs fixed on its front face, floor by
            // floor from the pool up, the dock's first apps lowest —
            // nearest eye level. Two columns; three when the dock is long.
            let cols = n <= 14 ? 2 : 3
            let pitch = cols == 2 ? 1.3 : 0.95
            return apps.enumerated().map { i, app in
                let floor = i / cols, col = i % cols
                let x = t.x + (Double(col) - Double(cols - 1) / 2) * pitch
                let y = t.base + Self.k3DTowerFirstFloor + Double(floor) * Self.k3DTowerFloor
                let k = app == _desktop3DHoveredSign ? Self.k3DSignHoverScale : 1.0
                return (app, x, y, t.z + t.half + Self.k3DTowerSignOut,
                        Self.k3DSignWidth * k, Self.k3DSignHeight * k, 0.0)
            }
        }
        let z0 = w.hub.z + w.ringRadius * Self.k3DSignRing
        let rows = (n + Self.k3DSignsPerRow - 1) / Self.k3DSignsPerRow
        let perRow = (n + rows - 1) / rows
        return apps.enumerated().map { i, app in
            let row = i / perRow, col = i % perRow
            let inRow = min(perRow, n - row * perRow)
            // +x is the viewer's right from the entrance; each row is
            // centred on its own.
            let x = w.hub.x + (Double(col) - Double(inRow - 1) / 2) * Self.k3DSignPitch
            let z = z0 - Double(row) * Self.k3DSignRowBack
            let k = app == _desktop3DHoveredSign ? Self.k3DSignHoverScale : 1.0
            return (app, x, w.ground(x, z) + 1.15 + Double(row) * Self.k3DSignRowRise, z,
                    Self.k3DSignWidth * k, Self.k3DSignHeight * k, nil)
        }
    }

    /// The sign under a screen point, if any: each is a billboard facing
    /// the viewer, so its screen box is its centre projected and its size
    /// over its depth — nearest wins where two overlap.
    func _desktop3DSignAt(_ screen: Offset, excluding: String? = nil) -> String? {
        _desktop3DSignAtDepth(screen, excluding: excluding)?.app
    }

    func _desktop3DSignAtDepth(_ screen: Offset, excluding: String? = nil) -> (app: String, depth: Double)? {
        let host = _desktop3DHost
        guard host.width > 0, _desktop3DT >= 1 else { return nil }
        let cam = _desktop3DEffectiveCamera(_desktop3DT)
        let view = Self._view(cam)
        let focal = _desktop3DFocalPx(host)
        var best: (app: String, depth: Double)? = nil
        var targets = _desktop3DSigns()
        targets += _desktop3DWorkspaceRails().map { ($0.app, $0.x, $0.y, $0.z, $0.width, $0.height, 0.0) }
        for s in targets where s.app != excluding {
            let v = view.perspectiveTransform(Vector3(s.x, s.y, s.z))
            let depth = -v.z
            guard depth > 0.1 else { continue }
            if let yaw = s.yaw {
                // Fixed on a wall: where the ray meets its plane.
                let pose = WindowPose3D(x: s.x, y: s.y, z: s.z, yaw: yaw, scale: 1, placed: true)
                guard let (u, vv) = _desktop3DPlaneHit(screen, camera: cam, host: host, pose: pose),
                      abs(u) <= s.w / 2, abs(vv) <= s.h / 2 else { continue }
            } else {
                let sx = host.center.dx + focal * v.x / depth
                let sy = host.center.dy - focal * v.y / depth
                let hw = focal * s.w / depth / 2, hh = focal * s.h / depth / 2
                guard abs(screen.dx - sx) <= hw, abs(screen.dy - sy) <= hh else { continue }
            }
            if best == nil || depth < best!.depth { best = (s.app, depth) }
        }
        let boxes: [(app: String, x: Double, y: Double, z: Double, size: Double)] =
            _desktop3DSculpture().map { ($0.app, $0.x, $0.y, $0.z, $0.size) }
            + _desktop3DControls().map { ($0.id, $0.x, $0.y, $0.z, $0.size) }
        for b in boxes where b.app != excluding {
            // A block: its projected box, a little generous for the corners.
            let v = view.perspectiveTransform(Vector3(b.x, b.y, b.z))
            let depth = -v.z
            guard depth > 0.1 else { continue }
            let sx = host.center.dx + focal * v.x / depth
            let sy = host.center.dy - focal * v.y / depth
            let half = focal * b.size * 0.62 / depth
            guard abs(screen.dx - sx) <= half, abs(screen.dy - sy) <= half else { continue }
            if best == nil || depth < best!.depth { best = (b.app, depth) }
        }
        return best
    }

    /// The nearest window pane under a screen point, and how far it is.
    func _desktop3DPaneUnder(_ screen: Offset) -> (win: WindowInfo, depth: Double)? {
        let host = _desktop3DHost
        guard host.width > 0 else { return nil }
        let cam = _desktop3DEffectiveCamera(_desktop3DT)
        let s = Self.k3DMetresPerPx
        var best: (win: WindowInfo, depth: Double)? = nil
        for win in windowManager.visibleWindows where win.pose3D.placed && !win.isFullscreen && _desktop3DIsShown(win) {
            let p = win.pose3D
            guard let (u, v) = _desktop3DPlaneHit(screen, camera: cam, host: host, pose: p),
                  abs(u) <= win.rect.width * s * p.scale / 2, abs(v) <= win.rect.height * s * p.scale / 2 else { continue }
            let dx = p.x - cam.x, dy = p.y - cam.y, dz = p.z - cam.z
            let depth = (dx * dx + dy * dy + dz * dz).squareRoot()
            if best == nil || depth < best!.depth { best = (win, depth) }
        }
        return best
    }

    /// The world thing under a screen point that is actually the nearest
    /// thing there: nil when a window's pane is in front of it.
    func _desktop3DSignAtVisible(_ screen: Offset) -> String? {
        guard _desktop3DVoxel, _desktop3DT >= 1, let (obj, depth) = _desktop3DSignAtDepth(screen) else { return nil }
        if let pane = _desktop3DPaneUnder(screen), pane.depth < depth { return nil }
        return obj
    }

    /// Pointer over the world: the sign under it grows a little.
    func _desktop3DSignHover(_ screen: Offset) {
        guard _desktop3DVoxel else { return }
        let hit = _desktop3DSignAtVisible(screen)
        if hit != _desktop3DHoveredSign {
            setState { _desktop3DHoveredSign = hit }
        }
    }

    /// A click on the world: a sign opens its app.
    func _desktop3DSignClick(_ screen: Offset) {
        guard let app = _desktop3DSignAt(screen) else { return }
        _desktop3DLog("sign \(app) clicked")
        _launchOrFocusApp(app)
    }

    /// How far the pointer moves with the button down before a press on
    /// a brick is a drag and not a click.
    static let k3DBrickDragSlop = 8.0

    /// The button goes down on the world. On a brick of the building it
    /// may be the start of a drag — a click is decided on release; on any
    /// other sign it is a click.
    func _desktop3DSignDown(_ screen: Offset) {
        guard _desktop3DVoxel, _desktop3DBrickDrag == nil, let app = _desktop3DSignAtVisible(screen) else { return }
        if app.hasPrefix("@") {
            _desktop3DControlActivate(app)
        } else if _desktop3DSculpture().contains(where: { $0.app == app }) {
            _desktop3DBrickDrag = (app, screen, screen, false, 0)
        } else {
            _desktop3DLog("sign \(app) clicked")
            _desktop3DOpenApp(app)
        }
    }

    /// The pointer moves with the button down: past the slop the brick
    /// leaves the wall and follows it, and the brick it is over comes
    /// forward to say "here".
    func _desktop3DSignMove(_ screen: Offset) {
        guard var d = _desktop3DBrickDrag else { return }
        d.at = screen
        if !d.dragging {
            let dx = screen.dx - d.start.dx, dy = screen.dy - d.start.dy
            if dx * dx + dy * dy > Self.k3DBrickDragSlop * Self.k3DBrickDragSlop { d.dragging = true }
        }
        let target = d.dragging ? _desktop3DSignAt(screen, excluding: d.app) : nil
        let pickedUp = d.dragging && _desktop3DBricks[d.app]?.mode != .held
        if pickedUp, let b = _desktop3DBricks[d.app] {
            // Picked up at the distance it stood at.
            let cam = _desktop3DEffectiveCamera(_desktop3DT)
            let v = Self._view(cam).perspectiveTransform(Vector3(b.x, b.y, b.z))
            d.depth = max(Self.k3DBrickDepthMin, -v.z)
        }
        setState {
            _desktop3DBrickDrag = d
            if d.dragging { _desktop3DHoveredSign = target }
            if pickedUp { _desktop3DBricks[d.app]?.mode = .held }
        }
        // Whatever it held up is on its own now.
        if pickedUp { _desktop3DStartBricks() }
    }

    /// The button comes up: a dragged brick is let go where the pointer
    /// is — lifted clear of any brick it would be inside — and falls from
    /// there onto whatever is under it; a press that never became a drag
    /// is a click.
    func _desktop3DSignUp(_ screen: Offset) {
        guard let d = _desktop3DBrickDrag else { return }
        if d.dragging {
            _desktop3DLog("brick \(d.app) let go")
            setState {
                _desktop3DBrickDrag = nil
                _desktop3DHoveredSign = nil
                guard var b = _desktop3DBricks[d.app] else { return }
                let s = Self.k3DSculptSize
                // Let go where it is carried; lifted clear of any brick it
                // would be inside, so it lands on that one.
                for (other, o) in _desktop3DBricks where other != d.app && o.mode == .rest {
                    if abs(o.x - b.x) < s - 0.01, abs(o.z - b.z) < s - 0.01,
                       o.y + s / 2 > b.y - s / 2, o.y - s / 2 < b.y + s / 2 {
                        b.y = max(b.y, o.y + s)
                    }
                }
                b.mode = .fall; b.vy = 0; b.roll = 0; b.yaw = 0
                _desktop3DBricks[d.app] = b
            }
            _desktop3DStartBricks()
        } else {
            setState { _desktop3DBrickDrag = nil }
            _desktop3DLog("sign \(d.app) clicked")
            _desktop3DBrickClicked(d.app)
        }
    }

    /// The world's frame tile (world.json `pane_frame`), decoded into a
    /// registry texture the renderer builds the window frames from. The
    /// decode is asynchronous; the renderer draws plain slabs until it
    /// lands, then a fresh frame of the scene picks the tile up.
    func _desktop3DLoadFrameTile(_ fr: FilamentRoomRenderer) {
        #if os(Linux)
        guard let frame = fr.world.paneFrame else { return }
        let path = frame.texture
        let outputId = _desktop3DViewId
        let rendererId = ObjectIdentifier(fr)
        Task { @MainActor in
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let codec = try? await FlutterSwiftBridge.instantiateImageCodec([UInt8](d)),
                  let f = try? await codec.getNextFrame() else {
                FileHandle.standardError.write(Data("[room] cannot decode frame tile \(path)\n".utf8))
                return
            }
            codec.dispose()
            let image = f.image
            // The renderer that asked, if it is still the one on the desktop.
            guard let shell = _shellState, let fr = shell._environments[outputId] as? FilamentRoomRenderer, ObjectIdentifier(fr) == rendererId,
                  fr.world.paneFrame?.texture == path,
                  let registry = drmTextureRegistry, let wl = waylandIntegration,
                  let bytes = try? image.toByteData(format: .rawRgba) else { image.dispose(); return }
            // The block chrome paints the same tile; keep the picture.
            shell._worldFrameTile?.dispose()
            shell._worldFrameTile = image
            let id = registry.registerTexture(engine: wl.engine)
            bytes.withUnsafeBytes { raw in
                registry.updatePixelData(engine: wl.engine, id: id, data: raw.baseAddress!,
                                         width: image.width, height: image.height)
            }
            fr.frameTextureId = id
            if let texture = shell._environmentTextures[outputId] {
                registry.markGLTextureDirty(engine: wl.engine, id: texture)
            }
        }
        #endif
    }

    /// An app's label for the scene — its tile (colour and glyph) with its
    /// name under it — drawn once into a texture the renderer can hang on
    /// a billboard. Cached per app for the life of the shell.
    func _desktop3DAppLabelTexture(_ appId: String) -> Int64? {
        #if os(Linux)
        if let id = _appLabelTextures[appId] { return id }
        guard let registry = drmTextureRegistry, let wl = waylandIntegration else { return nil }
        let rec = AppRegistry.shared.installedApps.first { $0.id == appId }
        let title = rec?.name ?? appId
        let bg = rec.map { Color(Int($0.color) | 0xFF00_0000) } ?? Color(0xFF3A3F4B)
        let w = 256, h = 300
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        let tile = Rect.fromLTWH(48, 8, 160, 160)
        let paint = Paint()
        paint.color = bg
        canvas.drawRRect(RRect(left: tile.left, top: tile.top, right: tile.right, bottom: tile.bottom,
                               tlRadiusX: 36, tlRadiusY: 36, trRadiusX: 36, trRadiusY: 36,
                               brRadiusX: 36, brRadiusY: 36, blRadiusX: 36, blRadiusY: 36), paint)
        if let icon = _desktop3DIconImage(appId) {
            // The app's own icon, over its tile: host icons bring their
            // own shape, so they get the tile's room rather than the glyph's.
            canvas.drawImageRect(icon, Rect.fromLTWH(0, 0, Double(icon.width), Double(icon.height)),
                                 tile.deflate(8), Paint())
        } else {
            canvas.save()
            canvas.translate(tile.left + 32, tile.top + 32)
            IconPainter(_iconType(for: appId), color: Color(0xFFFFFFFF)).paint(canvas, Size(96, 96))
            canvas.restore()
        }
        let pb = NativeParagraphBuilder(ParagraphStyle(textAlign: .center, fontSize: 30,
                                                       fontWeight: .w600))
        pb.pushStyle(TextStyle(color: Color(0xFFFFFFFF), fontWeight: .w600, fontSize: 30))
        pb.addText(title)
        let para = pb.build()
        para.layout(ParagraphConstraints(width: Double(w)))
        canvas.drawParagraph(para, Offset(0, 192))
        let picture = recorder.endRecording()
        guard let image = picture.toImageSync(width: w, height: h) else { return nil }
        defer { image.dispose() }
        guard let bytes = try? image.toByteData(format: .rawRgba) else { return nil }
        let id = registry.registerTexture(engine: wl.engine)
        bytes.withUnsafeBytes { raw in
            registry.updatePixelData(engine: wl.engine, id: id, data: raw.baseAddress!,
                                     width: w, height: h)
        }
        _appLabelTextures[appId] = id
        return id
        #else
        return nil
        #endif
    }

    // MARK: The environment

    /// The room behind the windows: a texture in the wallpaper's slot,
    /// rendered from the wallpaper's own texture. Created on first use
    /// (the wallpaper decodes asynchronously, so `makeWallpaper` asks
    /// every build until it can), released when a leave finishes.
    @discardableResult
    func _ensureEnvironment() -> Bool {
        #if os(Linux)
        let live = Set(displayLayout?.outputs.map { $0.id } ?? [0])
        for id in Array(_environments.keys) where !live.contains(id) {
            _withDesktop3DOutput(id) { _releaseEnvironmentOutput() }
        }
        var ready = true
        _forEachDesktop3DOutput { if !_ensureEnvironmentOutput() { ready = false } }
        return ready
        #else
        return false
        #endif
    }

    private func _ensureEnvironmentOutput() -> Bool {
        #if os(Linux)
        let canvas = _desktop3DCanvas
        // Bound each output target independently, preserving its aspect ratio.
        let scale = min(displayLayout?.outputs.first(where: { $0.id == _desktop3DViewId })?.scale ?? 1,
                        8192 / max(1, max(canvas.width, canvas.height)))
        let renderWidth = max(1, Int((canvas.width * scale).rounded()))
        let renderHeight = max(1, Int((canvas.height * scale).rounded()))
        if environmentTextureId >= 0 {
            if _environment?.width == renderWidth, _environment?.height == renderHeight {
                _desktop3DPublishCameraOutput()
                return true
            }
            _releaseEnvironmentOutput()
        }
        guard let registry = drmTextureRegistry, let wl = waylandIntegration,
              wallpaperTextureId >= 0,
              let phys = PlatformDispatcher.instance.implicitView?.physicalSize,
              phys.width > 0, phys.height > 0 else { return false }
        // The renderer: Filament (Compositor/FilamentRoom.swift), drawing a
        // world from its directory — the city shipped under
        // share/starling/worlds/city — whenever its library is beside the
        // shell; the shell's own GL room otherwise. STARLING_ROOM=gl forces
        // the GL room, STARLING_ROOM_DIR picks another world (one being
        // generated under ~/tmp, say).
        let renderer: EnvironmentRenderer
        let env = ProcessInfo.processInfo.environment
        let worldDir = env["STARLING_ROOM_DIR"]
            ?? Self.dataFilePath("worlds/city/world.json").map { ($0 as NSString).deletingLastPathComponent }
        let filament: Bool
        switch env["STARLING_ROOM"] {
        case "gl": filament = false
        case "filament": filament = true
        default: filament = worldDir != nil && FilamentRoomRenderer.isAvailable
        }
        if filament {
            let dir = worldDir ?? "room/filament"
            let fr = FilamentRoomRenderer(width: renderWidth, height: renderHeight,
                                          roomDir: dir)
            fr.sceneTexture = { [weak registry] id in registry?.sceneTexture(id: id) }
            renderer = fr
            _desktop3DLoadFrameTile(fr)
        } else {
            renderer = EnvironmentRenderer(width: renderWidth, height: renderHeight)
        }
        renderer.glProcAddressResolver = registry.glProcAddressResolver
        let source = wallpaperTextureId
        renderer.sourceTexture = { [weak registry] in registry?.sourceTexture(id: source) }
        let id = registry.registerTexture(engine: wl.engine)
        registry.setGLRenderer(id: id, renderer: renderer)
        _environment = renderer
        environmentTextureId = id
        _startSceneClock()
        _loadRoomAsset()
        _applyRoomAssetOutput()
        _desktop3DPublishCameraOutput()
        registry.markGLTextureDirty(engine: wl.engine, id: id)
        return true
        #else
        return false
        #endif
    }

    /// The scene is weather, not a photograph: a ticker drives the cloud
    /// and the water. It lives with the ENVIRONMENT rather than with the
    /// mode, because a session that comes up with the scene already open
    /// never runs the enter path at all — the same thing that left every
    /// window without a place in the room.
    ///
    /// This is the one part of the 3D desktop that costs power while
    /// nothing else is happening: a full-screen pass per frame.
    func _startSceneClock() {
        #if os(Linux)
        // In RDP display mode there is no physical viewer. Do not animate
        // an unseen city; connection callbacks restart it when a client returns.
        guard _environment != nil else { return }
        if let display = rdpDisplayService, !display.hasClient { return }
        if let scene = _environment as? FilamentRoomRenderer {
            guard scene.world.ambientAnimation, _sceneAmbientTimer == nil else { return }
            // Ambient motion needs only 20 Hz. Dirty each output texture,
            // not the shell widget tree; static worlds remain event-driven.
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: .milliseconds(50),
                           leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in
                guard let self, self._desktop3DActive, !self._sessionLocked,
                      !self._screensaverActive,
                      let registry = drmTextureRegistry, let wl = waylandIntegration,
                      self.environmentTextureId >= 0 else { return }
                self._forEachDesktop3DOutput {
                    self._environment?.dirty = true
                    registry.markGLTextureDirty(engine: wl.engine, id: self.environmentTextureId)
                }
                for repaint in self._sceneRepaints.values { repaint() }
            }
            _sceneAmbientTimer = timer
            timer.resume()
            return
        }
        if _sceneTicker == nil {
            _sceneTicker = createTicker { [weak self] elapsed in
                guard let self, self._environment != nil,
                      let registry = drmTextureRegistry,
                      let wl = waylandIntegration,
                      self.environmentTextureId >= 0 else { return }
                self._forEachDesktop3DOutput {
                    self._environment?.tick(Double(elapsed.components.seconds)
                         + Double(elapsed.components.attoseconds) * 1e-18)
                    registry.markGLTextureDirty(engine: wl.engine, id: self.environmentTextureId)
                }
            }
        }
        if !(_sceneTicker?.isActive ?? false) { _ = _sceneTicker?.start() }
        #endif
    }

    /// Read the baked room: the mesh, and the two atlases it is textured
    /// with. Decoded off the platform thread's critical path the same way
    /// the wallpaper is, then handed to the renderer, which uploads it at
    /// the next frame. Missing files leave the scene empty rather than
    /// failing — the room is an asset, not a dependency.
    func _loadRoomAsset() {
        #if os(Linux)
        guard !_roomLoadStarted else { return }
        _roomLoadStarted = true
        guard let meshPath = Self.dataFilePath("room/room.mesh")
                ?? ["Resources/Room/room.mesh"].first(where: {
                    FileManager.default.fileExists(atPath: $0) }),
              let mesh = Room3D.loadMesh(meshPath) else {
            FileHandle.standardError.write(Data(
                "[room] no baked room found — run build/tools/room-import.py\n".utf8))
            return
        }
        let dir = (meshPath as NSString).deletingLastPathComponent
        Task { @MainActor in
            func decode(_ name: String) async -> (data: [UInt8], w: Int, h: Int)? {
                guard let d = try? Data(contentsOf: URL(
                    fileURLWithPath: dir + "/" + name)) else { return nil }
                guard let codec = try? await FlutterSwiftBridge
                        .instantiateImageCodec([UInt8](d)),
                      let frame = try? await codec.getNextFrame() else { return nil }
                codec.dispose()
                let image = frame.image
                defer { image.dispose() }
                guard let bytes = try? image.toByteData(format: .rawRgba) else { return nil }
                return ([UInt8](bytes), image.width, image.height)
            }
            guard let diff = await decode("room-diffuse.png"),
                  let arm = await decode("room-arm.png"),
                  let sky = await decode("room-sky.png"),
                  let shell = _shellState else { return }
            shell._roomAsset = (mesh, diff, arm, sky)
            shell._applyRoomAsset()
        }
        #endif
    }

    /// Hand the room to the renderer, whenever both exist.
    func _applyRoomAsset() {
        _forEachDesktop3DOutput { _applyRoomAssetOutput() }
    }

    private func _applyRoomAssetOutput() {
        #if os(Linux)
        guard let env = _environment, let asset = _roomAsset,
              let registry = drmTextureRegistry, let wl = waylandIntegration,
              environmentTextureId >= 0 else { return }
        env.roomAsset = asset
        registry.markGLTextureDirty(engine: wl.engine, id: environmentTextureId)
        #endif
    }

    func _stopSceneClock() {
        #if os(Linux)
        _sceneTicker?.stop()
        _sceneAmbientTimer?.cancel()
        _sceneAmbientTimer = nil
        #endif
    }

    func _releaseEnvironment() {
        #if os(Linux)
        _stopSceneClock()
        _sceneRepaints.removeAll()
        for id in Array(_environments.keys) {
            _withDesktop3DOutput(id) { _releaseEnvironmentOutput() }
        }
        #endif
    }

    private func _releaseEnvironmentOutput() {
        #if os(Linux)
        guard environmentTextureId >= 0, let registry = drmTextureRegistry,
              let wl = waylandIntegration else { return }
        _desktop3DLog("release environment t=\(_desktop3DT)")
        _desktop3DGlideCurve?.dispose()
        _desktop3DGlide?.dispose()
        _desktop3DGlideCurve = nil
        _desktop3DGlide = nil
        _desktop3DGlidePath = nil
        if let frameId = (_environment as? FilamentRoomRenderer)?.frameTextureId, frameId >= 0 {
            registry.unregisterTexture(engine: wl.engine, id: frameId)
        }
        registry.setSceneMirror(ids: [], target: environmentTextureId)
        _sceneRepaints.removeValue(forKey: "\(_desktop3DViewId)")
        registry.unregisterTexture(engine: wl.engine, id: environmentTextureId)
        environmentTextureId = -1
        _environment = nil
        #endif
    }

    // MARK: Moving a window in the room

    /// The world ray under a screen point (logical px), from the eye.
    func _desktop3DRay(_ screen: Offset, camera: Camera3D, host: Rect)
        -> (origin: Vector3, dir: Vector3) {
        let focal = _desktop3DFocalPx(host)
        // View space: x right, y up, looking down -z. Screen y runs down.
        let v = Vector3((screen.dx - host.center.dx) / focal,
                        -(screen.dy - host.center.dy) / focal, -1)
        // The inverse of `_view`'s rotation: Ry(-yaw) · Rx(-pitch).
        var inv = Matrix4.rotationY(-camera.yaw)
        inv.multiply(Matrix4.rotationX(-camera.pitch))
        return (Vector3(camera.x, camera.y, camera.z), inv.perspectiveTransform(v))
    }

    /// Where a screen point lands on a pane's plane, in the pane's own
    /// axes: `u` along the pane (its screen-right), `v` up. nil when the
    /// ray runs away from the plane.
    func _desktop3DPlaneHit(_ screen: Offset, camera: Camera3D, host: Rect,
                            pose: WindowPose3D) -> (u: Double, v: Double)? {
        let (o, d) = _desktop3DRay(screen, camera: camera, host: host)
        let n = Vector3(sin(pose.yaw), 0, cos(pose.yaw))
        let p0 = Vector3(pose.x, pose.y, pose.z)
        let denom = d.dot(n)
        guard abs(denom) > 1e-4 else { return nil }
        let t = (p0 - o).dot(n) / denom
        guard t > 0 else { return nil }
        let hit = Vector3(o.x + d.x * t, o.y + d.y * t, o.z + d.z * t)
        let right = Vector3(cos(pose.yaw), 0, -sin(pose.yaw))
        return ((hit - p0).dot(right), hit.y - p0.y)
    }

    /// Slide a pane in its own plane by (du, dv) metres, and keep it on
    /// the wall and in the room: a pane on a side wall runs along z, one
    /// on the far wall along x, and none of them through the floor or
    /// the ceiling. The clamp is the room box less half the pane, which
    /// only bites along the axis the pane actually moves on.
    func _desktop3DSlidePane(_ win: WindowInfo, du: Double, dv: Double) {
        #if os(Linux)
        // A moon keeps its orbit, and a window on the square its place.
        if _desktop3DOrrery || _desktop3DVoxel { return }
        var p = win.pose3D
        let s = Self.k3DMetresPerPx
        let hw = win.rect.width * s / 2, hh = win.rect.height * s / 2
        p.x += cos(p.yaw) * du
        p.z -= sin(p.yaw) * du
        p.y += dv
        let m = 0.08
        p.x = min(Room3D.halfW - m, max(-Room3D.halfW + m, p.x))
        p.z = min(Room3D.depth - hw - m, max(hw + m, p.z))
        p.y = min(Room3D.height - hh - m, max(hh + m, p.y))
        setState { win.pose3D = p }
        #endif
    }

    /// A title-bar drag while the pane hangs in the scene: the pane
    /// follows the pointer along its wall. The delta is screen pixels;
    /// where the pointer was and is are both put through the pane's
    /// plane, so the pane moves by what the pointer moved ON THE WALL —
    /// exact at any angle, unlike a pixels-to-metres guess.
    func _desktop3DDragPane(_ winId: String, delta: Offset) {
        guard let win = windowManager.windows.first(where: { $0.id == winId }),
              win.pose3D.placed else { return }
        let host = _desktop3DHost
        let cam = _desktop3DEffectiveCamera(_desktop3DT)
        let a = _lastPointer
        let b = Offset(a.dx + delta.dx, a.dy + delta.dy)
        guard let h0 = _desktop3DPlaneHit(a, camera: cam, host: host, pose: win.pose3D),
              let h1 = _desktop3DPlaneHit(b, camera: cam, host: host, pose: win.pose3D)
        else {
            _desktop3DLog("drag \(win.title): no plane hit at \(a) / \(b)")
            return
        }
        _desktop3DLog("drag \(win.title): delta \(delta) -> du \(h1.u - h0.u) dv \(h1.v - h0.v)")
        _desktop3DSlidePane(win, du: h1.u - h0.u, dv: h1.v - h0.v)
    }

    /// A scroll on a title bar pushes the window away from the viewer or
    /// pulls it closer, along the line between them — the room's version
    /// of dragging a window around. With the pane on a wall, it slides
    /// along the wall instead.
    func _desktop3DScroll(_ winId: String, delta: Double) {
        guard _desktop3DOn, delta != 0,
              let win = windowManager.windows.first(where: { $0.id == winId }),
              win.pose3D.placed else { return }
        if _desktop3DScene {
            _desktop3DSlidePane(win, du: delta > 0 ? 0.25 : -0.25, dv: 0)
            return
        }
        let c = _camera3D
        var p = win.pose3D
        let dx = p.x - c.x, dy = p.y - c.y, dz = p.z - c.z
        let len = (dx * dx + dy * dy + dz * dz).squareRoot()
        guard len > 0.05 else { return }
        let next = min(12.0, max(0.9, len + (delta > 0 ? 0.25 : -0.25)))
        guard next != len else { return }
        let k = next / len
        p.x = c.x + dx * k; p.y = c.y + dy * k; p.z = c.z + dz * k
        setState { win.pose3D = p }
    }
}
