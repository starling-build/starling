// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import Glibc

// MARK: - FilamentRoomRenderer — the room, drawn by Filament
//
// The same slot as EnvironmentRenderer (the wallpaper's texture, rendered
// on the raster thread when the camera moves), but the picture comes from
// Filament through libstarling_room.so: a real PBR renderer lighting a
// glTF of the room from a captured sky, with shadows, ambient occlusion
// and tone mapping, instead of the hand-written GL and the offline bake.
//
// Filament runs on its own thread with its own EGL context, shared with
// the engine's, and draws straight into the texture the registry made for
// this slot. `sr_room_render` blocks until the GPU is done with it, so the
// engine samples a finished picture on the same frame.
//
// STARLING_ROOM=filament selects this renderer; STARLING_ROOM_DIR is the
// directory holding room.glb, room_ibl.ktx, room_skybox.ktx and room.json
// (build/tools/room-glb.py + cmgen), defaulting to the staged room/filament.
/// A window as the room renderer draws it: the window's centre and facing
/// in world metres, its size, and where inside it the client's picture
/// goes (below the title bar, which stays the shell's).
struct ScenePane: Equatable {
    var id: Int64
    /// A second scene instance may show the same client (workspace-rail preview).
    var textureId: Int64? = nil
    var x = 0.0, y = 0.0, z = 0.0, yaw = 0.0
    var width = 0.0, height = 0.0
    var contentDy = 0.0, contentWidth = 0.0, contentHeight = 0.0
    var flipY = false
    var focused = false
}

/// A sphere in the scene: a planet in an app's colour, or the sun (glow > 0).
struct SceneOrb: Equatable {
    var id: Int64
    var x = 0.0, y = 0.0, z = 0.0
    var radius = 0.2
    var r = 1.0, g = 1.0, b = 1.0
    var glow = 0.0
}

/// A label in the scene: a shell-drawn texture on a quad that faces the viewer.
struct SceneLabel: Equatable {
    var id: Int64          // the label's key in the scene
    var texture: Int64     // the engine texture it shows (several labels may share one)
    var x = 0.0, y = 0.0, z = 0.0
    var width = 0.3, height = 0.3
    /// nil: a billboard, always facing the viewer; else fixed, 0 = +z.
    var yaw: Double? = nil
}

/// A block in the scene: a cube wearing a shell-drawn texture on every
/// face — an app's icon as a thing standing in the world.
struct SceneBlock: Equatable {
    var id: Int64
    var texture: Int64
    var x = 0.0, y = 0.0, z = 0.0, yaw = 0.0
    /// Turned about its own z — a brick tipping over.
    var roll = 0.0
    var size = 0.9
}

/// What a world is, read from its world.json. The room is the default
/// world (a glTF lit by a captured sky); the orrery has no geometry of
/// its own and lays the desktop out round a sun.
struct World3D {
    struct WorkspaceRail {
        var x: Double, y: Double, z: Double
        var width: Double, height: Double
    }
    var workspaceRail: [WorkspaceRail] = []
    enum Kind: String { case room, orrery, voxel }
    var kind: Kind = .room
    /// A directional sun given by the world itself (else the room's bake).
    var sun: (dir: [Double], colour: [Double], lux: Double)? = nil
    /// Walking worlds: the eye above the ground, and the ring the windows
    /// stand on round the hub.
    var eyeHeight = 1.62
    var ringRadius = 7.5
    /// The ground: the y of the surface a walker stands on, per column.
    var heightOrigin = (x: 0, z: 0)
    var heightSize = (x: 0, z: 0)
    var heights: [Double] = []
    var navigation: WorldNavigation? = nil

