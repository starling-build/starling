// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation

// MARK: - EnvironmentRenderer (the 3D desktop's tier-0 environment)
//
// The wallpaper becomes a place: the picture recedes to the far wall of a
// box, and the floor, ceiling and side walls grow out of its four edges
// and come toward the viewer, carrying the picture's own colours, blurred
// and falling away into the dark. The room is made OUT of the picture
// rather than framing it. It renders into the texture the wallpaper's
// widget slot shows while 3D is on, on the raster thread inside the
// engine's external-texture callback (GLRenderer's contract), reading the
// wallpaper's own uploaded GL texture as its one source.
//
// The unfold is geometric: every vertex carries two positions — where it
// sits on a flat quad that exactly fills the view, and where it sits in
// the room — and the vertex shader mixes them by `t`. At t = 0 the output
// IS the flat wallpaper: the back wall fills the view undimmed and the
// other four surfaces have collapsed onto the quad's edges, where they
// are zero-area and rasterise nothing.
//
// Why a box and not the cylinder this started as: a cylinder centred on
// the eye is depth-flat by construction — every point on it is exactly R
// from the viewer, so it has no parallax and no perspective, and through
// a desktop lens it is indistinguishable from the flat picture it was
// made from. No amount of tuning fixes that. A box has surfaces at
// genuinely different distances, which is the only thing that reads as
// depth on a monitor.
//
// The room is defined against the frustum rather than in world units, so
// what reaches the screen does not depend on the lens or on the wall's
// distance: `kRoomCover` — how much of the view the picture still fills
// once the room is open — is the knob that changes the picture.
//
// GL state: the engine calls resetContext(kAll_GrBackendState) after every
// external-texture callback, so nothing set here leaks into Skia's cache;
// the FBO binding and viewport are still restored out of courtesy.

private typealias GLGenBuffersFunc = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
private typealias GLBindBufferFunc = @convention(c) (UInt32, UInt32) -> Void
private typealias GLBufferDataFunc = @convention(c) (UInt32, Int, UnsafeRawPointer?, UInt32) -> Void
private typealias GLCreateShaderFunc = @convention(c) (UInt32) -> UInt32
private typealias GLShaderSourceFunc = @convention(c) (UInt32, Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<Int32>?) -> Void
private typealias GLCompileShaderFunc = @convention(c) (UInt32) -> Void
private typealias GLGetShaderivFunc = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void
private typealias GLGetShaderInfoLogFunc = @convention(c) (UInt32, Int32, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CChar>?) -> Void
private typealias GLCreateProgramFunc = @convention(c) () -> UInt32
private typealias GLAttachShaderFunc = @convention(c) (UInt32, UInt32) -> Void
private typealias GLLinkProgramFunc = @convention(c) (UInt32) -> Void
private typealias GLGetProgramivFunc = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<Int32>?) -> Void
private typealias GLGetProgramInfoLogFunc = @convention(c) (UInt32, Int32, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CChar>?) -> Void
private typealias GLUseProgramFunc = @convention(c) (UInt32) -> Void
private typealias GLGetAttribLocationFunc = @convention(c) (UInt32, UnsafePointer<CChar>?) -> Int32
private typealias GLGetUniformLocationFunc = @convention(c) (UInt32, UnsafePointer<CChar>?) -> Int32
private typealias GLUniform1fFunc = @convention(c) (Int32, Float) -> Void
private typealias GLUniform3fvFunc = @convention(c) (Int32, Int32, UnsafePointer<Float>?) -> Void
private typealias GLUniform1iFunc = @convention(c) (Int32, Int32) -> Void
private typealias GLUniformMatrix4fvFunc = @convention(c) (Int32, Int32, UInt8, UnsafePointer<Float>?) -> Void
private typealias GLVertexAttribPointerFunc = @convention(c) (UInt32, Int32, UInt32, UInt8, Int32, UnsafeRawPointer?) -> Void
private typealias GLEnableVertexAttribArrayFunc = @convention(c) (UInt32) -> Void
private typealias GLDrawArraysFunc = @convention(c) (UInt32, Int32, Int32) -> Void
private typealias GLActiveTextureFunc = @convention(c) (UInt32) -> Void
private typealias GLBindTextureFunc = @convention(c) (UInt32, UInt32) -> Void
private typealias GLTexParameteriFunc = @convention(c) (UInt32, UInt32, Int32) -> Void
private typealias GLGenerateMipmapFunc = @convention(c) (UInt32) -> Void
private typealias GLGetErrorFunc = @convention(c) () -> UInt32
private typealias GLGenFramebuffersFunc = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
private typealias GLGenRenderbuffersFunc = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
private typealias GLBindRenderbufferFunc = @convention(c) (UInt32, UInt32) -> Void
private typealias GLRenderbufferStorageFunc = @convention(c) (UInt32, UInt32, Int32, Int32) -> Void
private typealias GLFramebufferRenderbufferFunc = @convention(c) (UInt32, UInt32, UInt32, UInt32) -> Void
private typealias GLDepthFuncFunc = @convention(c) (UInt32) -> Void
private typealias GLDepthMaskFunc = @convention(c) (UInt8) -> Void
private typealias GLDrawElementsFunc = @convention(c) (UInt32, Int32, UInt32, UnsafeRawPointer?) -> Void
private typealias GLGenTexturesFunc = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
private typealias GLTexImage2DFunc = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
private typealias GLBindFramebufferFunc = @convention(c) (UInt32, UInt32) -> Void
private typealias GLFramebufferTexture2DFunc = @convention(c) (UInt32, UInt32, UInt32, UInt32, Int32) -> Void
private typealias GLViewportFunc = @convention(c) (Int32, Int32, Int32, Int32) -> Void
private typealias GLClearColorFunc = @convention(c) (Float, Float, Float, Float) -> Void
private typealias GLClearFunc = @convention(c) (UInt32) -> Void
private typealias GLEnableFunc = @convention(c) (UInt32) -> Void
private typealias GLDisableFunc = @convention(c) (UInt32) -> Void
private typealias GLFlushFunc = @convention(c) () -> Void
private typealias GLGetIntegervFunc = @convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Void
private typealias GLGenVertexArraysFunc = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
private typealias GLReadPixelsFunc = @convention(c) (Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeMutableRawPointer?) -> Void
private typealias GLBindVertexArrayFunc = @convention(c) (UInt32) -> Void