    /// The ground height at a world position, or the hub's level.
    func ground(_ x: Double, _ z: Double) -> Double {
        if let floor = navigation?.ground(x, z) { return floor }
        guard heightSize.x > 0, heightSize.z > 0 else { return hub.y }
        let ix = min(heightSize.x - 1, max(0, Int(floor(x)) - heightOrigin.x))
        let iz = min(heightSize.z - 1, max(0, Int(floor(z)) - heightOrigin.z))
        return heights[ix * heightSize.z + iz]
    }
    var exposure: [Double] = [16, 1.0 / 125, 100]
    var iblIntensity = 30000.0
    var pointLight: (x: Double, y: Double, z: Double, r: Double, g: Double, b: Double, candela: Double)? = nil
    var hub = (x: 0.0, y: 0.6, z: 0.0)
    var sunRadius = 0.32
    var planetOrbit = 2.2
    var planetRadius = 0.22
    var moonOrbit = 0.62
    var moonScale = 0.12
    var cameraRadius = 5.2
    var cameraHeight = 1.0
    /// Entering is a dolly: the viewer starts this many metres behind the
    /// home spot and glides up to it over the tween (0: no dolly).
    var cameraDolly = 0.0
    var ambientAnimation = false
    /// What the windows' frames are made of, if not the plain slab: a
    /// block tile image in the world's directory, laid `block` metres to
    /// a tile over a frame `margin` wide and `depth` deep.
    var paneFrame: (texture: String, block: Double, margin: Double, depth: Double)? = nil
    /// A walking world's tower at the hub, if it has one: where the
    /// launcher's signs hang (on its +z face) and what the windows keep
    /// clear of.
    var tower: (x: Double, z: Double, half: Double, base: Double, top: Double)? = nil
    /// A walking world's sculpture at the hub: the launcher's app blocks
    /// spiral round this axis at this radius, from `base` up.
    var sculpture: (x: Double, z: Double, radius: Double, base: Double)? = nil
    /// A clock tower, if the world has one: the centre of its band, how
    /// far its sides are from that, and how big a face to hang on each.
    var clock: (x: Double, y: Double, z: Double, half: Double, size: Double)? = nil