private let GL_ARRAY_BUFFER: UInt32 = 0x8892
private let GL_STATIC_DRAW: UInt32 = 0x88E4
private let GL_VERTEX_SHADER: UInt32 = 0x8B31
private let GL_FRAGMENT_SHADER: UInt32 = 0x8B30
private let GL_COMPILE_STATUS: UInt32 = 0x8B81
private let GL_LINK_STATUS: UInt32 = 0x8B82
private let GL_FLOAT: UInt32 = 0x1406
private let GL_TRIANGLES: UInt32 = 0x0004
private let GL_TEXTURE0: UInt32 = 0x84C0
private let GL_TEXTURE_2D: UInt32 = 0x0DE1
private let GL_TEXTURE_MIN_FILTER: UInt32 = 0x2801
private let GL_TEXTURE_MAG_FILTER: UInt32 = 0x2800
private let GL_TEXTURE_WRAP_S: UInt32 = 0x2802
private let GL_TEXTURE_WRAP_T: UInt32 = 0x2803
private let GL_CLAMP_TO_EDGE: Int32 = 0x812F
private let GL_LINEAR: Int32 = 0x2601
private let GL_LINEAR_MIPMAP_LINEAR: Int32 = 0x2703
private let GL_FRAMEBUFFER: UInt32 = 0x8D40
private let GL_COLOR_ATTACHMENT0: UInt32 = 0x8CE0
private let GL_FRAMEBUFFER_BINDING: UInt32 = 0x8CA6
private let GL_VIEWPORT: UInt32 = 0x0BA2
private let GL_COLOR_BUFFER_BIT: UInt32 = 0x4000
private let GL_SCISSOR_TEST: UInt32 = 0x0C11
private let GL_DEPTH_TEST: UInt32 = 0x0B71
private let GL_BLEND: UInt32 = 0x0BE2
private let GL_CULL_FACE: UInt32 = 0x0B44
private let GL_STENCIL_TEST: UInt32 = 0x0B90
private let GL_RENDERBUFFER: UInt32 = 0x8D41
private let GL_DEPTH_ATTACHMENT: UInt32 = 0x8D00
private let GL_DEPTH_COMPONENT24: UInt32 = 0x81A6
private let GL_DEPTH_BUFFER_BIT: UInt32 = 0x0100
private let GL_LEQUAL: UInt32 = 0x0203
private let GL_CCW: UInt32 = 0x0901
private let GL_ELEMENT_ARRAY_BUFFER: UInt32 = 0x8893
private let GL_UNSIGNED_INT: UInt32 = 0x1405
private let GL_RGBA: UInt32 = 0x1908
private let GL_UNSIGNED_BYTE: UInt32 = 0x1401

/// What the platform thread last decided the camera should be, and the
/// hall it is standing in. Read on the raster thread under the renderer's
/// lock. Everything here is in METRES — the shell owns the room's shape,
/// the renderer just draws it from where the viewer is.
struct EnvironmentCamera: Equatable {
    /// 0 = the flat wallpaper, 1 = the room. Follows the enter/leave tween.
    var t: Double = 0
    /// Where the viewer is standing, and where they are looking.
    var x: Double = 0
    var y: Double = 2
    var z: Double = 4.6
    var yaw: Double = 0
    var pitch: Double = 0
    /// The picture on the far wall, at z = 0, its bottom on the floor.
    var pictureWidth: Double = 6.4
    var pictureHeight: Double = 4.0
    /// The hall: x is centred on 0, y runs up from the floor, z runs back
    /// from the picture toward the viewer.
    var roomWidth: Double = 11
    var roomHeight: Double = 4.6
    var roomDepth: Double = 16
    /// The lens, shared with the windows so the two agree exactly.
    var tanHalfFovX: Double = 0.7002
    /// Off-axis lens for a shared desktop spanning several outputs.
    var lensShiftX: Double = 0
    var lensShiftY: Double = 0
    /// The daylight's colour, taken from the wallpaper: the room is lit by
    /// what is outside its window, so a dusk view gives a dim warm room
    /// and a noon view a bright one. This is the wallpaper's average —
    /// Mica's ingredient, doing a second job.
    var lightR: Double = 0.55
    var lightG: Double = 0.60
    var lightB: Double = 0.70
}

class EnvironmentRenderer: GLRenderer {

    // MARK: Tuning (world units: the flat quad sits 1.0 in front of the eye)

    /// The lens, shared with the windows' arc so the two agree on where
    /// "straight ahead" converges: tan(fovX/2) = 0.5 / k3DFocalScreens.
    static let kTanHalfFovX = 0.5 / 1.5
    /// How far away the picture hangs. Only sets the scale: the room is
    /// built against the frustum, so the same image reaches the screen at
    /// any distance. It fixes what "world units" mean for the eye travel,
    /// and where the windows' arc sits relative to the wall (an unfocused
    /// window at depth 1 lands at 1/kNeighbourScale ≈ 1.43, comfortably
    /// in front of it).
    static let kWallDistance = 2.4
    /// How much of the view the picture still fills once the room is
    /// open. 1.0 would be the flat wallpaper and no room at all; much
    /// below 0.55 and the wallpaper stops being the subject of its own
    /// desktop. This is THE art-direction knob.
    static let kRoomCover = 0.66
    /// The picture's centre above the eye line, as a fraction of its own
    /// half-height: the eye sits low in the picture, so there is more
    /// floor than ceiling — which is what standing in a room looks like.
    static let kRoomLift = 0.14
    /// Where the room stops short of the eye, as a fraction of the wall's
    /// distance. Everything this near is far off the edges of the screen.
    static let kRoomNear = 0.02
    /// The relief: how far the NEAREST part of the picture is pulled off
    /// the wall toward the eye, as a fraction of the wall's distance. The
    /// displacement runs ALONG THE VIEW RAY, so the picture is unchanged
    /// from the home eye position however deep the relief is — it shows
    /// up only as parallax when the eye moves, and as real distance when
    /// something has to pass in front of or behind it.
    ///
    /// It can be this large because of what a depth map of a landscape
    /// photograph actually contains: a ground plane, and nothing else.
    /// Everything past the foreground really is at infinity, so there are
    /// no silhouettes for a big displacement to rubber-band.
    static let kRelief = 0.42
    /// The relief fades out over this fraction of the picture at the top
    /// and side edges, so the wall still meets the ceiling and side walls
    /// exactly where they expect it. NOT at the bottom: that edge is the
    /// near ground, which is the whole of the relief on a landscape, and
    /// cutting it there would fold the picture right where the eye is
    /// looking. The floor follows the wall's bottom edge instead.
    static let kReliefEdgeFade = 0.06
    /// Quads across the picture. The relief's silhouettes are only as
    /// sharp as this: a bridge tower a hundred pixels wide spans about
    /// eight quads at 192, which is enough that its edge does not visibly
    /// rubber-band under the parallax this camera has.
    static let kWallQuads = (192, 108)