    static func load(_ dir: String) -> World3D {
        var w = World3D()
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: dir + "/world.json")),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return w }
        if let k = j["kind"] as? String, let kind = Kind(rawValue: k) { w.kind = kind }
        w.ambientAnimation = j["ambient_animation"] as? Bool ?? false
        if let bays = j["workspaceRail"] as? [[String: Double]] {
            w.workspaceRail = bays.compactMap { b in
                guard let x = b["x"], let y = b["y"], let z = b["z"],
                      let width = b["width"], let height = b["height"],
                      [x, y, z, width, height].allSatisfy({ $0.isFinite }),
                      width > 0, height > 0 else { return nil }
                return WorkspaceRail(x: x, y: y, z: z, width: width, height: height)
            }
        }
        if let e = j["exposure"] as? [Double], e.count == 3 { w.exposure = e }
        if let i = j["ibl_intensity"] as? Double { w.iblIntensity = i }
        if let p = j["point_light"] as? [String: Any],
           let pos = p["position"] as? [Double], pos.count == 3,
           let col = p["colour"] as? [Double], col.count == 3,
           let cd = p["candela"] as? Double {
            w.pointLight = (pos[0], pos[1], pos[2], col[0], col[1], col[2], cd)
        }
        if let h = j["hub"] as? [Double], h.count == 3 { w.hub = (h[0], h[1], h[2]) }
        if let sc = j["sculpture"] as? [String: Any],
           let x = sc["x"] as? Double, let z = sc["z"] as? Double,
           let radius = sc["radius"] as? Double, let base = sc["base"] as? Double {
            w.sculpture = (x, z, radius, base)
        }
        if let ck = j["clock"] as? [String: Any],
           let x = ck["x"] as? Double, let y = ck["y"] as? Double, let z = ck["z"] as? Double,
           let half = ck["half"] as? Double, let size = ck["size"] as? Double {
            w.clock = (x, y, z, half, size)
        }
        if let t = j["tower"] as? [String: Any],
           let x = t["x"] as? Double, let z = t["z"] as? Double, let half = t["half"] as? Double,
           let base = t["base"] as? Double, let top = t["top"] as? Double {
            w.tower = (x, z, half, base, top)
        }
        if let v = j["sun_radius"] as? Double { w.sunRadius = v }
        if let v = j["planet_orbit"] as? Double { w.planetOrbit = v }
        if let v = j["planet_radius"] as? Double { w.planetRadius = v }
        if let v = j["moon_orbit"] as? Double { w.moonOrbit = v }
        if let v = j["moon_scale"] as? Double { w.moonScale = v }
        if let c = j["camera_home"] as? [String: Any] {
            if let v = c["radius"] as? Double { w.cameraRadius = v }
            if let v = c["height"] as? Double { w.cameraHeight = v }
            if let v = c["dolly"] as? Double { w.cameraDolly = v }
        }
        if let sun = j["sun"] as? [String: Any],
           let d = sun["dir"] as? [Double], d.count == 3,
           let c = sun["colour"] as? [Double], c.count == 3,
           let lux = sun["lux"] as? Double {
            w.sun = (d, c, lux)
        }
        if let v = j["eye_height"] as? Double { w.eyeHeight = v }
        if let v = j["ring_radius"] as? Double { w.ringRadius = v }
        if let f = j["pane_frame"] as? [String: Any], let t = f["texture"] as? String {
            w.paneFrame = (dir + "/" + t, f["block"] as? Double ?? 0.25,
                           f["margin"] as? Double ?? 0.25, f["depth"] as? Double ?? 0.25)
        }
        if let hm = j["heightmap"] as? [String: Any],
           let o = hm["origin"] as? [Int], o.count == 2,
           let sz = hm["size"] as? [Int], sz.count == 2,
           let hs = hm["heights"] as? [Double], hs.count == sz[0] * sz[1] {
            w.heightOrigin = (o[0], o[1]); w.heightSize = (sz[0], sz[1]); w.heights = hs
        }
        w.navigation = WorldNavigation.load(dir + "/navigation.json")
        return w
    }
}

final class FilamentRoomRenderer: EnvironmentRenderer {

    private typealias CreateFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> OpaquePointer?
    private typealias LoadFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    private typealias SetLightFn = @convention(c) (OpaquePointer?, UnsafePointer<Float>?, UnsafePointer<Float>?, Float, Float) -> Void
    private typealias SetExposureFn = @convention(c) (OpaquePointer?, Float, Float, Float) -> Void
    private typealias SetOutputFn = @convention(c) (OpaquePointer?, UInt32, Int32, Int32) -> Int32
    private typealias SetCameraFn = @convention(c) (OpaquePointer?, UnsafePointer<Float>?, UnsafePointer<Float>?, Float, Float) -> Void
    private typealias DestroyFn = @convention(c) (OpaquePointer?) -> Void
    private typealias RenderFn = @convention(c) (OpaquePointer?) -> Int32
    private typealias EGLGetCurrentFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias SetPaneFn = @convention(c) (OpaquePointer?, Int64, UnsafePointer<Float>?, Float, Float, Float, Float, Float, Float, UInt32, Int32, Int32, Int32, Int32) -> Int32
    private typealias RemovePaneFn = @convention(c) (OpaquePointer?, Int64) -> Void
    private typealias SetPaneStyleFn = @convention(c) (OpaquePointer?, UInt32, Int32, Int32, Float, Float, Float) -> Void
    private typealias SetPointLightFn = @convention(c) (OpaquePointer?, UnsafePointer<Float>?, UnsafePointer<Float>?, Float) -> Void
    private typealias SetOrbFn = @convention(c) (OpaquePointer?, Int64, UnsafePointer<Float>?, Float, UnsafePointer<Float>?, Float) -> Int32
    private typealias RemoveIdFn = @convention(c) (OpaquePointer?, Int64) -> Void
    private typealias SetLabelFn = @convention(c) (OpaquePointer?, Int64, UnsafePointer<Float>?, Float, Float, Float, UInt32, Int32, Int32) -> Int32
    private typealias SetBlockFn = @convention(c) (OpaquePointer?, Int64, UnsafePointer<Float>?, Float, Float, Float, UInt32, Int32, Int32) -> Int32

    /// The world this renderer shows, from its directory's world.json.
    let world: World3D

    private var _orbs: [SceneOrb] = []
    private var _labels: [SceneLabel] = []
    private var _blocks: [SceneBlock] = []
    private var knownOrbs = Set<Int64>()
    private var knownLabels = Set<Int64>()
    private var knownBlocks = Set<Int64>()
    private var fnSetBlock: SetBlockFn!
    private var fnRemoveBlock: RemoveIdFn!

    func setBlocks(_ blocks: [SceneBlock]) -> Bool {
        paneLock.lock()
        defer { paneLock.unlock() }
        if blocks == _blocks { return false }
        _blocks = blocks
        dirty = true
        return true
    }
    private var fnSetPointLight: SetPointLightFn!
    private var fnSetOrb: SetOrbFn!
    private var fnRemoveOrb: RemoveIdFn!
    private var fnSetLabel: SetLabelFn!
    private var fnRemoveLabel: RemoveIdFn!

    func setOrbs(_ orbs: [SceneOrb]) -> Bool {
        paneLock.lock()
        defer { paneLock.unlock() }
        if orbs == _orbs { return false }
        _orbs = orbs
        dirty = true
        return true
    }

    func setLabels(_ labels: [SceneLabel]) -> Bool {
        paneLock.lock()
        defer { paneLock.unlock() }
        if labels == _labels { return false }
        _labels = labels
        dirty = true
        return true
    }

    /// The client texture behind an engine texture id, on the raster
    /// thread (LinuxTextureRegistry.sceneTexture).
    var sceneTexture: ((Int64) -> (name: UInt32, width: Int, height: Int)?)?

    private let paneLock = NSLock()
    private var _panes: [ScenePane] = []
    private var knownPanes = Set<Int64>()
    private var fnSetPane: SetPaneFn!
    private var fnRemovePane: RemovePaneFn!
    private var fnSetPaneStyle: SetPaneStyleFn!

    /// The engine texture holding the world's frame tile (world.paneFrame),
    /// once the shell has decoded it; -1 for the plain slab. Any thread.
    var frameTextureId: Int64 {
        get { paneLock.lock(); defer { paneLock.unlock() }; return _frameTextureId }
        set {
            paneLock.lock()
            let changed = _frameTextureId != newValue
            _frameTextureId = newValue
            if changed { dirty = true }
            paneLock.unlock()
        }
    }
    private var _frameTextureId: Int64 = -1
    private var appliedFrame: UInt32 = 0

    /// Publish the windows that hang in the room; the next frame draws
    /// them. Returns whether anything changed.
    func setPanes(_ panes: [ScenePane]) -> Bool {
        paneLock.lock()
        defer { paneLock.unlock() }
        if panes == _panes { return false }
        _panes = panes
        dirty = true
        return true
    }

    /// Where the room's files are.
    let roomDir: String

    private var room: OpaquePointer?
    private var failed = false
    private var lib: UnsafeMutableRawPointer?
    private var fnLoad: LoadFn!
    private var fnSetLight: SetLightFn!
    private var fnSetExposure: SetExposureFn!
    private var fnSetOutput: SetOutputFn!
    private var fnSetCamera: SetCameraFn!
    private var fnRender: RenderFn!
    private var fnDestroy: DestroyFn!

    /// Called by the registry on the raster thread, after the last callback.
    /// An output resize/disconnect must release its native scene on that thread.
    func releaseScene() {
        if let room { fnDestroy?(room); self.room = nil }
        if let lib { dlclose(lib); self.lib = nil }
    }