    // Each surface other than the picture is (lit, fade, blur base, blur
    // reach): its brightness where it meets the picture, how fast it
    // falls into the dark as it comes toward the viewer, and the mip bias
    // it samples the picture with at the wall and at the near end. `lit`
    // near 1 matters — a surface that meets the picture at half
    // brightness draws a hard frame around it, and the picture stops
    // opening into the room and starts hanging on a wall.
    static let kFloorShade = (0.92, 2.6, 1.5, 3.0)
    static let kCeilShade = (0.75, 3.6, 2.5, 3.0)
    static let kSideShade = (0.92, 3.2, 2.0, 3.0)
    /// Fraction of the picture each surface mirrors as it comes forward:
    /// the floor shows its bottom band, the ceiling its top, the side
    /// walls their own columns.
    static let kFloorReflect = 0.34
    static let kCeilReflect = 0.20
    static let kSideReflect = 0.22
    /// The eye's full parallax travel, in world units: 3% of the flat
    /// quad's width per unit of pan. The wall at 2.4 shifts by a hundredth
    /// of that; the floor a step in front of the viewer, by half as much
    /// again — and that difference is the whole point. Matches
    /// `k3DEyeTravel`, which moves the windows by the same eye: an
    /// unfocused window sits at 1.43, between the two.
    static let kEyeTravel = 0.03 * 2 * kTanHalfFovX

    /// Called on the raster thread with the GL context current: the
    /// wallpaper's texture name and size, or nil while it is not uploaded.
    var sourceTexture: (() -> (name: UInt32, width: Int, height: Int)?)?


    /// Seconds since the scene opened. The sky and the water move with
    /// it, so the place is weather rather than a photograph.
    private var _clock: Double = 0
    var sceneClock: Double {
        get { cameraLock.lock(); defer { cameraLock.unlock() }; return _clock }
    }
    /// Advance the clock. Called from a ticker on the platform thread; the
    /// renderer is marked dirty by the caller.
    func tick(_ seconds: Double) {
        cameraLock.lock()
        _clock = seconds
        cameraLock.unlock()
        dirty = true
    }

    private let cameraLock = NSLock()
    private var _camera = EnvironmentCamera()

    /// The baked room, and the two atlases it is textured with. Handed
    /// over by the shell once the files are read; the renderer uploads
    /// them on the raster thread at the next frame.
    var roomAsset: (mesh: Room3D.Asset,
                    diffuse: (data: [UInt8], w: Int, h: Int),
                    arm: (data: [UInt8], w: Int, h: Int),
                    sky: (data: [UInt8], w: Int, h: Int))? {
        get { cameraLock.lock(); defer { cameraLock.unlock() }; return _room }
        set {
            cameraLock.lock(); _room = newValue; _roomStale = true; cameraLock.unlock()
            dirty = true
        }
    }
    private var _room: (mesh: Room3D.Asset,
                        diffuse: (data: [UInt8], w: Int, h: Int),
                        arm: (data: [UInt8], w: Int, h: Int),
                        sky: (data: [UInt8], w: Int, h: Int))?
    private var _roomStale = false
    private var ibo: UInt32 = 0
    private var indexCount: Int32 = 0
    private var texDiffuse: UInt32 = 0, texArm: UInt32 = 0, texSky: UInt32 = 0
    private var uDiffuse: Int32 = -1, uArm: Int32 = -1, uSky: Int32 = -1
    private var uSH: Int32 = -1, uSunCol: Int32 = -1, uSkyRange: Int32 = -1

    // GL objects (raster thread only)
    private var glReady = false
    private var loggedDraw = false
    private var program: UInt32 = 0
    private var vbo: UInt32 = 0
    private var vao: UInt32 = 0
    private var fbo: UInt32 = 0
    private var vertexCount: Int32 = 0
    private var mipmapped: Set<UInt32> = []
    private var aPos: Int32 = -1, aNrm: Int32 = -1, aUV: Int32 = -1
    private var aAO: Int32 = -1, aSun: Int32 = -1, aMat: Int32 = -1
    private var uTime: Int32 = -1
    private var uEye: Int32 = -1, uEyeV: Int32 = -1, uFade: Int32 = -1
    private var uLight: Int32 = -1
    private var uProj: Int32 = -1, uView: Int32 = -1, uT: Int32 = -1, uTex: Int32 = -1
    private var uMip: Int32 = -1