    init(width: Int, height: Int, roomDir: String) {
        self.roomDir = roomDir
        self.world = World3D.load(roomDir)
        super.init(width: width, height: height)
    }

    /// The scene clock drives the old renderer's water and clouds; this
    /// room is still, and only a camera move earns a frame.
    override func tick(_ seconds: Double) {}

    /// Where the renderer's library may be: named outright, beside the
    /// shell (the staged tree and the package put it there), or on the
    /// loader's path.
    static func libraryCandidates() -> [String] {
        var candidates: [String] = []
        if let p = ProcessInfo.processInfo.environment["STARLING_ROOM_LIB"] { candidates.append(p) }
        if let real = realpath("/proc/self/exe", nil) {
            let selfDir = (String(cString: real) as NSString).deletingLastPathComponent
            free(real)
            candidates.append(selfDir + "/libstarling_room.so")
        }
        candidates.append("libstarling_room.so")
        return candidates
    }

    /// Whether the library is here to be loaded — asked before the shell
    /// chooses this renderer over its own GL room, so a package built on a
    /// box without Filament still has a 3D desktop, just the room. The
    /// probe loads the library once; start() gets the same handle back.
    static let isAvailable: Bool = {
        for path in libraryCandidates() {
            if let h = dlopen(path, RTLD_NOW | RTLD_LOCAL) { dlclose(h); return true }
        }
        return false
    }()

    // MARK: Raster thread

    override func renderToTexture(_ textureName: UInt32) {
        dirty = false
        if failed { return }
        if room == nil {
            guard start() else {
                failed = true
                FileHandle.standardError.write(Data(
                    "[room] Filament renderer unavailable; the slot stays black\n".utf8))
                return
            }
        }
        let cam = camera
        guard fnSetOutput(room, textureName, Int32(width), Int32(height)) == 0 else { return }
        var proj = Self.projection(aspect: Double(width) / Double(height),
                                   tanHalfFovX: cam.tanHalfFovX)
        proj[8] = Float(cam.lensShiftX)
        proj[9] = Float(cam.lensShiftY)
        var view = Self.view(cam)
        fnSetCamera(room, &view, &proj, 0.08, 4000)
        syncPanes()
        syncOrbsAndLabels()
        _ = fnRender(room)
    }

    private func syncOrbsAndLabels() {
        paneLock.lock()
        let orbs = _orbs, labels = _labels, blocks = _blocks
        paneLock.unlock()
        var liveBlocks = Set<Int64>()
        for b in blocks {
            guard let tex = sceneTexture?(b.texture), tex.name != 0 else { continue }
            var c: [Float] = [Float(b.x), Float(b.y), Float(b.z)]
            if fnSetBlock(room, b.id, &c, Float(b.yaw), Float(b.roll), Float(b.size),
                          tex.name, Int32(tex.width), Int32(tex.height)) == 0 { liveBlocks.insert(b.id) }
        }
        for id in knownBlocks.subtracting(liveBlocks) { fnRemoveBlock(room, id) }
        knownBlocks = liveBlocks
        var live = Set<Int64>()
        for o in orbs {
            var c: [Float] = [Float(o.x), Float(o.y), Float(o.z)]
            var col: [Float] = [Float(o.r), Float(o.g), Float(o.b)]
            if fnSetOrb(room, o.id, &c, Float(o.radius), &col, Float(o.glow)) == 0 { live.insert(o.id) }
        }
        for id in knownOrbs.subtracting(live) { fnRemoveOrb(room, id) }
        knownOrbs = live
        var liveLabels = Set<Int64>()
        for l in labels {
            guard let tex = sceneTexture?(l.texture), tex.name != 0 else { continue }
            var c: [Float] = [Float(l.x), Float(l.y), Float(l.z)]
            if fnSetLabel(room, l.id, &c, Float(l.width), Float(l.height),
                          l.yaw.map { Float($0) } ?? Float.nan,
                          tex.name, Int32(tex.width), Int32(tex.height)) == 0 { liveLabels.insert(l.id) }
        }
        for id in knownLabels.subtracting(liveLabels) { fnRemoveLabel(room, id) }
        knownLabels = liveLabels
    }