    private var _glGenBuffers: GLGenBuffersFunc!
    private var _glBindBuffer: GLBindBufferFunc!
    private var _glBufferData: GLBufferDataFunc!
    private var _glCreateShader: GLCreateShaderFunc!
    private var _glShaderSource: GLShaderSourceFunc!
    private var _glCompileShader: GLCompileShaderFunc!
    private var _glGetShaderiv: GLGetShaderivFunc!
    private var _glGetShaderInfoLog: GLGetShaderInfoLogFunc!
    private var _glCreateProgram: GLCreateProgramFunc!
    private var _glAttachShader: GLAttachShaderFunc!
    private var _glLinkProgram: GLLinkProgramFunc!
    private var _glGetProgramiv: GLGetProgramivFunc!
    private var _glGetProgramInfoLog: GLGetProgramInfoLogFunc!
    private var _glUseProgram: GLUseProgramFunc!
    private var _glGetAttribLocation: GLGetAttribLocationFunc!
    private var _glGetUniformLocation: GLGetUniformLocationFunc!
    private var _glUniform1f: GLUniform1fFunc!
    private var _glUniform3fv: GLUniform3fvFunc?
    private var _glUniform1i: GLUniform1iFunc!
    private var _glUniformMatrix4fv: GLUniformMatrix4fvFunc!
    private var _glVertexAttribPointer: GLVertexAttribPointerFunc!
    private var _glEnableVertexAttribArray: GLEnableVertexAttribArrayFunc!
    private var _glDrawArrays: GLDrawArraysFunc!
    private var _glActiveTexture: GLActiveTextureFunc!
    private var _glBindTexture: GLBindTextureFunc!
    private var _glTexParameteri: GLTexParameteriFunc!
    private var _glGenerateMipmap: GLGenerateMipmapFunc!
    private var _glGetError: GLGetErrorFunc!
    private var _glGenFramebuffers: GLGenFramebuffersFunc!
    private var _glGenRenderbuffers: GLGenRenderbuffersFunc!
    private var _glBindRenderbuffer: GLBindRenderbufferFunc!
    private var _glRenderbufferStorage: GLRenderbufferStorageFunc!
    private var _glFramebufferRenderbuffer: GLFramebufferRenderbufferFunc!
    private var _glDepthFunc: GLDepthFuncFunc!
    private var _glDepthMask: GLDepthMaskFunc!
    private var _glDrawElements: GLDrawElementsFunc!
    private var _glGenTextures: GLGenTexturesFunc!
    private var _glTexImage2D: GLTexImage2DFunc!
    private var depthRb: UInt32 = 0
    private var _glBindFramebuffer: GLBindFramebufferFunc!
    private var _glFramebufferTexture2D: GLFramebufferTexture2DFunc!
    private var _glViewport: GLViewportFunc!
    private var _glClearColor: GLClearColorFunc!
    private var _glClear: GLClearFunc!
    private var _glEnable: GLEnableFunc!
    private var _glDisable: GLDisableFunc!
    private var _glFlush: GLFlushFunc!
    private var _glGetIntegerv: GLGetIntegervFunc!
    private var _glGenVertexArrays: GLGenVertexArraysFunc?
    private var _glReadPixels: GLReadPixelsFunc!
    /// STARLING_3D_DUMP=<path>: write the rendered environment as a PPM
    /// after each render, for looking at the room without the desktop
    /// drawn over it.
    private let dumpPath = ProcessInfo.processInfo.environment["STARLING_3D_DUMP"]
    private var _glBindVertexArray: GLBindVertexArrayFunc?

    // MARK: Platform thread

    /// Publish a camera; the next engine frame re-renders with it.
    func setCamera(_ cam: EnvironmentCamera) -> Bool {
        cameraLock.lock()
        defer { cameraLock.unlock() }
        if cam == _camera { return false }
        _camera = cam
        dirty = true
        return true
    }

    var camera: EnvironmentCamera {
        cameraLock.lock(); defer { cameraLock.unlock() }
        return _camera
    }

    // MARK: Raster thread

    override func renderToTexture(_ textureName: UInt32) {
        dirty = false
        if !glReady { loadGL(); glReady = true }
        guard program != 0 else { return }
        let cam = camera

        var prevFbo: Int32 = 0
        _glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFbo)
        var prevViewport = [Int32](repeating: 0, count: 4)
        _glGetIntegerv(GL_VIEWPORT, &prevViewport)

        _glBindFramebuffer(GL_FRAMEBUFFER, fbo)
        _glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textureName, 0)
        _glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                                   GL_RENDERBUFFER, depthRb)
        _glViewport(0, 0, Int32(width), Int32(height))
        _glDisable(GL_SCISSOR_TEST)
        _glEnable(GL_DEPTH_TEST)
        _glDepthFunc(GL_LEQUAL)
        // Skia leaves depth WRITES off, and a depth clear is a no-op while
        // they are: the buffer keeps whatever was in it, every fragment
        // fails LEQUAL, and the room draws nothing at all while the colour
        // clear still works — which looks exactly like a geometry bug.
        _glDepthMask(1)
        _glDisable(GL_BLEND)
        _glDisable(GL_CULL_FACE)
        _glDisable(GL_STENCIL_TEST)
        _glClearColor(0.02, 0.02, 0.03, 1.0)
        _glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        if let src = sourceTexture?(), src.width > 0, src.height > 0 {
            uploadRoomIfNeeded()
            guard indexCount > 0 else { return }

            _glActiveTexture(GL_TEXTURE0)
            _glBindTexture(GL_TEXTURE_2D, src.name)
            // Mip chain once per source: the floor and the edge extension
            // sample it with an LOD bias, which is the cheapest blur there is.
            var canMip = mipmapped.contains(src.name)
            if !canMip {
                _ = _glGetError()
                _glGenerateMipmap(GL_TEXTURE_2D)
                canMip = _glGetError() == 0
                if canMip { mipmapped.insert(src.name) }
            }
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                             canMip ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

            _glUseProgram(program)
            _glBindVertexArray?(vao)
            _glBindBuffer(GL_ARRAY_BUFFER, vbo)
            let stride = Int32(Self.kFloatsPerVertex * MemoryLayout<Float>.size)
            func attrib(_ loc: Int32, _ n: Int32, _ offsetFloats: Int) {
                guard loc >= 0 else { return }
                _glEnableVertexAttribArray(UInt32(loc))
                _glVertexAttribPointer(UInt32(loc), n, GL_FLOAT, 0, stride,
                                       UnsafeRawPointer(bitPattern: offsetFloats * MemoryLayout<Float>.size))
            }
            attrib(aPos, 3, 0); attrib(aNrm, 3, 3); attrib(aUV, 2, 6)
            attrib(aAO, 1, 8); attrib(aSun, 1, 9); attrib(aMat, 1, 10)

            var proj = Self.projection(aspect: Double(width) / Double(height),
                                       tanHalfFovX: cam.tanHalfFovX)
            proj[8] = Float(cam.lensShiftX)
            proj[9] = Float(cam.lensShiftY)
            var view = Self.view(cam)
            _glUniformMatrix4fv(uProj, 1, 0, &proj)
            _glUniformMatrix4fv(uView, 1, 0, &view)
            _glUniform1f(uT, Float(cam.t))
            _glUniform1f(uTime, Float(sceneClock))
            _glUniform1f(uMip, canMip ? 1.0 : 0.0)
            // The room fades up out of the view as the viewer pulls back
            // off the glass; at t = 0 there is nothing but the view, which
            // is the flat wallpaper.
            _glUniform1f(uFade, Float(min(1, max(0, (cam.t - 0.12) / 0.55))))
            var eye = [Float(cam.x), Float(cam.y), Float(cam.z)]
            if uEye >= 0 { _glUniform3fv?(uEye, 1, &eye) }
            if uEyeV >= 0 { _glUniform3fv?(uEyeV, 1, &eye) }
            var light = [Float(cam.lightR), Float(cam.lightG), Float(cam.lightB)]
            if uLight >= 0 { _glUniform3fv?(uLight, 1, &light) }
            _glUniform1i(uTex, 0)
            _glActiveTexture(GL_TEXTURE0 + 1)
            _glBindTexture(GL_TEXTURE_2D, texDiffuse)
            _glUniform1i(uDiffuse, 1)
            _glActiveTexture(GL_TEXTURE0 + 2)
            _glBindTexture(GL_TEXTURE_2D, texArm)
            _glUniform1i(uArm, 2)
            _glActiveTexture(GL_TEXTURE0 + 3)
            _glBindTexture(GL_TEXTURE_2D, texSky)
            _glUniform1i(uSky, 3)
            _glActiveTexture(GL_TEXTURE0)
            if let room = _room {
                var sh = room.mesh.sh
                if uSH >= 0, sh.count == 27 { _glUniform3fv?(uSH, 9, &sh) }
                var sc = [room.mesh.sunColour.0, room.mesh.sunColour.1,
                          room.mesh.sunColour.2]
                if uSunCol >= 0 { _glUniform3fv?(uSunCol, 1, &sc) }
                _glUniform1f(uSkyRange, room.mesh.skyRange)
            }
            _glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo)
            _glDrawElements(GL_TRIANGLES, indexCount, GL_UNSIGNED_INT, nil)
            _glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0)
            if !loggedDraw {
                loggedDraw = true
                let err = _glGetError()
                let msg = "[EnvironmentRenderer] draw \(vertexCount) verts, glError \(err)\n"
                FileHandle.standardError.write(Data(msg.utf8))
            }
            _glBindBuffer(GL_ARRAY_BUFFER, 0)
            _glBindVertexArray?(0)
            _glUseProgram(0)
            _glBindTexture(GL_TEXTURE_2D, 0)
        }
        _glFlush()
        if let path = dumpPath { dump(to: path) }
        _glDisable(GL_DEPTH_TEST)
        _glDepthMask(0)
        _glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, 0)
        _glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0)
        _glBindFramebuffer(GL_FRAMEBUFFER, UInt32(prevFbo))
        _glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3])
    }

    private func dump(to path: String) {
        let w = width, h = height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { buf in
            _glReadPixels(0, 0, Int32(w), Int32(h), 0x1908 /* GL_RGBA */, 0x1401 /* GL_UNSIGNED_BYTE */, buf.baseAddress)
        }
        var ppm = Data("P6\n\(w) \(h)\n255\n".utf8)
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        // As the engine shows it: GL's last row is the top of the screen.
        for y in 0..<h {
            for x in 0..<w {
                let s = ((h - 1 - y) * w + x) * 4, d = (y * w + x) * 3
                rgb[d] = rgba[s]; rgb[d + 1] = rgba[s + 1]; rgb[d + 2] = rgba[s + 2]
            }
        }
        ppm.append(contentsOf: rgb)
        try? ppm.write(to: URL(fileURLWithPath: path))
    }

    // MARK: Geometry

    /// Column-major perspective with the lens the windows use. No y flip:
    /// the engine wraps an external GL texture bottom-left up, so GL's
    /// row 0 (clip y = -1) IS the bottom of the screen — measured, not
    /// assumed (the first build flipped it and drew the floor on top).
    static func projection(aspect: Double, tanHalfFovX: Double) -> [Float] {
        let tx = tanHalfFovX, ty = tanHalfFovX / aspect
        // Far enough for the sky: the reconstruction puts it hundreds of
        // metres out, and an 80 m far plane simply clipped it away — a
        // black sky that looked like a shader bug and was a frustum.
        let n = 0.08, f = 4000.0
        var m = [Float](repeating: 0, count: 16)
        m[0] = Float(1 / tx)
        m[5] = Float(1 / ty)
        m[10] = Float(-(f + n) / (f - n))
        m[11] = -1
        m[14] = Float(-2 * f * n / (f - n))
        return m
    }

    /// World -> view, column-major: undo the viewer's place and heading.
    /// The viewer really walks now, so this is a look-at and not the
    /// hand's-breadth translation the parallax version used.
    static func view(_ c: EnvironmentCamera) -> [Float] {
        let cy = cos(-c.yaw), sy = sin(-c.yaw)
        let cp = cos(-c.pitch), sp = sin(-c.pitch)
        // R = Rx(-pitch) * Ry(-yaw), then translate by -eye.
        let r = [
            cy, 0.0, -sy,
            sp * sy, cp, sp * cy,
            cp * sy, -sp, cp * cy,
        ]
        func rowDotEye(_ i: Int) -> Double {
            -(r[i * 3] * c.x + r[i * 3 + 1] * c.y + r[i * 3 + 2] * c.z)
        }
        var m = [Float](repeating: 0, count: 16)
        for col in 0..<3 {
            for row in 0..<3 { m[col * 4 + row] = Float(r[row * 3 + col]) }
        }
        m[12] = Float(rowDotEye(0))
        m[13] = Float(rowDotEye(1))
        m[14] = Float(rowDotEye(2))
        m[15] = 1
        return m
    }

    /// Vertices are pos(3) nrm(3) uv(2) ao(1) sun(1) mat(1).
    static let kFloatsPerVertex = 11

    /// Upload the baked room the first time it arrives. Everything about
    /// it is already decided — geometry, texture coordinates, the light —
    /// so this is a copy and nothing more.
    private func uploadRoomIfNeeded() {
        cameraLock.lock()
        let stale = _roomStale
        _roomStale = false
        let room = _room
        cameraLock.unlock()
        guard stale, let r = room else { return }

        _glBindBuffer(GL_ARRAY_BUFFER, vbo)
        r.mesh.vertices.withUnsafeBytes { buf in
            _glBufferData(GL_ARRAY_BUFFER, buf.count, buf.baseAddress, GL_STATIC_DRAW)
        }
        _glBindBuffer(GL_ARRAY_BUFFER, 0)
        if ibo == 0 { _glGenBuffers(1, &ibo) }
        _glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo)
        r.mesh.indices.withUnsafeBytes { buf in
            _glBufferData(GL_ELEMENT_ARRAY_BUFFER, buf.count, buf.baseAddress, GL_STATIC_DRAW)
        }
        _glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0)
        vertexCount = Int32(r.mesh.vertices.count / r.mesh.floatsPerVertex)
        indexCount = Int32(r.mesh.indices.count)

        func upload(_ name: inout UInt32, _ t: (data: [UInt8], w: Int, h: Int)) {
            if name == 0 { _glGenTextures(1, &name) }
            _glBindTexture(GL_TEXTURE_2D, name)
            t.data.withUnsafeBytes { buf in
                _glTexImage2D(GL_TEXTURE_2D, 0, Int32(GL_RGBA), Int32(t.w), Int32(t.h),
                              0, GL_RGBA, GL_UNSIGNED_BYTE, buf.baseAddress)
            }
            _glGenerateMipmap(GL_TEXTURE_2D)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
            _glBindTexture(GL_TEXTURE_2D, 0)
        }
        upload(&texDiffuse, r.diffuse)
        upload(&texArm, r.arm)
        upload(&texSky, r.sky)
        let msg = "[EnvironmentRenderer] room \(vertexCount) verts, "
            + "\(indexCount / 3) tris, atlas \(r.diffuse.w)x\(r.diffuse.h)\n"
        FileHandle.standardError.write(Data(msg.utf8))
    }

    // MARK: GL setup

    private static let vertexSource = """
    #version 100
    attribute vec3 aPos;
    attribute vec3 aNrm;
    attribute vec2 aUV;
    attribute float aAO;
    attribute float aSun;
    attribute float aMat;
    uniform mat4 uProj;
    uniform mat4 uView;
    uniform vec3 uEyeV;
    varying vec3 vPos;
    varying vec3 vNrm;
    varying vec2 vUV;
    varying float vAO;
    varying float vSun;
    varying float vMat;
    varying vec3 vDir;
    void main() {
        // Outside rides with the viewer: scenery at infinity, which never
        // approaches and never shows an edge. Material 4 — and it has to
        // agree with room-import.py, which is where the numbering lives.
        // When it did not, the CEILING rode with the camera instead and
        // the room simply had no ceiling, with the sky showing through.
        vec3 p = aPos + (aMat > 3.5 && aMat < 4.5 ? uEyeV : vec3(0.0));
        gl_Position = uProj * uView * vec4(p, 1.0);
        vPos = p;
        vNrm = aNrm;
        vUV = aUV;
        vAO = aAO;
        vSun = aSun;
        vMat = aMat;
        vDir = normalize(p - uEyeV);
    }
    """

    private static let fragmentSource = """
    #version 100
    // HIGHP. The procedural textures hash uv in METRES, which over a 10 m
    // floor reaches hundreds of thousands — past what mediump (fp16, max
    // 65504) holds. It overflows to infinity, sin(inf) is NaN, and the
    // fragment comes out pure BLACK with no error anywhere.
    precision highp float;
    uniform sampler2D uTex;
    uniform sampler2D uDiffuse;
    uniform sampler2D uArm;
    uniform sampler2D uSky;
    uniform vec3 uSH[9];
    uniform vec3 uSunCol;
    uniform float uSkyRange;
    uniform float uTime;
    uniform float uFade;
    uniform vec3 uEye;
    uniform vec3 uLight;
    varying vec3 vPos;
    varying vec3 vNrm;
    varying vec2 vUV;
    varying float vAO;
    varying float vSun;
    varying float vMat;
    varying vec3 vDir;

    float hash(vec2 p) {
        p = mod(p, 256.0);
        return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
    }
    float noise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
                   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
    }
    float fbm(vec2 p) {
        float a = 0.5, s = 0.0;
        for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; }
        return s;
    }

    void main() {
        float m = vMat;

        // ---- outside ----------------------------------------------------
        // A real sky, captured: the same one the room's light was baked
        // from, so what comes through the glass and what falls on the
        // floor are the same weather. Packed as RGB times a multiplier in
        // alpha, because 8 bits per channel cannot hold a sun.
        if (m > 3.5 && m < 4.5) {
            vec3 d = normalize(vDir);
            float su = 0.5 + atan(d.x, -d.z) / 6.2831853;
            float sv = acos(clamp(d.y, -1.0, 1.0)) / 3.14159265;
            // The PNG's rows go in top-down and GL's origin is at the
            // bottom, so the lookup runs the other way.
            // Square-rooted on the way in, squared here. NOT an alpha
            // multiplier: the engine's image codec returns premultiplied
            // RGBA, so anything kept in alpha arrives already folded into
            // the colour and multiplying by it again blackens the sky.
            // (`packed` is also a reserved word in GLSL, for the record.)
            vec3 sky = texture2D(uSky, vec2(su, 1.0 - sv)).rgb;
            vec3 c = sky * sky * uSkyRange;
            c = c / (c + vec3(0.78)) * 1.62;
            gl_FragColor = vec4(c * uFade, 1.0);
            return;
        }

        // ---- materials --------------------------------------------------
        // Material 0 is "look it up in the atlas": the furniture, whose
        // colour, roughness and its own ambient occlusion were authored
        // rather than guessed. The rest are procedural, because a floor
        // and a wall want to tile and an atlas cannot.
        vec3 albedo;
        float gloss = 0.0;
        float texAO = 1.0;
        if (m < 0.5) {
            // Same flip as the sky: these atlases are written top-down.
            vec2 au = vec2(vUV.x, 1.0 - vUV.y);
            albedo = texture2D(uDiffuse, au).rgb;
            vec3 arm = texture2D(uArm, au).rgb;
            texAO = 0.35 + 0.65 * arm.r;
            gloss = (1.0 - arm.g) * 0.5 + arm.b * 0.35;
        } else if (m < 1.5) {
            // Oak boards, 17 cm, laid along z, each a different tone.
            float board = floor(vUV.x / 0.17);
            float tone = 0.80 + 0.32 * hash(vec2(board, 3.0));
            float grain = noise(vec2(vUV.y * 30.0, board * 7.0)) * 0.15
                        + noise(vec2(vUV.y * 110.0, board * 13.0)) * 0.07;
            float seam = smoothstep(0.0, 0.010, abs(fract(vUV.x / 0.17) - 0.5) - 0.475);
            float endJoint = smoothstep(0.0, 0.012,
                abs(fract(vUV.y / 1.9 + hash(vec2(board, 9.0))) - 0.5) - 0.487);
            albedo = vec3(0.47, 0.335, 0.205) * (tone + grain)
                   * (1.0 - max(seam, endJoint) * 0.5);
            gloss = 0.34;
        } else if (m < 2.5) {
            float tooth = noise(vUV * 95.0) * 0.5 + noise(vUV * 230.0) * 0.5;
            albedo = vec3(0.83, 0.805, 0.765) * (0.985 + 0.03 * tooth);
            albedo *= 0.94 + 0.06 * smoothstep(0.0, 1.8, vPos.y);
        } else if (m < 3.5) {
            albedo = vec3(0.93, 0.925, 0.915);
        } else if (m < 5.5) {
            // The wallpaper, framed and hanging in the room.
            gl_FragColor = vec4(texture2D(uTex,
                vec2(clamp(vUV.x, 0.0, 1.0), 1.0 - clamp(vUV.y, 0.0, 1.0))).rgb
                * (0.55 + 0.9 * vAO) * uFade, 1.0);
            return;
        } else {
            float g2 = noise(vec2(vUV.x * 44.0, vUV.y * 5.0));
            albedo = vec3(0.24, 0.16, 0.105) * (0.82 + 0.38 * g2);
            gloss = 0.26;
        }

        vec3 n = normalize(vNrm);
        // What the whole sky gives a surface facing this way, from the
        // nine coefficients baked out of the HDRI. This is what used to be
        // three hand-tuned constants and a guess about which way was up.
        const float c1 = 0.429043, c2 = 0.511664;
        const float c3 = 0.743125, c4 = 0.886227, c5 = 0.247708;
        vec3 irr = c1 * uSH[8] * (n.x * n.x - n.y * n.y)
                 + c3 * uSH[6] * n.z * n.z
                 + c4 * uSH[0] - c5 * uSH[6]
                 + 2.0 * c1 * (uSH[4] * n.x * n.y + uSH[7] * n.x * n.z
                               + uSH[5] * n.y * n.z)
                 + 2.0 * c2 * (uSH[3] * n.x + uSH[1] * n.y + uSH[2] * n.z);
        // Only what the room can see of it: the walls block most of the
        // sky, and the windows are where it gets in.
        float toWin = max(-n.z, 0.0);
        vec3 skyAmb = max(irr, vec3(0.0)) * (0.17 + 0.62 * toWin) * 0.318;
        // Light that has bounced off the floor. No sky can supply this —
        // a ceiling sees no sky at all — and without it the ceiling is
        // black, which is the one thing that never happens in a room.
        float down = clamp(0.5 - n.y * 0.5, 0.0, 1.0);
        vec3 bounce = vec3(1.0, 0.90, 0.76)
                    * (0.10 + 0.26 * down) * (0.35 + 0.06 * uSunCol.g);
        vec3 ambient = (skyAmb + bounce) * vAO * texAO;
        vec3 lit = albedo * (ambient + uSunCol * vSun * 0.318);
        if (gloss > 0.0) {
            vec3 vv = normalize(uEye - vPos);
            float fres = pow(1.0 - max(dot(n, vv), 0.0), 4.0);
            lit += vec3(0.9, 0.93, 1.0) * fres * gloss * vAO * 0.30;
        }
        // Filmic shoulder, so a sun patch rolls off instead of clipping.
        lit = lit / (lit + vec3(0.78)) * 1.62;
        gl_FragColor = vec4(lit * uFade, 1.0);
    }
    """

    private func loadGL() {
        func load<T>(_ name: String) -> T {
            guard let resolver = glProcAddressResolver else {
                fatalError("[EnvironmentRenderer] no GL proc address resolver")
            }
            guard let fn = name.withCString({ resolver($0) }) else {
                fatalError("[EnvironmentRenderer] missing GL function \(name)")
            }
            return unsafeBitCast(fn, to: T.self)
        }
        func tryLoad<T>(_ name: String) -> T? {
            guard let resolver = glProcAddressResolver,
                  let fn = name.withCString({ resolver($0) }) else { return nil }
            return unsafeBitCast(fn, to: T.self)
        }
        _glGenBuffers = load("glGenBuffers")
        _glBindBuffer = load("glBindBuffer")
        _glBufferData = load("glBufferData")
        _glCreateShader = load("glCreateShader")
        _glShaderSource = load("glShaderSource")
        _glCompileShader = load("glCompileShader")
        _glGetShaderiv = load("glGetShaderiv")
        _glGetShaderInfoLog = load("glGetShaderInfoLog")
        _glCreateProgram = load("glCreateProgram")
        _glAttachShader = load("glAttachShader")
        _glLinkProgram = load("glLinkProgram")
        _glGetProgramiv = load("glGetProgramiv")
        _glGetProgramInfoLog = load("glGetProgramInfoLog")
        _glUseProgram = load("glUseProgram")
        _glGetAttribLocation = load("glGetAttribLocation")
        _glGetUniformLocation = load("glGetUniformLocation")
        _glUniform1f = load("glUniform1f")
        _glUniform3fv = tryLoad("glUniform3fv")
        _glUniform1i = load("glUniform1i")
        _glUniformMatrix4fv = load("glUniformMatrix4fv")
        _glVertexAttribPointer = load("glVertexAttribPointer")
        _glEnableVertexAttribArray = load("glEnableVertexAttribArray")
        _glDrawArrays = load("glDrawArrays")
        _glActiveTexture = load("glActiveTexture")
        _glBindTexture = load("glBindTexture")
        _glTexParameteri = load("glTexParameteri")
        _glGenerateMipmap = load("glGenerateMipmap")
        _glGetError = load("glGetError")
        _glGenFramebuffers = load("glGenFramebuffers")
        _glGenRenderbuffers = load("glGenRenderbuffers")
        _glBindRenderbuffer = load("glBindRenderbuffer")
        _glRenderbufferStorage = load("glRenderbufferStorage")
        _glFramebufferRenderbuffer = load("glFramebufferRenderbuffer")
        _glDepthFunc = load("glDepthFunc")
        _glDepthMask = load("glDepthMask")
        _glDrawElements = load("glDrawElements")
        _glGenTextures = load("glGenTextures")
        _glTexImage2D = load("glTexImage2D")
        _glBindFramebuffer = load("glBindFramebuffer")
        _glFramebufferTexture2D = load("glFramebufferTexture2D")
        _glViewport = load("glViewport")
        _glClearColor = load("glClearColor")
        _glClear = load("glClear")
        _glEnable = load("glEnable")
        _glDisable = load("glDisable")
        _glFlush = load("glFlush")
        _glGetIntegerv = load("glGetIntegerv")
        _glGenVertexArrays = tryLoad("glGenVertexArrays")
        _glReadPixels = load("glReadPixels")
        _glBindVertexArray = tryLoad("glBindVertexArray")

        var prevFbo: Int32 = 0
        _glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFbo)
        _glGenFramebuffers(1, &fbo)
        // A real room needs a real depth buffer: the sofa has to be in
        // front of the wall behind it from wherever the viewer stands.
        _glGenRenderbuffers(1, &depthRb)
        _glBindRenderbuffer(GL_RENDERBUFFER, depthRb)
        _glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24,
                               Int32(width), Int32(height))
        _glBindRenderbuffer(GL_RENDERBUFFER, 0)
        _glBindFramebuffer(GL_FRAMEBUFFER, UInt32(prevFbo))
        _glGenBuffers(1, &vbo)
        if let gen = _glGenVertexArrays { gen(1, &vao) }

        func compile(_ kind: UInt32, _ src: String) -> UInt32 {
            let sh = _glCreateShader(kind)
            src.withCString { cstr in
                var p: UnsafePointer<CChar>? = cstr
                withUnsafePointer(to: &p) { pp in _glShaderSource(sh, 1, pp, nil) }
            }
            _glCompileShader(sh)
            var ok: Int32 = 0
            _glGetShaderiv(sh, GL_COMPILE_STATUS, &ok)
            if ok == 0 {
                var log = [CChar](repeating: 0, count: 2048)
                var n: Int32 = 0
                _glGetShaderInfoLog(sh, 2048, &n, &log)
                let msg = "[EnvironmentRenderer] shader compile failed: \(String(cString: log))\n"
                FileHandle.standardError.write(Data(msg.utf8))
                return 0
            }
            return sh
        }
        let vs = compile(GL_VERTEX_SHADER, Self.vertexSource)
        let fs = compile(GL_FRAGMENT_SHADER, Self.fragmentSource)
        guard vs != 0, fs != 0 else { return }
        let prog = _glCreateProgram()
        _glAttachShader(prog, vs)
        _glAttachShader(prog, fs)
        _glLinkProgram(prog)
        var linked: Int32 = 0
        _glGetProgramiv(prog, GL_LINK_STATUS, &linked)
        guard linked != 0 else {
            var log = [CChar](repeating: 0, count: 2048)
            var n: Int32 = 0
            _glGetProgramInfoLog(prog, 2048, &n, &log)
            FileHandle.standardError.write(Data(
                "[EnvironmentRenderer] program link failed: \(String(cString: log))\n".utf8))
            return
        }
        program = prog
        aPos = _glGetAttribLocation(prog, "aPos")
        aUV = _glGetAttribLocation(prog, "aUV")
        uDiffuse = _glGetUniformLocation(prog, "uDiffuse")
        uArm = _glGetUniformLocation(prog, "uArm")
        uSky = _glGetUniformLocation(prog, "uSky")
        uSH = _glGetUniformLocation(prog, "uSH[0]")
        uSunCol = _glGetUniformLocation(prog, "uSunCol")
        uSkyRange = _glGetUniformLocation(prog, "uSkyRange")
        aNrm = _glGetAttribLocation(prog, "aNrm")
        aAO = _glGetAttribLocation(prog, "aAO")
        aSun = _glGetAttribLocation(prog, "aSun")
        aMat = _glGetAttribLocation(prog, "aMat")
        uTime = _glGetUniformLocation(prog, "uTime")
        uEye = _glGetUniformLocation(prog, "uEye")
        uEyeV = _glGetUniformLocation(prog, "uEyeV")
        uLight = _glGetUniformLocation(prog, "uLight")
        uFade = _glGetUniformLocation(prog, "uFade")
        uProj = _glGetUniformLocation(prog, "uProj")
        uView = _glGetUniformLocation(prog, "uView")
        uT = _glGetUniformLocation(prog, "uT")
        uTex = _glGetUniformLocation(prog, "uTex")
        uMip = _glGetUniformLocation(prog, "uMip")
        FileHandle.standardError.write(Data("[EnvironmentRenderer] ready \(width)x\(height)\n".utf8))
    }
}
#endif