    /// Hand every published pane to the scene with its client texture as
    /// it stands this frame, and take down the ones that have gone.
    private func syncPanes() {
        paneLock.lock()
        let panes = _panes, frameId = _frameTextureId
        paneLock.unlock()
        // The frames' style, once its tile is a texture (the tile decodes
        // asynchronously, so the first frames may hang in plain slabs).
        if let f = world.paneFrame, frameId >= 0, let tex = sceneTexture?(frameId), tex.name != 0 {
            if tex.name != appliedFrame {
                fnSetPaneStyle(room, tex.name, Int32(tex.width), Int32(tex.height),
                               Float(f.block), Float(f.margin), Float(f.depth))
                appliedFrame = tex.name
            }
        } else if appliedFrame != 0 {
            fnSetPaneStyle(room, 0, 0, 0, 0, 0, 0)
            appliedFrame = 0
        }
        var live = Set<Int64>()
        for p in panes {
            guard let tex = sceneTexture?(p.textureId ?? p.id), tex.name != 0 else { continue }
            var c: [Float] = [Float(p.x), Float(p.y), Float(p.z)]
            let rc = fnSetPane(room, p.id, &c, Float(p.yaw), Float(p.width), Float(p.height),
                               Float(p.contentDy), Float(p.contentWidth), Float(p.contentHeight),
                               tex.name, Int32(tex.width), Int32(tex.height),
                               p.flipY ? 1 : 0, p.focused ? 1 : 0)
            if rc == 0 { live.insert(p.id) }
        }
        for id in knownPanes.subtracting(live) { fnRemovePane(room, id) }
        knownPanes = live
    }

    private func start() -> Bool {
        // The engine's context is current on this thread: that is the one
        // Filament's context shares with, on the same display.
        guard let resolver = glProcAddressResolver,
              let pDisplay = resolver("eglGetCurrentDisplay"),
              let pContext = resolver("eglGetCurrentContext") else {
            FileHandle.standardError.write(Data("[room] no EGL entry points\n".utf8))
            return false
        }
        let display = unsafeBitCast(pDisplay, to: EGLGetCurrentFn.self)()
        let context = unsafeBitCast(pContext, to: EGLGetCurrentFn.self)()
        guard display != nil, context != nil else {
            FileHandle.standardError.write(Data("[room] no current EGL context\n".utf8))
            return false
        }

        for path in Self.libraryCandidates() {
            if let h = dlopen(path, RTLD_NOW | RTLD_LOCAL) { lib = h; break }
        }
        guard let lib else {
            FileHandle.standardError.write(Data(
                "[room] libstarling_room.so not found (build/build-room.sh): \(String(cString: dlerror()))\n".utf8))
            return false
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(lib, name) else {
                FileHandle.standardError.write(Data("[room] missing \(name)\n".utf8))
                return nil
            }
            return unsafeBitCast(p, to: type)
        }
        guard let create = sym("sr_room_create", CreateFn.self),
              let load = sym("sr_room_load", LoadFn.self),
              let setLight = sym("sr_room_set_light", SetLightFn.self),
              let setExposure = sym("sr_room_set_exposure", SetExposureFn.self),
              let setOutput = sym("sr_room_set_output", SetOutputFn.self),
              let setCamera = sym("sr_room_set_camera", SetCameraFn.self),
              let render = sym("sr_room_render", RenderFn.self),
              let destroy = sym("sr_room_destroy", DestroyFn.self),
              let setPane = sym("sr_room_set_pane", SetPaneFn.self),
              let removePane = sym("sr_room_remove_pane", RemovePaneFn.self),
              let setPaneStyle = sym("sr_room_set_pane_style", SetPaneStyleFn.self),
              let setPointLight = sym("sr_room_set_point_light", SetPointLightFn.self),
              let setOrb = sym("sr_room_set_orb", SetOrbFn.self),
              let removeOrb = sym("sr_room_remove_orb", RemoveIdFn.self),
              let setLabel = sym("sr_room_set_label", SetLabelFn.self),
              let removeLabel = sym("sr_room_remove_label", RemoveIdFn.self),
              let setBlock = sym("sr_room_set_block", SetBlockFn.self),
              let removeBlock = sym("sr_room_remove_block", RemoveIdFn.self) else { return false }
        fnLoad = load; fnSetLight = setLight; fnSetExposure = setExposure
        fnSetOutput = setOutput; fnSetCamera = setCamera; fnRender = render; fnDestroy = destroy
        fnSetPane = setPane; fnRemovePane = removePane; fnSetPaneStyle = setPaneStyle
        fnSetPointLight = setPointLight; fnSetOrb = setOrb; fnRemoveOrb = removeOrb
        fnSetLabel = setLabel; fnRemoveLabel = removeLabel
        fnSetBlock = setBlock; fnRemoveBlock = removeBlock

        guard let r = create(display, context) else { return false }
        room = r
        // A world with geometry loads its glTF; one without (the orrery)
        // loads only its sky.
        let glb = FileManager.default.fileExists(atPath: roomDir + "/room.glb") ? roomDir + "/room.glb" : ""
        let rc = fnLoad(r, glb, roomDir + "/room_ibl.ktx", roomDir + "/room_skybox.ktx")
        guard rc == 0 else {
            FileHandle.standardError.write(Data("[room] load failed (\(rc)) from \(roomDir)\n".utf8))
            return false
        }

        // The sun, from the exporter's sidecar; strengths and exposure
        // from the environment while the look is being settled.
        let env = ProcessInfo.processInfo.environment
        var sunDir: [Float] = [-0.35, 0.45, -0.82]
        var sunCol: [Float] = [1, 0.95, 0.85]
        if let d = try? Data(contentsOf: URL(fileURLWithPath: roomDir + "/room.json")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let s = j["sun_dir"] as? [Double], s.count == 3 { sunDir = s.map { Float($0) } }
            if let c = j["sun_colour"] as? [Double], c.count == 3 {
                let m = max(c.max() ?? 1, 1e-6)
                sunCol = c.map { Float($0 / m) }
            }
        }
        var sunLux = Float(env["STARLING_ROOM_SUN_LUX"] ?? "") ?? (world.kind == .room ? 100000 : 0)
        if let ws = world.sun {
            sunDir = ws.dir.map { Float($0) }
            sunCol = ws.colour.map { Float($0) }
            if env["STARLING_ROOM_SUN_LUX"] == nil { sunLux = Float(ws.lux) }
        }
        let iblLux = Float(env["STARLING_ROOM_IBL_LUX"] ?? "") ?? Float(world.iblIntensity)
        fnSetLight(r, sunDir, sunCol, sunLux, iblLux)
        if let pl = world.pointLight {
            var pos: [Float] = [Float(pl.x), Float(pl.y), Float(pl.z)]
            var col: [Float] = [Float(pl.r), Float(pl.g), Float(pl.b)]
            fnSetPointLight(r, &pos, &col, Float(pl.candela))
        }
        var exposure = world.exposure.map { Float($0) }
        if let e = env["STARLING_ROOM_EXPOSURE"] {
            let p = e.split(separator: ",").compactMap { Float($0) }
            if p.count == 3 { exposure = p }
        }
        if exposure.count == 3 { fnSetExposure(r, exposure[0], exposure[1], exposure[2]) }
        return true
    }
}
#endif
