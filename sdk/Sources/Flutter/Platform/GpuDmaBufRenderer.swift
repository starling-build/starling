#if os(Linux)
import FlutterSwiftBridge
import FlutterEmbedderBridge
import DmaBufBridge
import SwiftRuntime
import Foundation
import Glibc

// ─── FlutterTaskQueue ────────────────────────────────────────────────────────

/// Thread-safe priority queue of engine tasks. The engine posts tasks from
/// arbitrary threads; we drain them on the main thread in the event loop.
/// Uses a pipe to wake the event loop when tasks are enqueued.
final class FlutterTaskQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [(FlutterTask, UInt64)] = []

    /// Pipe used to wake the event loop: write to [1], poll on [0].
    let wakeupReadFd: Int32
    private let wakeupWriteFd: Int32

    init() {
        var fds: (Int32, Int32) = (0, 0)
        let rc = withUnsafeMutablePointer(to: &fds) { ptr in
            ptr.withMemoryRebound(to: Int32.self, capacity: 2) { Glibc.pipe($0) }
        }
        assert(rc == 0, "pipe() failed")
        wakeupReadFd = fds.0
        wakeupWriteFd = fds.1
        // Set read end non-blocking
        let flags = fcntl(wakeupReadFd, F_GETFL)
        _ = fcntl(wakeupReadFd, F_SETFL, flags | O_NONBLOCK)
    }

    deinit {
        Glibc.close(wakeupReadFd)
        Glibc.close(wakeupWriteFd)
    }

    func enqueue(_ task: FlutterTask, targetNanos: UInt64) {
        lock.lock()
        tasks.append((task, targetNanos))
        lock.unlock()
        // Wake the event loop
        var byte: UInt8 = 1
        _ = Glibc.write(wakeupWriteFd, &byte, 1)
    }

    /// Drain the pipe (call after poll returns POLLIN).
    func consumeWakeup() {
        var buf = [UInt8](repeating: 0, count: 64)
        while Glibc.read(wakeupReadFd, &buf, buf.count) > 0 {}
    }

    /// Returns (expired tasks, next-deadline-nanos-or-nil).
    func drainExpired() -> (expired: [(FlutterTask, UInt64)], nextDeadline: UInt64?) {
        let now = FlutterEngineGetCurrentTime()
        lock.lock()
        var expired: [(FlutterTask, UInt64)] = []
        var remaining: [(FlutterTask, UInt64)] = []
        for item in tasks {
            if item.1 <= now {
                expired.append(item)
            } else {
                remaining.append(item)
            }
        }
        tasks = remaining
        let next = remaining.min(by: { $0.1 < $1.1 })?.1
        lock.unlock()
        return (expired, next)
    }
}

// ─── GpuRendererState ────────────────────────────────────────────────────────

/// Holds mutable state for engine callbacks. Extracted via Unmanaged from
/// userData pointers in the embedder's C function pointer callbacks.
public final class GpuRendererState: @unchecked Sendable {
    nonisolated(unsafe) var engine: OpaquePointer? = nil
    nonisolated(unsafe) var eglDisplay: UnsafeMutableRawPointer? = nil
    nonisolated(unsafe) var mainContext: UnsafeMutableRawPointer? = nil
    nonisolated(unsafe) var resourceContext: UnsafeMutableRawPointer? = nil
    nonisolated(unsafe) var fboName: UInt32 = 0
    nonisolated(unsafe) var socketFd: Int32 = -1
    nonisolated let taskQueue = FlutterTaskQueue()
    nonisolated let mainThreadPthread = pthread_self()

    // Resize support — GBM/FBO state accessed from raster thread (fbo_callback)
    nonisolated(unsafe) var gbmDevice: OpaquePointer? = nil
    nonisolated(unsafe) var gbmBo: OpaquePointer? = nil
    nonisolated(unsafe) var dmaFd: Int32 = -1
    nonisolated(unsafe) var stride: Int32 = 0
    nonisolated(unsafe) var fboEglImage: UnsafeMutableRawPointer? = nil
    nonisolated(unsafe) var fboColorTex: UInt32 = 0
    nonisolated(unsafe) var fboStencilRb: UInt32 = 0
    nonisolated(unsafe) var bufferWidth: Int = 0
    nonisolated(unsafe) var bufferHeight: Int = 0

    // Swapchain mode (NVIDIA): the render target is an EGL window surface on
    // a gbm_surface instead of an EGLImage-backed FBO, because that driver
    // can neither allocate a LINEAR|RENDERING bo nor attach a linear dma-buf
    // image to an FBO — eglSwapBuffers is its only route into linear memory.
    // The parent is sent the locked front buffer's fd whenever it changes;
    // its reimport path (built for resizes) makes that a cheap buffer flip.
    nonisolated(unsafe) var swapchain: Bool = false
    nonisolated(unsafe) var gbmSurface: OpaquePointer? = nil
    nonisolated(unsafe) var eglWindowSurface: UnsafeMutableRawPointer? = nil
    nonisolated(unsafe) var eglWindowConfig: UnsafeMutableRawPointer? = nil
    nonisolated(unsafe) var swapFourcc: UInt32 = 0
    /// The engine renders into this ordinary FBO (bo-path semantics);
    /// present() blits it Y-flipped onto the window surface, because
    /// eglSwapBuffers stores GL's bottom-up framebuffer top-down.
    nonisolated(unsafe) var swapFbo: UInt32 = 0
    nonisolated(unsafe) var swapFboColorRb: UInt32 = 0
    nonisolated(unsafe) var swapFboStencilRb: UInt32 = 0
    /// Front buffers still locked: the newest (being sent/sampled) and the
    /// previous (the parent may sample it until it processes the newest).
    nonisolated(unsafe) var lockedBos: [OpaquePointer] = []
    /// dma-buf fd per swapchain bo — gbm_bo_get_fd dups a fresh fd each call,
    /// so cache one per bo for the surface's lifetime.
    nonisolated(unsafe) var boFds: [OpaquePointer: Int32] = [:]
    nonisolated(unsafe) var lastSentBo: OpaquePointer? = nil

    /// Raster thread only. Replace the gbm_surface + EGL window surface at a
    /// new size. The parent keeps sampling the old front buffer — its dma-buf
    /// import keeps the memory alive after the surface is destroyed — until
    /// the first present at the new size sends it a new fd.
    func rebuildSwapchain(width: Int, height: Int) {
        guard let dev = gbmDevice, let cfg = eglWindowConfig else { return }
        guard let newSurf = gbm_surface_create(
            dev, UInt32(width), UInt32(height), swapFourcc,
            GBM_BO_USE_RENDERING.rawValue | GBM_BO_USE_LINEAR.rawValue) else {
            FileHandle.standardError.write(Data(
                "[GpuDmaBufRenderer] resize: gbm_surface_create failed\n".utf8))
            return
        }
        guard let newEglSurf = dmabuf_egl_create_window_surface(eglDisplay, cfg,
                                                                newSurf) else {
            gbm_surface_destroy(newSurf)
            FileHandle.standardError.write(Data(
                "[GpuDmaBufRenderer] resize: eglCreateWindowSurface failed\n".utf8))
            return
        }
        // Switch the context over before tearing down the old surface —
        // it is current on this thread right now.
        guard dmabuf_egl_make_current_surface(eglDisplay, mainContext,
                                              newEglSurf) != 0 else {
            dmabuf_egl_destroy_surface(eglDisplay, newEglSurf)
            gbm_surface_destroy(newSurf)
            return
        }
        if let old = eglWindowSurface {
            dmabuf_egl_destroy_surface(eglDisplay, old)
        }
        if let oldSurf = gbmSurface {
            for bo in lockedBos { gbm_surface_release_buffer(oldSurf, bo) }
            gbm_surface_destroy(oldSurf)
        }
        for boFd in boFds.values where boFd >= 0 { Glibc.close(boFd) }
        boFds = [:]
        lockedBos = []
        lastSentBo = nil
        gbmSurface = newSurf
        eglWindowSurface = newEglSurf
        bufferWidth = width
        bufferHeight = height

        // The engine's render target FBO, at the new size (context is
        // current on this thread — we just made the new surface current).
        dmabuf_destroy_plain_fbo(swapFbo, swapFboColorRb, swapFboStencilRb)
        var colorRb: UInt32 = 0
        var stencilRb: UInt32 = 0
        let newFbo = dmabuf_create_plain_fbo(Int32(width), Int32(height),
                                             &colorRb, &stencilRb)
        if newFbo == 0 {
            FileHandle.standardError.write(Data(
                "[GpuDmaBufRenderer] resize: dmabuf_create_plain_fbo failed\n".utf8))
        }
        swapFbo = newFbo
        swapFboColorRb = colorRb
        swapFboStencilRb = stencilRb
    }

    // Thread-safe pending resize (written: platform thread, read: raster thread)
    private let _resizeLock = NSLock()
    private var _pendingResize: (width: Int, height: Int)? = nil
    func setPendingResize(_ size: (width: Int, height: Int)) {
        _resizeLock.lock(); _pendingResize = size; _resizeLock.unlock()
    }
    func takePendingResize() -> (width: Int, height: Int)? {
        _resizeLock.lock()
        let r = _pendingResize
        _pendingResize = nil
        _resizeLock.unlock()
        return r
    }

    // ─── Window stream (per-screen shell) ───────────────────────────────────
    // The shell relays the desktop windows overlapping an externally sourced
    // output over a second socket (FLUTTER_WINDOW_STREAM_SOCKET): fixed-size
    // DmaBufWindowStreamMsg, FRAME ones carrying the buffer fd. Each window
    // becomes an external texture; the app composites them from the snapshot.

    /// One relayed desktop window, ready to composite.
    public struct ExternalWindowState: Sendable {
        public let window: Int32
        public let textureId: Int64
        /// CONTENT placement in this screen's LOGICAL coordinates — the
        /// screen shell draws its own title bar above this rect.
        public let x: Double, y: Double, width: Double, height: Double
        public let z: Int
        public let focused: Bool
        public let title: String
    }

    private let _winLock = NSLock()
    private var _externalWindows: [Int32: ExternalWindowState] = [:]
    /// Completed titles by window key, and runs still accumulating
    /// (8 bytes per DMABUF_WINSTREAM_TITLE chunk).
    private var _winTitles: [Int32: String] = [:]
    private var _winTitlePartial: [Int32: (total: Int, bytes: [UInt8])] = [:]
    /// Fired on the main queue when windows appear, move, or leave — texture
    /// CONTENT updates repaint through the engine without a rebuild, so they
    /// do not fire this.
    public nonisolated(unsafe) var onExternalWindowsChanged: (@Sendable () -> Void)? = nil

    /// Snapshot for compositing, bottom-most first.
    public var externalWindows: [ExternalWindowState] {
        _winLock.lock(); defer { _winLock.unlock() }
        return _externalWindows.values.sorted { $0.z < $1.z }
    }

    func startWindowStream(path: String) {
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                path.withCString { _ = strncpy(buf, $0, 107) }
            }
        }
        let ok = withUnsafePointer(to: &addr) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Glibc.connect(fd, $0, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else {
            FileHandle.standardError.write(Data(
                "[WindowStream] connect(\(path)) failed: \(String(cString: strerror(errno)))\n".utf8))
            Glibc.close(fd)
            return
        }
        Thread.detachNewThread { [self] in windowStreamLoop(fd) }
    }

    private func windowStreamLoop(_ fd: Int32) {
        let size = MemoryLayout<DmaBufWindowStreamMsg>.size
        while true {
            var msg = DmaBufWindowStreamMsg()
            var rfd: Int32 = -1
            let n = withUnsafeMutableBytes(of: &msg) { p in
                dmabuf_recv_with_fd(fd, p.baseAddress, p.count, &rfd)
            }
            if n <= 0 {
                FileHandle.standardError.write(Data(
                    "[WindowStream] reader exiting: recv=\(n) errno=\(errno)\n".utf8))
                break
            }
            guard n >= size else {
                if rfd >= 0 { Glibc.close(rfd) }
                continue
            }
            switch msg.kind {
            case Int32(DMABUF_WINSTREAM_FRAME):
                guard rfd >= 0 else { break }
                _winLock.lock()
                let existing = _externalWindows[msg.window]
                let title = _winTitles[msg.window] ?? ""
                _winLock.unlock()
                let texId = existing?.textureId ?? registerExternalTexture()
                // updateExternalTexture takes ownership of the fd. External
                // target: window buffers come from OTHER GPU contexts (a
                // foreign GPU's, or another zink process's linear bo), which
                // this display can only sample through EXTERNAL_OES.
                updateExternalTexture(
                    texId, fd: rfd, width: msg.buf_w, height: msg.buf_h,
                    stride: msg.stride, fourcc: msg.fourcc,
                    modifier: msg.modifier, external: true)
                let state = ExternalWindowState(
                    window: msg.window, textureId: texId,
                    x: Double(msg.x), y: Double(msg.y),
                    width: Double(msg.w), height: Double(msg.h),
                    z: Int(msg.z),
                    focused: msg.flags & UInt32(DMABUF_WINFLAG_FOCUSED) != 0,
                    title: title)
                let topologyChanged = existing == nil
                    || existing!.x != state.x || existing!.y != state.y
                    || existing!.width != state.width
                    || existing!.height != state.height
                    || existing!.z != state.z
                    || existing!.focused != state.focused
                _winLock.lock()
                _externalWindows[msg.window] = state
                _winLock.unlock()
                if topologyChanged { _notifyWindowsChanged() }
            case Int32(DMABUF_WINSTREAM_PLACE):
                if rfd >= 0 { Glibc.close(rfd) }
                _winLock.lock()
                guard let existing = _externalWindows[msg.window] else {
                    _winLock.unlock()
                    break
                }
                _externalWindows[msg.window] = ExternalWindowState(
                    window: msg.window, textureId: existing.textureId,
                    x: Double(msg.x), y: Double(msg.y),
                    width: Double(msg.w), height: Double(msg.h),
                    z: Int(msg.z),
                    focused: msg.flags & UInt32(DMABUF_WINFLAG_FOCUSED) != 0,
                    title: existing.title)
                _winLock.unlock()
                _notifyWindowsChanged()
            case Int32(DMABUF_WINSTREAM_TITLE):
                if rfd >= 0 { Glibc.close(rfd) }
                _winLock.lock()
                let total = Int(msg.buf_w)
                var partial = msg.z == 0
                    ? (total: total, bytes: [UInt8]())
                    : (_winTitlePartial[msg.window]
                        ?? (total: total, bytes: []))
                var chunk = msg.modifier
                var i = 0
                while i < 8 && partial.bytes.count < partial.total {
                    partial.bytes.append(UInt8(truncatingIfNeeded: chunk))
                    chunk >>= 8
                    i += 1
                }
                if partial.bytes.count >= partial.total {
                    let title = String(decoding: partial.bytes,
                                       as: UTF8.self)
                    _winTitles[msg.window] = title
                    _winTitlePartial.removeValue(forKey: msg.window)
                    let existing = _externalWindows[msg.window]
                    if let existing, existing.title != title {
                        _externalWindows[msg.window] = ExternalWindowState(
                            window: existing.window,
                            textureId: existing.textureId,
                            x: existing.x, y: existing.y,
                            width: existing.width, height: existing.height,
                            z: existing.z, focused: existing.focused,
                            title: title)
                        _winLock.unlock()
                        _notifyWindowsChanged()
                        break
                    }
                } else {
                    _winTitlePartial[msg.window] = partial
                }
                _winLock.unlock()
            case Int32(DMABUF_WINSTREAM_DAMAGE):
                if rfd >= 0 { Glibc.close(rfd) }
                _winLock.lock()
                let texId = _externalWindows[msg.window]?.textureId
                _winLock.unlock()
                if let texId, let eng = engine {
                    FlutterEngineMarkExternalTextureFrameAvailable(eng, texId)
                }
            case Int32(DMABUF_WINSTREAM_REMOVE):
                if rfd >= 0 { Glibc.close(rfd) }
                _winLock.lock()
                let removed = _externalWindows.removeValue(forKey: msg.window)
                _winTitles.removeValue(forKey: msg.window)
                _winTitlePartial.removeValue(forKey: msg.window)
                _winLock.unlock()
                if let removed {
                    unregisterExternalTexture(removed.textureId)
                    _notifyWindowsChanged()
                }
            default:
                if rfd >= 0 { Glibc.close(rfd) }
            }
        }
        Glibc.close(fd)
    }

    private func _notifyWindowsChanged() {
        guard let cb = onExternalWindowsChanged else { return }
        DispatchQueue.main.async { cb() }
    }

    // ─── External Texture Registry ──────────────────────────────────────────

    /// A hardware-decoded NV12 surface waiting to be imported: both planes in
    /// one DMA-BUF, at their own offsets. The fd is NOT owned — it belongs to
    /// the decoder's frame, which the producer keeps alive until it sees the
    /// import happen.
    struct PendingNV12 {
        var fd: Int32
        var width: Int32
        var height: Int32
        var modifier: UInt64
        var offset0: UInt32, pitch0: UInt32
        var offset1: UInt32, pitch1: UInt32
        var release: (@Sendable () -> Void)?
    }

    struct ExternalTextureEntry {
        var pendingFd: Int32 = -1       // New DMA-BUF fd from main thread
        var pendingPixels: [UInt8]? = nil  // OR new CPU RGBA frame (exclusive)
        var pendingNV12: PendingNV12? = nil  // OR a decoded surface (exclusive)
        /// Texture target the engine must sample this through. GL_TEXTURE_2D
        /// for RGBA; GL_TEXTURE_EXTERNAL_OES once an NV12 image is bound,
        /// since that is the only target such an image can live on.
        var glTarget: UInt32 = 0x0DE1
        /// Kept alive until the NEXT surface is bound: the texture still
        /// references this one's dma-buf, and letting the decoder reuse the
        /// surface early means it overwrites a frame still being sampled.
        var heldRelease: (@Sendable () -> Void)? = nil
        /// EGLImages already imported for this texture, keyed by the dma-buf
        /// they wrap. A decoder cycles a small pool of surfaces, so the same
        /// handful of buffers arrives over and over; importing each once and
        /// rebinding is far cheaper than an eglCreateImageKHR and destroy per
        /// frame. Same reasoning — and the same inode key — as the shell's
        /// LinuxTextureRegistry.imageCache.
        var nv12Cache: [UInt64: UnsafeMutableRawPointer] = [:]
        var nv12CacheOrder: [UInt64] = []
        var width: Int32 = 0
        var height: Int32 = 0
        var stride: Int32 = 0
        var fourcc: UInt32 = 0
        var modifier: UInt64 = 0
        /// Bind pending fds on GL_TEXTURE_EXTERNAL_OES instead of TEXTURE_2D
        /// (window-stream textures — see updateExternalTexture).
        var wantExternalTarget: Bool = false
        var glTexName: UInt32 = 0       // GL texture (raster thread)
        var eglImage: UnsafeMutableRawPointer? = nil  // Current EGLImage
        var dirty: Bool = false
        /// Size the GL texture's own storage is allocated at, or 0 when it has
        /// none of its own (fresh, or currently bound to an EGLImage). A CPU
        /// frame of exactly this size refills that storage instead of
        /// replacing it.
        var texWidth: Int32 = 0
        var texHeight: Int32 = 0
    }

    private let _texLock = NSLock()
    nonisolated(unsafe) var _texEntries: [Int64: ExternalTextureEntry] = [:]
    nonisolated(unsafe) var _nextTexId: Int64 = 1

    public func registerExternalTexture() -> Int64 {
        _texLock.lock()
        let id = _nextTexId
        _nextTexId += 1
        _texEntries[id] = ExternalTextureEntry()
        _texLock.unlock()

        if let eng = engine {
            FlutterEngineRegisterExternalTexture(eng, id)
        }
        return id
    }

    public func unregisterExternalTexture(_ id: Int64) {
        if let eng = engine {
            FlutterEngineUnregisterExternalTexture(eng, id)
        }
        _texLock.lock()
        let removed = _texEntries.removeValue(forKey: id)
        _texLock.unlock()
        if let entry = removed {
            if entry.pendingFd >= 0 { Glibc.close(entry.pendingFd) }
            for img in entry.nv12Cache.values {
                dmabuf_destroy_egl_image(eglDisplay, img)
            }
            // Both the queued and the bound surface are owed a release, or the
            // decoder never gets those frames back.
            entry.pendingNV12?.release?()
            entry.heldRelease?()
        }
    }

    /// Called from main thread: store new DMA-BUF fd for the raster thread.
    /// `external: true` binds through GL_TEXTURE_EXTERNAL_OES instead of
    /// TEXTURE_2D — the only target a FOREIGN GPU's buffer can bind to on
    /// this display (nv-view.md fact 4), and the route around zink's
    /// refusal to sample a re-imported linear dma-buf of its own on
    /// TEXTURE_2D. Window-stream textures use it unconditionally.
    public func updateExternalTexture(_ id: Int64, fd: Int32, width: Int32, height: Int32,
                                       stride: Int32, fourcc: UInt32, modifier: UInt64,
                                       external: Bool = false) {
        _texLock.lock()
        guard var entry = _texEntries[id] else {
            _texLock.unlock()
            Glibc.close(fd)
            return
        }
        if entry.pendingFd >= 0 {
            Glibc.close(entry.pendingFd)
        }
        entry.pendingFd = fd
        entry.width = width
        entry.height = height
        entry.stride = stride
        entry.fourcc = fourcc
        entry.modifier = modifier
        entry.wantExternalTarget = external
        entry.dirty = true
        _texEntries[id] = entry
        _texLock.unlock()

        // Without this the engine composites its CACHED resolve of the
        // texture and never calls populate again — the fd path historically
        // got away with it by rebinding EGLImages under the same GL texture
        // name, which only works after a first pull that happened to see a
        // frame. Mark properly so every update is pulled.
        if let eng = engine {
            FlutterEngineMarkExternalTextureFrameAvailable(eng, id)
        }
    }

    /// Called from the main thread: hand over a hardware-decoded NV12 surface
    /// for the raster thread to import. Nothing is copied — the compositor
    /// samples the decoder's own buffer.
    ///
    /// `release` runs once the texture has moved on to a later surface, on
    /// the raster thread. Return the frame to the decoder's pool there and
    /// not before: the pool will hand the surface straight back to the
    /// decoder, which writes the next frame into memory still bound to a live
    /// EGLImage.
    public func updateExternalTextureNV12(
        _ id: Int64, fd: Int32, width: Int32, height: Int32, modifier: UInt64,
        offset0: UInt32, pitch0: UInt32, offset1: UInt32, pitch1: UInt32,
        release: (@Sendable () -> Void)? = nil
    ) {
        _texLock.lock()
        guard var entry = _texEntries[id] else {
            _texLock.unlock()
            release?()
            return
        }
        // A surface queued but never imported still owes its release.
        let superseded = entry.pendingNV12?.release
        if entry.pendingFd >= 0 {
            Glibc.close(entry.pendingFd)
            entry.pendingFd = -1
        }
        entry.pendingPixels = nil
        entry.pendingNV12 = PendingNV12(
            fd: fd, width: width, height: height, modifier: modifier,
            offset0: offset0, pitch0: pitch0, offset1: offset1, pitch1: pitch1,
            release: release)
        entry.width = width
        entry.height = height
        entry.dirty = true
        _texEntries[id] = entry
        _texLock.unlock()
        superseded?()

        if let eng = engine {
            FlutterEngineMarkExternalTextureFrameAvailable(eng, id)
            // Mark alone says "the texture changed"; it does not by itself
            // get a frame composited. The producer used to setState on every
            // frame, which scheduled one as a side effect — at 60fps that
            // rebuilt the entire widget tree to show a picture the engine
            // could have re-composited on its own.
            FlutterEngineScheduleFrame(eng)
        }
    }

    /// Called from main thread: store a CPU RGBA frame for the raster thread
    /// to upload — the pixel counterpart of updateExternalTexture(fd:), for
    /// content decoded into ordinary memory (e.g. video frames off a pipe).
    /// Rows must be tightly packed; the array is consumed (moved, not
    /// copied) so hand over a buffer you are done with.
    public func updateExternalTexturePixels(_ id: Int64, pixels: [UInt8],
                                             width: Int32, height: Int32) {
        guard pixels.count == Int(width) * Int(height) * 4 else { return }
        _texLock.lock()
        guard var entry = _texEntries[id] else {
            _texLock.unlock()
            return
        }
        if entry.pendingFd >= 0 {
            Glibc.close(entry.pendingFd)
            entry.pendingFd = -1
        }
        entry.pendingPixels = pixels
        entry.width = width
        entry.height = height
        entry.dirty = true
        _texEntries[id] = entry
        _texLock.unlock()

        if let eng = engine {
            FlutterEngineMarkExternalTextureFrameAvailable(eng, id)
        }
    }

    /// Hands every CPU frame delivered since the last frame to the GPU, with
    /// the render context already current. Called from `make_current`, which
    /// is to say BEFORE the rasterizer touches the shared buffer.
    ///
    /// Uploading from `populateExternalTexture` instead — during the paint —
    /// is what made a video window FLICKER. The child renders into ONE
    /// DMA-BUF that the parent shell samples zero-copy and unsynchronised, so
    /// the buffer is on screen the whole time; a frame is a clear followed by
    /// the paint, and a multi-megabyte `glTexImage2D` wedged between them
    /// flushes the clear to the GPU and then holds the buffer empty for as
    /// long as the upload takes. The shell sampling in that gap composites
    /// the window as pure black — 40% of its presented frames, at 2560x1600.
    /// Hoisted here the upload runs while the buffer still holds the last
    /// complete frame, and clear and paint land together.
    /// A hardware-decoded surface costs almost nothing here (an EGLImage
    /// import and a bind, no pixels move), but it is drained in the same pass
    /// so both kinds of frame become visible at the same point in the cycle.
    func uploadPendingPixels() {
        _texLock.lock()
        let ids = _texEntries.compactMap {
            ($0.value.pendingPixels != nil || $0.value.pendingNV12 != nil)
                ? $0.key : nil
        }
        _texLock.unlock()
        for id in ids {
            importPendingNV12(id)
            uploadPendingPixels(id)
        }
    }

    /// One texture's pending decoded surface, imported and bound. The
    /// previous surface is released here and not earlier — the texture
    /// referenced it until this bind replaced it.
    private func importPendingNV12(_ id: Int64) {
        _texLock.lock()
        guard var entry = _texEntries[id], let nv = entry.pendingNV12 else {
            _texLock.unlock()
            return
        }
        entry.pendingNV12 = nil
        entry.dirty = false
        _texEntries[id] = entry
        _texLock.unlock()

        let external = DMABUF_GL_TEXTURE_EXTERNAL_OES
        // Identify the buffer itself, not the fd number: fds get recycled, and
        // an inode is what makes two handles to one dma-buf compare equal.
        var st = stat()
        let key: UInt64? = fstat(nv.fd, &st) == 0
            ? (UInt64(st.st_dev) &* 1_000_003 &+ UInt64(st.st_ino)) : nil
        var cached: UnsafeMutableRawPointer? = nil
        if let key {
            _texLock.lock()
            cached = _texEntries[id]?.nv12Cache[key]
            _texLock.unlock()
        }
        guard let img = cached ?? dmabuf_import_nv12_egl_image(
            eglDisplay, nv.fd, nv.width, nv.height, nv.modifier,
            nv.offset0, nv.pitch0, nv.offset1, nv.pitch1)
        else {
            nv.release?()
            return
        }
        if cached == nil, let key {
            var evicted: [UnsafeMutableRawPointer] = []
            _texLock.lock()
            if _texEntries[id] != nil {
                _texEntries[id]!.nv12Cache[key] = img
                _texEntries[id]!.nv12CacheOrder.append(key)
                while _texEntries[id]!.nv12CacheOrder.count > 12 {
                    let old = _texEntries[id]!.nv12CacheOrder.removeFirst()
                    if old == key { _texEntries[id]!.nv12CacheOrder.append(old); break }
                    if let img = _texEntries[id]!.nv12Cache.removeValue(forKey: old) {
                        evicted.append(img)
                    }
                }
            }
            _texLock.unlock()
            for e in evicted { dmabuf_destroy_egl_image(eglDisplay, e) }
        }

        // A texture name's target is fixed by its first bind, so one that was
        // serving RGBA cannot be re-pointed at an external image — retire it.
        var name = entry.glTexName
        if entry.glTarget != external, name != 0 {
            dmabuf_delete_gl_texture(name)
            name = 0
        }
        let tex = dmabuf_bind_external_texture(name, img)
        guard tex != 0 else {
            dmabuf_destroy_egl_image(eglDisplay, img)
            nv.release?()
            return
        }

        // The previous image belongs to nv12Cache now; destroying it here
        // would free a buffer the decoder's pool is still cycling.
        _texLock.lock()
        _texEntries[id]?.glTexName = tex
        _texEntries[id]?.glTarget = external
        _texEntries[id]?.eglImage = img
        _texEntries[id]?.texWidth = 0     // storage belongs to the image
        _texEntries[id]?.texHeight = 0
        let previous = _texEntries[id]?.heldRelease
        _texEntries[id]?.heldRelease = nv.release
        _texLock.unlock()
        previous?()
    }

    /// One texture's pending CPU frame, uploaded and cleared. No-op when
    /// nothing is pending. Caller must hold a current GL context.
    private func uploadPendingPixels(_ id: Int64) {
        _texLock.lock()
        guard var entry = _texEntries[id], let px = entry.pendingPixels else {
            _texLock.unlock()
            return
        }
        let w = entry.width, h = entry.height
        entry.pendingPixels = nil
        entry.dirty = false
        _texEntries[id] = entry
        _texLock.unlock()

        // The upload replaces whatever EGLImage-backed storage was there — a
        // texture flips between sources cleanly because it orphans the
        // previous storage. Drop the stored pointer in the same breath as
        // destroying it: a failed upload must not leave a dangling one behind
        // for the next call to destroy again.
        // Refill the existing allocation when it already fits — see the
        // header note on dmabuf_upload_rgba_texture. An EGLImage-bound
        // texture has no storage of its own, so it never qualifies.
        let reuse = entry.eglImage == nil && entry.glTexName != 0
            && entry.texWidth == w && entry.texHeight == h
            && entry.glTarget == 0x0DE1
        if let oldImg = entry.eglImage {
            dmabuf_destroy_egl_image(eglDisplay, oldImg)
            _texLock.lock()
            _texEntries[id]?.eglImage = nil
            _texEntries[id]?.texWidth = 0
            _texEntries[id]?.texHeight = 0
            _texLock.unlock()
        }
        // Coming back from a decoded surface (a hardware file followed by one
        // the GPU cannot decode): an external name cannot hold RGBA, and the
        // surface it referenced is free the moment it is unbound.
        var name = entry.glTexName
        if entry.glTarget != 0x0DE1 {
            if name != 0 { dmabuf_delete_gl_texture(name) }
            name = 0
            _texLock.lock()
            let held = _texEntries[id]?.heldRelease
            _texEntries[id]?.heldRelease = nil
            _texLock.unlock()
            held?()
        }
        let tex = px.withUnsafeBufferPointer {
            dmabuf_upload_rgba_texture(name, w, h, reuse ? 1 : 0, $0.baseAddress)
        }
        guard tex != 0 else { return }
        _texLock.lock()
        _texEntries[id]?.glTexName = tex
        _texEntries[id]?.glTarget = 0x0DE1
        _texEntries[id]?.texWidth = w
        _texEntries[id]?.texHeight = h
        _texLock.unlock()
    }

    /// Called from raster thread (via gl_external_texture_frame_callback).
    func populateExternalTexture(_ id: Int64,
                                  textureOut: UnsafeMutablePointer<FlutterOpenGLTexture>) -> Bool {
        // Normally already done in `make_current`; this catches a frame that
        // landed after it, so a late arrival is shown rather than held.
        importPendingNV12(id)
        uploadPendingPixels(id)

        _texLock.lock()
        guard var entry = _texEntries[id] else {
            _texLock.unlock()
            return false
        }
        let fd = entry.pendingFd
        let dirty = entry.dirty
        let w = entry.width, h = entry.height
        let st = entry.stride
        let fourcc = entry.fourcc, mod = entry.modifier
        if dirty {
            entry.pendingFd = -1
            entry.dirty = false
            _texEntries[id] = entry
        }
        _texLock.unlock()

        // Pixels were taken by uploadPendingPixels above; only the DMA-BUF fd
        // path is left to resolve here.
        if dirty && fd >= 0 {
            if let oldImg = entry.eglImage {
                dmabuf_destroy_egl_image(eglDisplay, oldImg)
            }

            let externalTarget: UInt32 = 0x8D65  // GL_TEXTURE_EXTERNAL_OES
            var newImg: UnsafeMutableRawPointer? = nil
            var newTarget: UInt32 = 0x0DE1
            if entry.wantExternalTarget {
                // A texture name binds to ONE target for its lifetime —
                // coming from the 2D path it must be recreated on OES.
                if entry.glTexName != 0 && entry.glTarget != externalTarget {
                    dmabuf_delete_gl_texture(entry.glTexName)
                    entry.glTexName = 0
                }
                newImg = dmabuf_import_egl_image_with_modifier(
                    eglDisplay, fd, w, h, st, fourcc, mod)
                if newImg != nil {
                    entry.glTexName = dmabuf_bind_external_texture(
                        entry.glTexName, newImg)
                }
                newTarget = externalTarget
            } else if entry.glTexName == 0 {
                let tex = dmabuf_import_as_gl_texture(
                    eglDisplay, fd, w, h, st, fourcc, mod, &newImg)
                entry.glTexName = tex
            } else {
                newImg = dmabuf_import_egl_image_with_modifier(
                    eglDisplay, fd, w, h, st, fourcc, mod)
                if newImg != nil {
                    dmabuf_rebind_gl_texture(entry.glTexName, newImg)
                }
            }

            Glibc.close(fd)

            entry.eglImage = newImg
            entry.width = w
            entry.height = h

            _texLock.lock()
            _texEntries[id]?.glTexName = entry.glTexName
            _texEntries[id]?.eglImage = entry.eglImage
            _texEntries[id]?.glTarget = newTarget
            // The texture's storage is the image's now, not its own.
            _texEntries[id]?.texWidth = 0
            _texEntries[id]?.texHeight = 0
            _texLock.unlock()
        }

        guard entry.glTexName != 0 else { return false }

        // GL_TEXTURE_2D for RGBA, GL_TEXTURE_EXTERNAL_OES for a decoded NV12
        // surface — the engine hands this straight to Skia as the backend
        // texture's target, and an external image is only samplable there.
        _texLock.lock()
        let target = _texEntries[id]?.glTarget ?? 0x0DE1
        _texLock.unlock()
        textureOut.pointee.target = target
        textureOut.pointee.name = entry.glTexName
        textureOut.pointee.format = 0x8058  // GL_RGBA8
        textureOut.pointee.width = Int(entry.width)
        textureOut.pointee.height = Int(entry.height)
        return true
    }
}

// ─── GpuDmaBufRenderer ──────────────────────────────────────────────────────

/// GPU-accelerated DMA-BUF renderer that runs a full Flutter embedder with
/// kOpenGL, rendering to an offscreen FBO backed by a GBM buffer object.
/// The parent process imports the DMA-BUF fd as an EGLImage for zero-copy
/// GPU texture sharing.
public class GpuDmaBufRenderer {

    let width: Int
    let height: Int
    var pixelRatio: Double

    // GBM state
    private let renderFd: Int32
    private let gbmDevice: OpaquePointer         // gbm_device*
    private let gbmBo: OpaquePointer?            // gbm_bo* (nil in swapchain mode)
    private let dmaFd: Int32                     // DMA-BUF fd (-1 in swapchain mode)
    private let stride: Int32                    // Row stride in bytes

    // EGL state
    private let eglDisplay: UnsafeMutableRawPointer
    private let eglConfig: UnsafeMutableRawPointer
    private let mainContext: UnsafeMutableRawPointer
    private let resourceContext: UnsafeMutableRawPointer

    // FBO state
    private var fboName: UInt32
    private var fboEglImage: UnsafeMutableRawPointer?
    private var fboColorTex: UInt32 = 0
    private var fboStencilRb: UInt32 = 0

    // Socket to parent
    private let socketFd: Int32

    // Engine
    private var engine: OpaquePointer? = nil

    // Renderer state passed to callbacks
    let state: GpuRendererState

    // Event loop control
    private var running: Bool = false

    /// STARLING_SWAPCHAIN_DEBUG=1: per-event stderr tracing for the
    /// swapchain path (pointer reads, fbo callback, present).
    static let swapchainDebug =
        (ProcessInfo.processInfo.environment["STARLING_SWAPCHAIN_DEBUG"] ?? "") == "1"

    // MARK: - DRM device selection

    /// GBM_FORMAT_ABGR8888 — matches Skia's RGBA byte order.
    static let bufferFormat: UInt32 = 0x34324241

    /// A DRM device we can both allocate on and export a DMA-BUF from.
    /// `swapchain` marks a device that allocates and exports LINEAR buffers
    /// but cannot render into one directly (NVIDIA): `bo` is nil and the
    /// buffers come from a gbm_surface created during EGL setup instead.
    struct DrmTarget {
        let path: String
        let fd: Int32
        let device: OpaquePointer      // gbm_device*
        let bo: OpaquePointer?         // gbm_bo* (nil in swapchain mode)
        let dmaBufFd: Int32            // -1 in swapchain mode
        let swapchain: Bool
    }

    /// The symlink target of a DRM node's sysfs `device`, which is the same
    /// string for the card and render nodes of one GPU. Used to pair them.
    private static func sysfsDevice(_ node: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(
            atPath: "/sys/class/drm/\(node)/device")
    }

    /// DRM devices to try, best first: the render node of the card the shell
    /// renders on, then any other render node, then the primary nodes (which
    /// is where a GPU-less software stack has to allocate). A non-empty
    /// `STARLING_APP_DRM_DEVICE` replaces the list outright.
    public static func drmCandidates() -> [String] {
        let env = ProcessInfo.processInfo.environment
        if let forced = env["STARLING_APP_DRM_DEVICE"], !forced.isEmpty {
            return [forced]
        }

        let nodes = ((try? FileManager.default.contentsOfDirectory(atPath: "/dev/dri")) ?? [])
            .sorted()
        let renderNodes = nodes.filter { $0.hasPrefix("renderD") }
        let cardNodes = nodes.filter { $0.hasPrefix("card") }

        // The shell's own card (FLUTTER_DRM_DEVICE) decides which GPU we pair
        // with: on a hybrid machine the wrong render node allocates on a
        // device the compositor cannot import from.
        let shellCard = (env["FLUTTER_DRM_DEVICE"].flatMap { $0.isEmpty ? nil : $0 }
                         ?? "/dev/dri/card0")
        let shellCardNode = (shellCard as NSString).lastPathComponent
        let shellCardDevice = sysfsDevice(shellCardNode)

        let matching = renderNodes.filter {
            shellCardDevice != nil && sysfsDevice($0) == shellCardDevice
        }
        let ordered = matching
            + renderNodes.filter { !matching.contains($0) }
            + [shellCardNode]
            + cardNodes.filter { $0 != shellCardNode }

        var seen = Set<String>()
        return ordered.compactMap { seen.insert($0).inserted ? "/dev/dri/\($0)" : nil }
    }

    /// Opens the first DRM device that can actually allocate a shareable
    /// buffer of this size. Opening proves nothing — on a render node with no
    /// GPU behind it, `gbm_create_device` succeeds and the allocation is what
    /// fails — so each candidate is carried all the way to a DMA-BUF fd and
    /// torn down again if it does not get there.
    static func openDrmDevice(width: Int, height: Int) -> DrmTarget? {
        // GBM_BO_USE_LINEAR = (1 << 4), GBM_BO_USE_RENDERING = (1 << 2)
        let useFlags = GBM_BO_USE_LINEAR.rawValue | GBM_BO_USE_RENDERING.rawValue

        for path in drmCandidates() {
            let fd = Glibc.open(path, O_RDWR)
            guard fd >= 0 else {
                reject(path, "open: \(String(cString: strerror(errno)))")
                continue
            }
            guard let dev = gbm_create_device(fd) else {
                reject(path, "gbm_create_device failed")
                Glibc.close(fd)
                continue
            }
            guard let bo = gbm_bo_create(dev, UInt32(width), UInt32(height),
                                         bufferFormat, useFlags) else {
                // NVIDIA refuses LINEAR|RENDERING outright but allocates
                // LINEAR alone — rendering then has to go through a
                // gbm_surface swapchain (built during EGL setup in init).
                // Prove allocation + export here the same way as the bo path.
                if let probe = gbm_bo_create(dev, UInt32(width), UInt32(height),
                                             bufferFormat,
                                             GBM_BO_USE_LINEAR.rawValue) {
                    let probeFd = gbm_bo_get_fd(probe)
                    gbm_bo_destroy(probe)
                    if probeFd >= 0 {
                        Glibc.close(probeFd)
                        FileHandle.standardError.write(Data(
                            "[GpuDmaBufRenderer] rendering on \(path) (swapchain mode)\n".utf8))
                        return DrmTarget(path: path, fd: fd, device: dev,
                                         bo: nil, dmaBufFd: -1, swapchain: true)
                    }
                }
                reject(path, "gbm_bo_create failed")
                gbm_device_destroy(dev)
                Glibc.close(fd)
                continue
            }
            let dmaBufFd = gbm_bo_get_fd(bo)
            guard dmaBufFd >= 0 else {
                reject(path, "gbm_bo_get_fd failed")
                gbm_bo_destroy(bo)
                gbm_device_destroy(dev)
                Glibc.close(fd)
                continue
            }
            FileHandle.standardError.write(Data(
                "[GpuDmaBufRenderer] rendering on \(path)\n".utf8))
            return DrmTarget(path: path, fd: fd, device: dev, bo: bo,
                             dmaBufFd: dmaBufFd, swapchain: false)
        }
        return nil
    }

    /// Why one candidate was passed over. stderr, not `print`: the shell pipes
    /// a child's stdout and drops it, so a `print` here is invisible — which is
    /// how a launch that fails this early looked like nothing happening at all.
    private static func reject(_ path: String, _ reason: String) {
        FileHandle.standardError.write(Data(
            "[GpuDmaBufRenderer] \(path): \(reason)\n".utf8))
    }

    // MARK: - Init

    /// Creates a GpuDmaBufRenderer. Returns nil if GBM/EGL setup fails.
    public init?(width: Int, height: Int, socketPath: String) {
        // 1. Connect to parent's Unix domain socket first (to receive configure)
        let sock = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard sock >= 0 else {
            print("[GpuDmaBufRenderer] socket() failed: \(String(cString: strerror(errno)))")
            return nil
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            let bound = pathPtr.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                socketPath.withCString { src in
                    strncpy(buf, src, 107)
                    return true
                }
            }
            _ = bound
        }

        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Glibc.connect(sock, sa, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            print("[GpuDmaBufRenderer] connect(\(socketPath)) failed: \(String(cString: strerror(errno)))")
            Glibc.close(sock)
            return nil
        }
        socketFd = sock

        // 2. Read configure message from parent (content area dimensions)
        var logicalW = width
        var logicalH = height
        var configure = DmaBufConfigure(width: 0, height: 0, type: 0, _reserved: 0)
        let configureSize = MemoryLayout<DmaBufConfigure>.size
        let n = withUnsafeMutablePointer(to: &configure) { ptr in
            recv(sock, ptr, configureSize, Int32(MSG_WAITALL))
        }
        if n == configureSize && configure.type == DMABUF_CONFIGURE {
            logicalW = Int(configure.width)
            logicalH = Int(configure.height)
            print("[GpuDmaBufRenderer] Configured by parent: \(logicalW)x\(logicalH)")
        }

        // 3. Read device pixel ratio from environment (set by parent's DRM shell)
        let dpiEnv = ProcessInfo.processInfo.environment["FLUTTER_DRM_DPI"]
        var dpi = dpiEnv.flatMap { Double($0) } ?? 1.0
        if dpi < 0.5 { dpi = 0.5 }
        if dpi > 4.0 { dpi = 4.0 }
        self.pixelRatio = dpi

        // Buffer size is in physical pixels (logical * DPI). Round, don't
        // truncate: 980 * 1.7 is 1665.999… in Double, and a buffer one texel
        // short of the on-screen quad gets stretched — blurry text.
        let physicalWidth = Int((Double(logicalW) * dpi).rounded())
        let physicalHeight = Int((Double(logicalH) * dpi).rounded())
        self.width = physicalWidth
        self.height = physicalHeight
        if dpi != 1.0 {
            print("[GpuDmaBufRenderer] DPI=\(dpi): logical \(logicalW)x\(logicalH) → physical \(physicalWidth)x\(physicalHeight)")
        }

        // 4–7. Open a DRM device, and allocate the shared buffer on it.
        //
        // These are one step because only the allocation proves the device is
        // usable. A render node is the right answer whenever there is a GPU:
        // it needs no privilege and it is what every accelerated stack uses.
        // But with no GPU at all — a VM with 3D acceleration switched off,
        // which is the DEFAULT in GNOME Boxes, VirtualBox and VMware — Mesa
        // falls back to kms_swrast, and that allocates through
        // DRM_IOCTL_MODE_CREATE_DUMB, an ioctl render nodes reject outright
        // (EACCES, "KMS: DRM_IOCTL_MODE_CREATE_DUMB failed: Permission
        // denied"). The primary node allows it for anyone who can open the
        // device, which the seat's active user can through the logind ACL.
        //
        // So the render node is tried first and the primary node second, and
        // each candidate is proven by allocating rather than by opening. The
        // shell renders on the primary node either way (it holds it via
        // libseat), so the fallback lands both halves on the same device.
        guard let picked = Self.openDrmDevice(width: self.width, height: self.height) else {
            FileHandle.standardError.write(Data((
                "[GpuDmaBufRenderer] no usable DRM device — tried " +
                Self.drmCandidates().joined(separator: ", ") + "\n"
            ).utf8))
            Glibc.close(sock)
            return nil
        }
        // Steps 8–14 below share the failure cleanup, so keep the locals.
        let fd = picked.fd
        let dev = picked.device
        let formatABGR8888 = Self.bufferFormat
        renderFd = fd
        gbmDevice = dev

        // Swapchain-path locals, populated as setup progresses so `fail`
        // can unwind exactly what exists.
        var gbmSurf: OpaquePointer? = nil
        var lockedFront: OpaquePointer? = nil
        var swapDmaFd: Int32 = -1
        func fail(_ msg: String) {
            FileHandle.standardError.write(Data(
                "[GpuDmaBufRenderer] \(msg)\n".utf8))
            if let front = lockedFront, let surf = gbmSurf {
                gbm_surface_release_buffer(surf, front)
            }
            if swapDmaFd >= 0 { Glibc.close(swapDmaFd) }
            if let surf = gbmSurf { gbm_surface_destroy(surf) }
            if picked.dmaBufFd >= 0 { Glibc.close(picked.dmaBufFd) }
            if let bo = picked.bo { gbm_bo_destroy(bo) }
            gbm_device_destroy(dev)
            Glibc.close(fd)
            Glibc.close(sock)
        }

        // 8. Create EGL display from GBM device
        guard let display = dmabuf_egl_create_display(dev) else {
            fail("dmabuf_egl_create_display failed")
            return nil
        }
        eglDisplay = display

        // 9. Initialize EGL
        guard dmabuf_egl_initialize(display) != 0 else {
            fail("dmabuf_egl_initialize failed")
            return nil
        }

        // 10. Choose EGL config. The swapchain path needs a window config
        // whose native visual GBM accepts, plus the gbm_surface itself —
        // negotiated as a pair, since a driver may expose a format as a
        // config yet refuse it as a surface. Skia's RGBA order first.
        var chosenFourcc: UInt32 = 0
        let config: UnsafeMutableRawPointer
        if picked.swapchain {
            var found: UnsafeMutableRawPointer? = nil
            let candidates: [UInt32] = [
                formatABGR8888,
                0x3432_5241,  // GBM_FORMAT_ARGB8888 'AR24'
                0x3432_5258,  // GBM_FORMAT_XRGB8888 'XR24'
            ]
            for fourcc in candidates {
                guard let cfg = dmabuf_egl_choose_window_config(display, fourcc)
                else { continue }
                guard let surf = gbm_surface_create(
                    dev, UInt32(self.width), UInt32(self.height), fourcc,
                    GBM_BO_USE_RENDERING.rawValue | GBM_BO_USE_LINEAR.rawValue)
                else { continue }
                found = cfg
                chosenFourcc = fourcc
                gbmSurf = surf
                break
            }
            guard let windowConfig = found else {
                fail("no EGL window config + gbm_surface for any format")
                return nil
            }
            config = windowConfig
        } else {
            guard let offscreen = dmabuf_egl_choose_config(display) else {
                fail("dmabuf_egl_choose_config failed")
                return nil
            }
            config = offscreen
        }
        eglConfig = config

        // 11. Create main context
        guard let mainCtx = dmabuf_egl_create_context(display, config, nil) else {
            fail("Failed to create main EGL context")
            return nil
        }
        mainContext = mainCtx

        // 12. Create resource context (shared with main)
        guard let resCtx = dmabuf_egl_create_context(display, config, mainCtx) else {
            fail("Failed to create resource EGL context")
            return nil
        }
        resourceContext = resCtx

        // 13/14. Bind the render target: an EGLImage FBO over the shared bo,
        // or the window surface whose front buffer we lock and export.
        var eglImage: UnsafeMutableRawPointer? = nil
        var colorTex: UInt32 = 0
        var stencilRb: UInt32 = 0
        var windowSurface: UnsafeMutableRawPointer? = nil
        var swapchainFbo: UInt32 = 0
        var swapchainColorRb: UInt32 = 0
        var swapchainStencilRb: UInt32 = 0
        let sendFd: Int32
        let sendStride: Int32
        let sendFourcc: UInt32

        if picked.swapchain {
            guard let esurf = dmabuf_egl_create_window_surface(display, config,
                                                               gbmSurf) else {
                fail("eglCreateWindowSurface failed")
                return nil
            }
            windowSurface = esurf
            guard dmabuf_egl_make_current_surface(display, mainCtx, esurf) != 0 else {
                fail("make_current(window surface) failed")
                return nil
            }
            // The FBO the engine actually renders into (see state.swapFbo).
            var colorRb: UInt32 = 0
            var stencilRb2: UInt32 = 0
            let plainFbo = dmabuf_create_plain_fbo(Int32(self.width),
                                                   Int32(self.height),
                                                   &colorRb, &stencilRb2)
            guard plainFbo != 0 else {
                fail("dmabuf_create_plain_fbo failed")
                return nil
            }
            swapchainFbo = plainFbo
            swapchainColorRb = colorRb
            swapchainStencilRb = stencilRb2
            // First buffer: clear, swap, lock — the parent samples this until
            // the engine presents its first real frame.
            dmabuf_gl_clear_black()
            guard dmabuf_egl_swap_buffers(display, esurf) != 0,
                  let front = gbm_surface_lock_front_buffer(gbmSurf) else {
                fail("first swap/lock on gbm_surface failed")
                return nil
            }
            lockedFront = front
            swapDmaFd = gbm_bo_get_fd(front)
            guard swapDmaFd >= 0 else {
                fail("gbm_bo_get_fd(front buffer) failed")
                return nil
            }
            fboName = 0
            gbmBo = nil
            dmaFd = -1
            stride = Int32(gbm_bo_get_stride(front))
            sendFd = swapDmaFd
            sendStride = stride
            sendFourcc = chosenFourcc
        } else {
            let bo = picked.bo!
            let dmaBufFd = picked.dmaBufFd
            gbmBo = bo
            dmaFd = dmaBufFd
            stride = Int32(gbm_bo_get_stride(bo))

            // Make main context current to create the FBO
            guard dmabuf_egl_make_current(display, mainCtx) != 0 else {
                fail("dmabuf_egl_make_current failed")
                return nil
            }
            let fbo = dmabuf_create_fbo(display, dmaBufFd,
                                        Int32(self.width), Int32(self.height), stride,
                                        formatABGR8888,
                                        &eglImage, &colorTex, &stencilRb)
            guard fbo != 0 else {
                dmabuf_egl_clear_current(display)
                fail("dmabuf_create_fbo failed")
                return nil
            }
            fboName = fbo
            // 15. Clear FBO to black so parent doesn't see uninitialized GPU memory
            dmabuf_gl_clear_black()
            sendFd = dmaBufFd
            sendStride = stride
            sendFourcc = formatABGR8888
        }
        fboEglImage = eglImage
        fboColorTex = colorTex
        fboStencilRb = stencilRb

        // 16. Clear current context
        dmabuf_egl_clear_current(display)

        // Set socket to non-blocking for input event reads in poll loop
        let sockFlags = fcntl(sock, F_GETFL)
        _ = fcntl(sock, F_SETFL, sockFlags | O_NONBLOCK)

        // 17. Send DMA-BUF fd + metadata to parent
        var meta = DmaBufMeta(
            width: Int32(self.width),
            height: Int32(self.height),
            stride: sendStride,
            fourcc: sendFourcc
        )
        let sendResult = dmabuf_send_fd(sock, sendFd, &meta,
                                        MemoryLayout<DmaBufMeta>.size)
        guard sendResult == 0 else {
            fail("Failed to send DMA-BUF fd to parent")
            return nil
        }

        print("[GpuDmaBufRenderer] Connected to parent, sent DMA-BUF fd (stride=\(sendStride), fbo=\(fboName), swapchain=\(picked.swapchain))")

        // Initialize renderer state for callbacks
        state = GpuRendererState()
        state.eglDisplay = display
        state.mainContext = mainCtx
        state.resourceContext = resCtx
        state.fboName = fboName
        state.socketFd = sock

        // Store GBM/FBO state for resize support
        state.gbmDevice = dev
        state.gbmBo = gbmBo
        state.dmaFd = dmaFd
        state.stride = stride
        state.fboEglImage = eglImage
        state.fboColorTex = colorTex
        state.fboStencilRb = stencilRb
        state.bufferWidth = self.width
        state.bufferHeight = self.height

        // Swapchain state (see GpuRendererState.swapchain)
        state.swapchain = picked.swapchain
        state.gbmSurface = gbmSurf
        state.eglWindowSurface = windowSurface
        state.eglWindowConfig = picked.swapchain ? config : nil
        state.swapFourcc = chosenFourcc
        state.swapFbo = swapchainFbo
        state.swapFboColorRb = swapchainColorRb
        state.swapFboStencilRb = swapchainStencilRb
        if picked.swapchain, let front = lockedFront {
            state.lockedBos = [front]
            state.boFds = [front: swapDmaFd]
            state.lastSentBo = front
        }
    }

    deinit {
        running = false
        if let eng = engine {
            FlutterEngineShutdown(eng)
        }
        // Use state's values — may have been updated by resize on raster thread
        if state.fboName != 0 {
            dmabuf_destroy_fbo(state.eglDisplay, state.fboName,
                               state.fboEglImage,
                               state.fboColorTex, state.fboStencilRb)
        }
        if state.swapchain {
            dmabuf_destroy_plain_fbo(state.swapFbo, state.swapFboColorRb,
                                     state.swapFboStencilRb)
            if let display = state.eglDisplay {
                dmabuf_egl_destroy_surface(display, state.eglWindowSurface)
            }
            for boFd in state.boFds.values where boFd >= 0 { Glibc.close(boFd) }
            if let surf = state.gbmSurface {
                for bo in state.lockedBos { gbm_surface_release_buffer(surf, bo) }
                gbm_surface_destroy(surf)
            }
        }
        Glibc.close(socketFd)
        if state.dmaFd >= 0 { Glibc.close(state.dmaFd) }
        if let bo = state.gbmBo { gbm_bo_destroy(bo) }
        gbm_device_destroy(gbmDevice)
        Glibc.close(renderFd)
    }

    // MARK: - DPI Control

    /// Write one control event to the shell, retrying an interrupted
    /// syscall — a signal landing mid-write (SIGCHLD is near-constant in
    /// these apps) must not eat a user's click. SOCK_SEQPACKET writes are
    /// atomic, so there are no partials to worry about.
    private func writeControlEvent(_ event: inout DmaBufInputEvent) {
        while true {
            let n = Glibc.write(socketFd, &event,
                                MemoryLayout<DmaBufInputEvent>.size)
            if n >= 0 || errno != EINTR { return }
        }
    }

    /// Send a DPI change request to the parent process via the socket.
    public func sendDpiChange(_ dpi: Double) {
        var event = DmaBufInputEvent(x: dpi, y: 0, buttons: 0,
                                     type: DMABUF_CONTROL_SET_DPI, phase: 0)
        writeControlEvent(&event)
        FileHandle.standardError.write(Data("[GpuDmaBufRenderer] Sent DPI change: \(dpi)\n".utf8))
    }

    /// Ask the parent shell to switch the desktop appearance (Settings'
    /// Dark Mode toggle).
    private var _lastCaret: (Double, Double, Double, Double, Bool)? = nil
    private var _caretOwner: ObjectIdentifier? = nil

    /// Report the focused text caret (logical content coordinates) to the
    /// parent shell — drives the IME candidate panel placement. Deduplicated,
    /// so calling from build() on every rebuild is cheap.
    ///
    /// `owner` arbitrates between multiple reporting widgets in one app: a
    /// visible report claims the anchor; a hide is honored only from the
    /// current owner (a stale unfocus from widget A must not clear widget
    /// B's freshly claimed anchor — build order is arbitrary).
    public func sendCaret(owner: AnyObject, x: Double, y: Double,
                          width: Double, height: Double, visible: Bool) {
        let id = ObjectIdentifier(owner)
        if visible {
            _caretOwner = id
        } else {
            guard _caretOwner == id else { return }
            _caretOwner = nil
        }
        let entry = (x, y, width, height, visible)
        if let last = _lastCaret, last == entry { return }
        _lastCaret = entry
        let packed = UInt64(Float(width).bitPattern)
            | (UInt64(Float(height).bitPattern) << 32)
        var event = DmaBufInputEvent(x: x, y: y,
                                     buttons: Int64(bitPattern: packed),
                                     type: Int32(DMABUF_CARET),
                                     phase: visible ? 1 : 0)
        writeControlEvent(&event)
    }

    public func sendThemeChange(dark: Bool) {
        var event = DmaBufInputEvent(x: dark ? 1 : 0, y: 0, buttons: 0,
                                     type: DMABUF_CONTROL_SET_THEME, phase: 0)
        writeControlEvent(&event)
        FileHandle.standardError.write(Data("[GpuDmaBufRenderer] Sent theme change: dark=\(dark)\n".utf8))
    }

    /// Ask the shell to switch the window-manager layout (Settings toggle).
    public func sendLayoutChange(tiling: Bool) {
        var event = DmaBufInputEvent(x: tiling ? 1 : 0, y: 0, buttons: 0,
                                     type: DMABUF_CONTROL_SET_LAYOUT, phase: 0)
        writeControlEvent(&event)
    }

    /// Ask the shell to switch the wallpaper preset (Settings picker). The
    /// value is the shell's WallpaperPreset raw value — opaque here.
    public func sendWallpaperChange(preset: Int) {
        var event = DmaBufInputEvent(x: Double(preset), y: 0, buttons: 0,
                                     type: DMABUF_CONTROL_SET_WALLPAPER, phase: 0)
        writeControlEvent(&event)
    }

    /// Ask the shell to change the screensaver idle timeout (Settings
    /// picker). Seconds of no input before the screensaver appears; 0 = never.
    public func sendScreensaverChange(seconds: Int) {
        var event = DmaBufInputEvent(x: Double(seconds), y: 0, buttons: 0,
                                     type: DMABUF_CONTROL_SET_SCREENSAVER, phase: 0)
        writeControlEvent(&event)
    }

    /// Ask the shell to make `outputId` the primary display (Settings ›
    /// Displays). The id is the one the shell reported in `DisplayInfo`.
    public func sendPrimaryDisplayChange(outputId: Int) {
        var event = DmaBufInputEvent(x: Double(outputId), y: 0, buttons: 0,
                                     type: DMABUF_CONTROL_SET_PRIMARY_DISPLAY,
                                     phase: 0)
        writeControlEvent(&event)
    }

    /// Global reference for child apps to send control messages.
    public nonisolated(unsafe) static var current: GpuDmaBufRenderer? = nil

    /// Fired on the main queue when the parent shell pushes an appearance
    /// change (true = dark). Set by the app before/after runApp.
    ///
    /// The shell pushes the current appearance as soon as the child connects,
    /// which lands here *before* the first frame builds the widget tree — the
    /// tree is mounted from `onBeginFrame`, so a root widget's `initState` has
    /// not run yet and this is still nil. A push arriving then is latched in
    /// `pendingThemeDark` and replayed the moment a callback is installed;
    /// without that, a child launched while the desktop is light would keep
    /// its dark default until the next switch.
    public nonisolated(unsafe) static var onThemeChanged: ((Bool) -> Void)? = nil {
        didSet {
            guard let cb = onThemeChanged, let dark = pendingThemeDark else { return }
            pendingThemeDark = nil
            deliverThemeChange(cb, dark)
        }
    }

    /// The most recent appearance the parent pushed, or nil if it never has.
    /// Durable: unlike the replay latch this is never consumed, so state built
    /// after the root widget (a bloc, say) can still seed itself from it.
    /// Seeding keeps the first frame from flashing the app's default theme.
    public private(set) nonisolated(unsafe) static var lastPushedThemeIsDark: Bool? = nil

    /// A push that arrived before any callback was installed, awaiting replay.
    private nonisolated(unsafe) static var pendingThemeDark: Bool? = nil

    /// Records a push from the parent and delivers it, or latches it for replay.
    fileprivate static func receiveThemePush(_ dark: Bool) {
        lastPushedThemeIsDark = dark
        if let cb = onThemeChanged {
            deliverThemeChange(cb, dark)
        } else {
            pendingThemeDark = dark
        }
    }

    // Window-manager layout push — same latch/replay contract as the theme.

    public nonisolated(unsafe) static var onLayoutChanged: ((Bool) -> Void)? = nil {
        didSet {
            guard let cb = onLayoutChanged, let tiling = pendingLayoutTiling else { return }
            pendingLayoutTiling = nil
            deliverThemeChange(cb, tiling)
        }
    }

    /// The most recent layout the parent pushed (true = tiling), or nil.
    public private(set) nonisolated(unsafe) static var lastPushedLayoutIsTiling: Bool? = nil

    private nonisolated(unsafe) static var pendingLayoutTiling: Bool? = nil

    fileprivate static func receiveLayoutPush(_ tiling: Bool) {
        lastPushedLayoutIsTiling = tiling
        if let cb = onLayoutChanged {
            deliverThemeChange(cb, tiling)
        } else {
            pendingLayoutTiling = tiling
        }
    }

    // Wallpaper preset push — same latch/replay contract as the theme.

    public nonisolated(unsafe) static var onWallpaperChanged: ((Int) -> Void)? = nil {
        didSet {
            guard let cb = onWallpaperChanged, let preset = pendingWallpaper else { return }
            pendingWallpaper = nil
            deliverIntChange(cb, preset)
        }
    }

    /// The most recent wallpaper preset the parent pushed, or nil.
    public private(set) nonisolated(unsafe) static var lastPushedWallpaper: Int? = nil

    private nonisolated(unsafe) static var pendingWallpaper: Int? = nil

    fileprivate static func receiveWallpaperPush(_ preset: Int) {
        lastPushedWallpaper = preset
        if let cb = onWallpaperChanged {
            deliverIntChange(cb, preset)
        } else {
            pendingWallpaper = preset
        }
    }

    // Screensaver idle timeout push — same latch/replay contract as the
    // theme. Seconds of idle before the screensaver appears; 0 = never.

    public nonisolated(unsafe) static var onScreensaverChanged: ((Int) -> Void)? = nil {
        didSet {
            guard let cb = onScreensaverChanged, let secs = pendingScreensaver else { return }
            pendingScreensaver = nil
            deliverIntChange(cb, secs)
        }
    }

    /// The most recent idle timeout the parent pushed, or nil.
    public private(set) nonisolated(unsafe) static var lastPushedScreensaver: Int? = nil

    private nonisolated(unsafe) static var pendingScreensaver: Int? = nil

    fileprivate static func receiveScreensaverPush(_ seconds: Int) {
        lastPushedScreensaver = seconds
        if let cb = onScreensaverChanged {
            deliverIntChange(cb, seconds)
        } else {
            pendingScreensaver = seconds
        }
    }

    // Connected-display list push — same latch/replay contract as the theme.

    /// One display as the shell sees it. `id` is what
    /// `sendPrimaryDisplayChange` takes back.
    public struct DisplayInfo: Sendable, Equatable {
        public let id: Int
        /// The DRM connector name, e.g. "eDP-1", "HDMI-A-1".
        public let name: String
        public let physicalWidth: Int
        public let physicalHeight: Int
        public let scale: Double
        public let isPrimary: Bool

        public init(id: Int, name: String, physicalWidth: Int,
                    physicalHeight: Int, scale: Double, isPrimary: Bool) {
            self.id = id
            self.name = name
            self.physicalWidth = physicalWidth
            self.physicalHeight = physicalHeight
            self.scale = scale
            self.isPrimary = isPrimary
        }

        /// Logical size at this display's own scale.
        public var logicalWidth: Int { Int((Double(physicalWidth) / scale).rounded()) }
        public var logicalHeight: Int { Int((Double(physicalHeight) / scale).rounded()) }
    }

    public nonisolated(unsafe) static var onDisplaysChanged: (([DisplayInfo]) -> Void)? = nil {
        didSet {
            guard let cb = onDisplaysChanged, let list = pendingDisplays else { return }
            pendingDisplays = nil
            deliverDisplaysChange(cb, list)
        }
    }

    /// The most recent display list the parent pushed, or nil if it never has
    /// (every non-shell host: the windowed GLFW host, the macOS dev path).
    public private(set) nonisolated(unsafe) static var lastPushedDisplays: [DisplayInfo]? = nil

    private nonisolated(unsafe) static var pendingDisplays: [DisplayInfo]? = nil

    /// The run being assembled: names arrive in chunks ahead of each info
    /// record, and the list is published only once the run's last record
    /// lands, so a reader never sees a half-built arrangement.
    private nonisolated(unsafe) static var displayRun: [DisplayInfo] = []
    private nonisolated(unsafe) static var displayNameBytes: [UInt8] = []

    /// Eight more bytes of the next display's connector name.
    fileprivate static func receiveDisplayNameChunk(_ chunk: Int64, index: Int) {
        if index == 0 { displayNameBytes.removeAll(keepingCapacity: true) }
        let bits = UInt64(bitPattern: chunk)
        for i in 0..<8 {
            let byte = UInt8(truncatingIfNeeded: bits >> (8 * UInt64(i)))
            if byte == 0 { break }
            displayNameBytes.append(byte)
        }
    }

    fileprivate static func receiveDisplayInfo(width: Double, height: Double,
                                               packed: Int64, phase: Int32) {
        let index = Int(phase >> 16) & 0xFFFF
        let count = Int(phase) & 0xFFFF
        let bits = UInt64(bitPattern: packed)
        let info = DisplayInfo(
            id: Int(bits & 0xFFFF),
            name: String(decoding: displayNameBytes, as: UTF8.self),
            physicalWidth: Int(width), physicalHeight: Int(height),
            scale: Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits >> 32))),
            isPrimary: (bits >> 16) & 1 == 1)
        displayNameBytes.removeAll(keepingCapacity: true)
        if index == 0 { displayRun.removeAll(keepingCapacity: true) }
        displayRun.append(info)
        guard count > 0, displayRun.count == count else { return }
        let list = displayRun
        displayRun.removeAll(keepingCapacity: true)
        lastPushedDisplays = list
        if let cb = onDisplaysChanged {
            deliverDisplaysChange(cb, list)
        } else {
            pendingDisplays = list
        }
    }

    /// App UI state is main-thread only; hop before touching it.
    private static func deliverThemeChange(_ cb: @escaping (Bool) -> Void, _ dark: Bool) {
        let call: () -> Void = { cb(dark) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(call, to: (@Sendable () -> Void).self))
    }

    private static func deliverIntChange(_ cb: @escaping (Int) -> Void, _ value: Int) {
        let call: () -> Void = { cb(value) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(call, to: (@Sendable () -> Void).self))
    }

    private static func deliverDisplaysChange(
        _ cb: @escaping ([DisplayInfo]) -> Void, _ value: [DisplayInfo]
    ) {
        let call: () -> Void = { cb(value) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(call, to: (@Sendable () -> Void).self))
    }

    // MARK: - Widget Mounting

    public func mountWidget(_ builder: () -> Widget) {
        _setupWidgetBinding(builder())
    }

    // MARK: - Run (Engine Init + Event Loop)

    public func run() {
        let statePtr = Unmanaged.passUnretained(state).toOpaque()

        // 1. Create runtime callbacks
        var callbacks = createRuntimeCallbacks()

        // 2. Configure OpenGL renderer
        var rendererConfig = FlutterRendererConfig()
        rendererConfig.type = kOpenGL
        rendererConfig.open_gl.struct_size = MemoryLayout<FlutterOpenGLRendererConfig>.size

        rendererConfig.open_gl.make_current = { userData -> Bool in
            guard let userData = userData else { return false }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            if s.swapchain {
                guard dmabuf_egl_make_current_surface(s.eglDisplay, s.mainContext,
                                                      s.eglWindowSurface) != 0 else {
                    return false
                }
            } else {
                guard dmabuf_egl_make_current(s.eglDisplay, s.mainContext) != 0 else {
                    return false
                }
            }
            // Before the rasterizer touches the shared buffer, never during
            // the paint — see uploadPendingPixels for why that flickers.
            s.uploadPendingPixels()
            return true
        }

        rendererConfig.open_gl.clear_current = { userData -> Bool in
            guard let userData = userData else { return false }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            return dmabuf_egl_clear_current(s.eglDisplay) != 0
        }

        rendererConfig.open_gl.present = { userData -> Bool in
            guard let userData = userData else { return false }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            if s.swapchain {
                // Release older fronts BEFORE the swap: the gbm_surface has a
                // small fixed pool (3 on NVIDIA), and holding two locked
                // buffers through eglSwapBuffers starves it — the swap blocks
                // forever waiting for a free buffer, freezing the raster
                // thread after the first frames (the app kept compositing its
                // startup frame but never rendered again). By swap time the
                // parent processed the fd sent last frame, so only the newest
                // front still needs its lock.
                guard let surf = s.gbmSurface else { return false }
                if GpuDmaBufRenderer.swapchainDebug {
                    FileHandle.standardError.write(Data(
                        "[GpuDmaBufRenderer] present locked=\(s.lockedBos.count)\n".utf8))
                }
                while s.lockedBos.count > 1 {
                    gbm_surface_release_buffer(surf, s.lockedBos.removeFirst())
                }
                // Flip the engine's FBO onto the window surface, then swap —
                // the swap detiles into a linear front buffer; lock it and
                // tell the parent which buffer this frame landed in. The
                // parent's reimport path treats an fd message as a buffer
                // replacement, so only a changed front bo needs one.
                guard dmabuf_blit_flip_to_window(s.swapFbo,
                                                 Int32(s.bufferWidth),
                                                 Int32(s.bufferHeight)) != 0 else {
                    FileHandle.standardError.write(Data(
                        "[GpuDmaBufRenderer] present: flip blit failed\n".utf8))
                    return false
                }
                guard dmabuf_egl_swap_buffers(s.eglDisplay, s.eglWindowSurface) != 0 else {
                    FileHandle.standardError.write(Data(
                        "[GpuDmaBufRenderer] present: eglSwapBuffers failed\n".utf8))
                    return false
                }
                guard let front = gbm_surface_lock_front_buffer(surf) else {
                    FileHandle.standardError.write(Data(
                        "[GpuDmaBufRenderer] present: lock_front_buffer returned NULL (locked=\(s.lockedBos.count))\n".utf8))
                    return false
                }
                s.lockedBos.append(front)
                if front != s.lastSentBo {
                    let boFd: Int32
                    if let cached = s.boFds[front] {
                        boFd = cached
                    } else {
                        boFd = gbm_bo_get_fd(front)
                        s.boFds[front] = boFd
                    }
                    if boFd >= 0 {
                        var meta = DmaBufMeta(width: Int32(s.bufferWidth),
                                              height: Int32(s.bufferHeight),
                                              stride: Int32(gbm_bo_get_stride(front)),
                                              fourcc: s.swapFourcc)
                        // On EAGAIN lastSentBo stays put, so the next present
                        // retries rather than stranding the parent on a stale
                        // buffer.
                        if dmabuf_send_fd(s.socketFd, boFd, &meta,
                                          MemoryLayout<DmaBufMeta>.size) == 0 {
                            s.lastSentBo = front
                        }
                    }
                }
            } else {
                // Submit GPU commands (non-blocking). DMA-BUF implicit sync
                // ensures the parent's texture read waits for our write to complete.
                dmabuf_gl_flush()
            }
            // Signal parent that a new frame is ready (single byte 'F')
            var signal: UInt8 = 0x46
            _ = Glibc.write(s.socketFd, &signal, 1)
            return true
        }

        rendererConfig.open_gl.fbo_with_frame_info_callback = { userData, frameInfo -> UInt32 in
            guard let userData = userData else { return 0 }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()

            // Check engine's requested frame size against pending resize.
            // The engine determines this from viewport metrics (set async via
            // FlutterEngineSendWindowMetricsEvent). If a resize is pending but
            // the engine still requests the old size, defer — applying the FBO
            // resize now would cause Skia to create a surface at the old size
            // wrapping the new larger FBO, producing blurry upscaled rendering.
            let reqW = frameInfo?.pointee.size.width ?? 0
            let reqH = frameInfo?.pointee.size.height ?? 0

            // Swapchain mode renders into the plain FBO that present() blits
            // to the window surface; a resize rebuilds surface + FBO together.
            if s.swapchain {
                if GpuDmaBufRenderer.swapchainDebug {
                    FileHandle.standardError.write(Data(
                        "[GpuDmaBufRenderer] fbo cb req=\(Int(reqW))x\(Int(reqH)) buf=\(s.bufferWidth)x\(s.bufferHeight)\n".utf8))
                }
                guard let newSize = s.takePendingResize() else { return s.swapFbo }
                if Int(reqW) != newSize.width || Int(reqH) != newSize.height {
                    s.setPendingResize(newSize)
                    return s.swapFbo
                }
                s.rebuildSwapchain(width: newSize.width, height: newSize.height)
                return s.swapFbo
            }

            guard let newSize = s.takePendingResize() else {
                return s.fboName
            }

            // Defer resize if engine hasn't processed the new viewport metrics yet
            if Int(reqW) != newSize.width || Int(reqH) != newSize.height {
                s.setPendingResize(newSize)
                return s.fboName
            }

            // Engine size matches — safe to apply the FBO resize now
            let newW = newSize.width
            let newH = newSize.height
            let formatABGR8888: UInt32 = 0x34324241
            let useFlags = GBM_BO_USE_LINEAR.rawValue | GBM_BO_USE_RENDERING.rawValue

            // 1. Destroy old FBO
            if s.fboName != 0 {
                dmabuf_destroy_fbo(s.eglDisplay, s.fboName,
                                   s.fboEglImage, s.fboColorTex, s.fboStencilRb)
                s.fboName = 0
            }
            // 2. Close old DMA-BUF fd and destroy old GBM BO
            if s.dmaFd >= 0 { Glibc.close(s.dmaFd); s.dmaFd = -1 }
            if let oldBo = s.gbmBo { gbm_bo_destroy(oldBo); s.gbmBo = nil }

            // 3. Create new GBM BO
            guard let newBo = gbm_bo_create(s.gbmDevice!, UInt32(newW), UInt32(newH),
                                             formatABGR8888, useFlags) else {
                FileHandle.standardError.write(Data("[GpuDmaBufRenderer] resize: gbm_bo_create failed\n".utf8))
                return 0
            }
            let newDmaFd = gbm_bo_get_fd(newBo)
            let newStride = Int32(gbm_bo_get_stride(newBo))

            // 4. Create new FBO
            var eglImage: UnsafeMutableRawPointer? = nil
            var colorTex: UInt32 = 0
            var stencilRb: UInt32 = 0
            let newFbo = dmabuf_create_fbo(s.eglDisplay, newDmaFd,
                                            Int32(newW), Int32(newH), newStride,
                                            formatABGR8888,
                                            &eglImage, &colorTex, &stencilRb)
            guard newFbo != 0 else {
                FileHandle.standardError.write(Data("[GpuDmaBufRenderer] resize: dmabuf_create_fbo failed\n".utf8))
                gbm_bo_destroy(newBo)
                Glibc.close(newDmaFd)
                return 0
            }

            // 5. Update state
            s.gbmBo = newBo
            s.dmaFd = newDmaFd
            s.stride = newStride
            s.fboName = newFbo
            s.fboEglImage = eglImage
            s.fboColorTex = colorTex
            s.fboStencilRb = stencilRb
            s.bufferWidth = newW
            s.bufferHeight = newH

            // 6. Send new DMA-BUF fd + metadata to parent
            var meta = DmaBufMeta(
                width: Int32(newW), height: Int32(newH),
                stride: newStride, fourcc: formatABGR8888
            )
            _ = dmabuf_send_fd(s.socketFd, newDmaFd, &meta,
                               MemoryLayout<DmaBufMeta>.size)

            return s.fboName
        }

        rendererConfig.open_gl.make_resource_current = { userData -> Bool in
            guard let userData = userData else { return false }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            return dmabuf_egl_make_current(s.eglDisplay, s.resourceContext) != 0
        }

        rendererConfig.open_gl.gl_proc_resolver = { _, name -> UnsafeMutableRawPointer? in
            guard let name = name else { return nil }
            return dmabuf_egl_get_proc_address(name)
        }

        rendererConfig.open_gl.gl_external_texture_frame_callback = {
            userData, textureId, width, height, textureOut -> Bool in
            guard let userData = userData, let textureOut = textureOut else { return false }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            return s.populateExternalTexture(textureId, textureOut: textureOut)
        }

        rendererConfig.open_gl.fbo_reset_after_present = false

        // 3. Configure project args
        var args = FlutterProjectArgs()
        args.struct_size = MemoryLayout<FlutterProjectArgs>.size
        // As a composited child of DesktopShellApp we inherit the parent's cwd,
        // so the relative fallback may not point at the engine. Honor
        // FLUTTER_ENGINE_OUT (forwarded from the parent's environment) when set.
        let engineOutDir = ProcessInfo.processInfo.environment["FLUTTER_ENGINE_OUT"]
            ?? "../engine/src/out/host_debug"
        let assetsPath = strdup("\(engineOutDir)/flutter_assets")!
        let icuPath = strdup("\(engineOutDir)/icudtl.dat")!
        args.assets_path = UnsafePointer(assetsPath)
        args.icu_data_path = UnsafePointer(icuPath)

        // Use Skia OpenGL backend (Impeller disabled for broader GPU compat)
        let argv0 = strdup("FlutterDemoApp")!
        let argv1 = strdup("--enable-impeller=false")!
        let argvBuf = UnsafeMutableBufferPointer<UnsafePointer<CChar>?>.allocate(capacity: 3)
        argvBuf[0] = UnsafePointer(argv0)
        argvBuf[1] = UnsafePointer(argv1)
        argvBuf[2] = nil
        args.command_line_argc = 2
        args.command_line_argv = UnsafePointer(argvBuf.baseAddress!)

        // 4. Configure custom task runner (platform thread)
        var platformTaskRunner = FlutterTaskRunnerDescription()
        platformTaskRunner.struct_size = MemoryLayout<FlutterTaskRunnerDescription>.size
        platformTaskRunner.user_data = statePtr

        platformTaskRunner.runs_task_on_current_thread_callback = { userData -> Bool in
            guard let userData = userData else { return false }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            return pthread_equal(pthread_self(), s.mainThreadPthread) != 0
        }

        platformTaskRunner.post_task_callback = { task, targetTimeNanos, userData in
            guard let userData = userData else { return }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            s.taskQueue.enqueue(task, targetNanos: targetTimeNanos)
        }

        // 4b. UI task runner — merged onto the main thread, mirroring the
        // shell (fl_drm_view.cc). Left null, the engine spins up its own
        // io.flutter.ui thread and the widget pipeline runs THERE, while
        // DispatchQueue.main closures (a pty reader's setState, timers,
        // @MainActor continuations) run on the main thread's GCD drain —
        // two threads mutating one widget tree. The old 100ms GCD cadence
        // kept the overlap rare (mutation drained, then main slept while
        // the UI thread built); prompt GCD wakeups made it a reliable
        // segfault in swiftCore refcounting under a flooding client. Both
        // descriptions post to the same queue and carry the same (default)
        // identifier, which embedder.h requires of runners that service
        // one thread.
        var uiTaskRunner = FlutterTaskRunnerDescription()
        uiTaskRunner.struct_size = MemoryLayout<FlutterTaskRunnerDescription>.size
        uiTaskRunner.user_data = statePtr
        uiTaskRunner.runs_task_on_current_thread_callback = { userData -> Bool in
            guard let userData = userData else { return false }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            return pthread_equal(pthread_self(), s.mainThreadPthread) != 0
        }
        uiTaskRunner.post_task_callback = { task, targetTimeNanos, userData in
            guard let userData = userData else { return }
            let s = Unmanaged<GpuRendererState>.fromOpaque(userData).takeUnretainedValue()
            s.taskQueue.enqueue(task, targetNanos: targetTimeNanos)
        }

        var taskRunners = FlutterCustomTaskRunners()
        taskRunners.struct_size = MemoryLayout<FlutterCustomTaskRunners>.size

        // 5. Initialize engine
        var eng: OpaquePointer? = nil
        let initResult = withUnsafeMutablePointer(to: &callbacks) { cbPtr in
            withUnsafeMutablePointer(to: &platformTaskRunner) { taskRunnerPtr in
                taskRunners.platform_task_runner = UnsafePointer(taskRunnerPtr)
                return withUnsafeMutablePointer(to: &uiTaskRunner) { uiRunnerPtr in
                    taskRunners.ui_task_runner = UnsafePointer(uiRunnerPtr)
                    return withUnsafeMutablePointer(to: &taskRunners) { taskRunnersPtr in
                        args.custom_task_runners = UnsafePointer(taskRunnersPtr)
                        return FlutterEngineInitializeSwift(
                            Int(FLUTTER_ENGINE_VERSION),
                            &rendererConfig,
                            &args,
                            statePtr,  // user_data -> passed to renderer callbacks
                            UnsafeRawPointer(cbPtr),
                            &eng
                        )
                    }
                }
            }
        }
        guard initResult == kSuccess, let eng = eng else {
            print("[GpuDmaBufRenderer] FlutterEngineInitializeSwift failed")
            return
        }
        engine = eng
        state.engine = eng
        print("[GpuDmaBufRenderer] Engine initialized (OpenGL)")

        // 6. Run the engine
        let runResult = FlutterEngineRunInitializedSwift(eng)
        guard runResult == kSuccess else {
            print("[GpuDmaBufRenderer] FlutterEngineRunInitializedSwift failed")
            return
        }
        print("[GpuDmaBufRenderer] Engine running")

        // 6.5 Window stream: the shell relays desktop windows overlapping an
        // externally sourced output (per-screen shell only). Started after
        // the engine runs so texture registrations reach it.
        if let winSock = ProcessInfo.processInfo
            .environment["FLUTTER_WINDOW_STREAM_SOCKET"], !winSock.isEmpty {
            state.startWindowStream(path: winSock)
        }

        // 7. Send initial window metrics
        var metrics = FlutterWindowMetricsEvent()
        metrics.struct_size = MemoryLayout<FlutterWindowMetricsEvent>.size
        metrics.width = Int(width)
        metrics.height = Int(height)
        metrics.pixel_ratio = pixelRatio
        metrics.view_id = 0
        FlutterEngineSendWindowMetricsEvent(eng, &metrics)

        // 8. Schedule first frame
        PlatformDispatcher.instance.scheduleFrame()
        print("[GpuDmaBufRenderer] First frame scheduled, entering event loop")

        // 9. GCD main queue integration — drain DispatchQueue.main so
        // @MainActor / async-await continuations fire on the main thread.
        //
        // The handle fd IS pollable, but it is an eventfd that the drain
        // callback does NOT reset — only read()ing it does. Poll it without
        // that read and it stays readable after the first drain forever,
        // which reads as "always readable" and once demoted this loop to a
        // 100ms timeout. That pinned every child whose repaints arrive via
        // DispatchQueue.main.async — a pty reader thread, say — to exactly
        // 10fps: the enqueue wakes no fd this loop polled, so each repaint
        // sat a full timeout. Protocol: poll it, and on POLLIN read it
        // CLEARED before the next drain — anything enqueued after the read
        // re-signals the fd, so a wakeup can be spurious but never lost.
        typealias GCDDrainFunc = @convention(c) (UnsafeMutableRawPointer?) -> Void
        typealias GCDHandleFunc = @convention(c) () -> Int32
        let gcdDrainSym = dlsym(nil, "_dispatch_main_queue_callback_4CF")
        let gcdDrain: GCDDrainFunc? = gcdDrainSym.map { unsafeBitCast($0, to: GCDDrainFunc.self) }
        let gcdHandleSym = dlsym(nil, "_dispatch_get_main_queue_handle_4CF")
        let gcdFd: Int32 = gcdHandleSym.map { unsafeBitCast($0, to: GCDHandleFunc.self)() } ?? -1

        // 10. Event loop — poll on task queue pipe, parent socket, and the
        // GCD main queue handle (fd -1 if unavailable; poll ignores those).
        running = true
        var pointerAdded = false
        var pfds: (pollfd, pollfd, pollfd) = (
            pollfd(fd: state.taskQueue.wakeupReadFd, events: Int16(POLLIN), revents: 0),
            pollfd(fd: state.socketFd, events: Int16(POLLIN), revents: 0),
            pollfd(fd: gcdFd, events: Int16(POLLIN), revents: 0)
        )
        while running {
            // Drain GCD main queue (@MainActor, DispatchQueue.main.async)
            gcdDrain?(nil)

            // Drain expired engine tasks
            let (expired, nextNanos) = state.taskQueue.drainExpired()
            for (task, _) in expired {
                var mutableTask = task
                FlutterEngineRunTask(eng, &mutableTask)
            }

            // Compute timeout until next task deadline (cap at 100ms)
            let timeoutMs: Int32
            if let nextNanos = nextNanos {
                let now = FlutterEngineGetCurrentTime()
                if nextNanos > now {
                    timeoutMs = Int32(min((nextNanos - now) / 1_000_000, 100))
                } else {
                    timeoutMs = 0
                }
            } else {
                timeoutMs = 100  // Idle backstop; the GCD fd wakes us early
            }

            pfds.0.revents = 0
            pfds.1.revents = 0
            pfds.2.revents = 0
            withUnsafeMutablePointer(to: &pfds) { ptr in
                ptr.withMemoryRebound(to: pollfd.self, capacity: 3) { pollPtr in
                    _ = poll(pollPtr, 3, timeoutMs)
                }
            }

            // Drain the task queue pipe
            if pfds.0.revents & Int16(POLLIN) != 0 {
                state.taskQueue.consumeWakeup()
            }

            // Consume the GCD eventfd so it goes quiet until the next
            // enqueue; the drain at the top of the loop does the work.
            if pfds.2.revents & Int16(POLLIN) != 0 {
                var v: UInt64 = 0
                _ = Glibc.read(gcdFd, &v, 8)
            }

            // Parent closed the socket — exit
            if pfds.1.revents & Int16(POLLHUP | POLLERR) != 0 {
                running = false
                break
            }

            // Process input events from parent
            if pfds.1.revents & Int16(POLLIN) != 0 {
                var inputEvent = DmaBufInputEvent(x: 0, y: 0, buttons: 0, type: 0, phase: 0)
                let eventSize = MemoryLayout<DmaBufInputEvent>.size
                while true {
                    let n = Glibc.read(state.socketFd, &inputEvent, eventSize)
                    if n == 0 { running = false; break }  // EOF — parent closed socket
                    if n < eventSize { break }

                    if inputEvent.type == Int32(DMABUF_INPUT_RESIZE) {
                        // Parent sends logical dimensions; scale to physical
                        // pixels (rounded, matching the initial buffer sizing)
                        let physW = Int((inputEvent.x * pixelRatio).rounded())
                        let physH = Int((inputEvent.y * pixelRatio).rounded())
                        if physW > 0 && physH > 0 {
                            state.setPendingResize((width: physW, height: physH))
                            // Update the C++ engine's viewport metrics (physical pixels + DPI).
                            var metrics = FlutterWindowMetricsEvent()
                            metrics.struct_size = MemoryLayout<FlutterWindowMetricsEvent>.size
                            metrics.width = physW
                            metrics.height = physH
                            metrics.pixel_ratio = pixelRatio
                            metrics.view_id = 0
                            FlutterEngineSendWindowMetricsEvent(eng, &metrics)
                            // Update the Swift framework's view metrics so the widget
                            // tree re-layouts at the new size. This also triggers
                            // onMetricsChanged → scheduleFrame().
                            //
                            // devicePixelRatio must travel with the size:
                            // ViewConfiguration defaults it to 1.0, so leaving
                            // it out silently reset a 2x view to 1x on every
                            // resize — the app relaid out at physical==logical
                            // and rendered half-size after fullscreen/maximize/
                            // drag-resize. Invisible on a 1x panel, where the
                            // default happens to be right.
                            let newSize = Size(Double(physW), Double(physH))
                            PlatformDispatcher.instance._updateWindowMetrics(
                                0,
                                ViewConfiguration(
                                    devicePixelRatio: pixelRatio,
                                    size: newSize,
                                    viewConstraints: ViewConstraints(tight: newSize)
                                )
                            )
                        }
                        continue
                    }

                    if inputEvent.type == DMABUF_CONTROL_SET_THEME {
                        GpuDmaBufRenderer.receiveThemePush(inputEvent.x > 0.5)
                        continue
                    }

                    if inputEvent.type == DMABUF_CONTROL_SET_LAYOUT {
                        GpuDmaBufRenderer.receiveLayoutPush(inputEvent.x > 0.5)
                        continue
                    }

                    if inputEvent.type == DMABUF_CONTROL_SET_WALLPAPER {
                        GpuDmaBufRenderer.receiveWallpaperPush(Int(inputEvent.x))
                        continue
                    }

                    if inputEvent.type == DMABUF_CONTROL_SET_SCREENSAVER {
                        GpuDmaBufRenderer.receiveScreensaverPush(Int(inputEvent.x))
                        continue
                    }

                    if inputEvent.type == DMABUF_DISPLAY_NAME {
                        GpuDmaBufRenderer.receiveDisplayNameChunk(
                            inputEvent.buttons, index: Int(inputEvent.x))
                        continue
                    }

                    if inputEvent.type == DMABUF_DISPLAY_INFO {
                        GpuDmaBufRenderer.receiveDisplayInfo(
                            width: inputEvent.x, height: inputEvent.y,
                            packed: inputEvent.buttons, phase: inputEvent.phase)
                        continue
                    }

                    if inputEvent.type == DMABUF_CONTROL_SET_DPI {
                        // Parent changed DPI — update pixel ratio and resize buffer
                        let newDpi = inputEvent.x
                        let oldDpi = pixelRatio
                        if newDpi >= 0.5 && newDpi <= 4.0 && newDpi != oldDpi {
                            FileHandle.standardError.write(Data("[GpuDmaBufRenderer] DPI changed: \(oldDpi) → \(newDpi)\n".utf8))
                            pixelRatio = newDpi
                            // Recompute physical size: newPhys = oldPhys * newDpi / oldDpi
                            let physW = Int((Double(state.bufferWidth) * newDpi / oldDpi).rounded())
                            let physH = Int((Double(state.bufferHeight) * newDpi / oldDpi).rounded())
                            if physW > 0 && physH > 0 {
                                state.setPendingResize((width: physW, height: physH))
                                var metrics = FlutterWindowMetricsEvent()
                                metrics.struct_size = MemoryLayout<FlutterWindowMetricsEvent>.size
                                metrics.width = physW
                                metrics.height = physH
                                metrics.pixel_ratio = newDpi
                                metrics.view_id = 0
                                FlutterEngineSendWindowMetricsEvent(eng, &metrics)
                                let newSize = Size(Double(physW), Double(physH))
                                PlatformDispatcher.instance._updateWindowMetrics(
                                    0,
                                    ViewConfiguration(
                                        devicePixelRatio: newDpi,
                                        size: newSize,
                                        viewConstraints: ViewConstraints(tight: newSize)
                                    )
                                )
                            }
                        }
                        continue
                    }

                    if inputEvent.type == Int32(DMABUF_INPUT_KEY) {
                        // Parent forwards keyboard input for the focused
                        // window: x = physical HID key, y = logical keysym,
                        // buttons = Unicode scalar (0 = none), phase =
                        // 0/1/2 for down/up/repeat. Route through the engine
                        // so it takes the same keydata path as native input.
                        var keyEvent = FlutterKeyEvent()
                        keyEvent.struct_size = MemoryLayout<FlutterKeyEvent>.size
                        keyEvent.timestamp = Double(FlutterEngineGetCurrentTime() / 1000)
                        switch inputEvent.phase {
                        case 1: keyEvent.type = kFlutterKeyEventTypeUp
                        case 2: keyEvent.type = kFlutterKeyEventTypeRepeat
                        default: keyEvent.type = kFlutterKeyEventTypeDown
                        }
                        keyEvent.physical = UInt64(inputEvent.x)
                        keyEvent.logical = UInt64(inputEvent.y)
                        keyEvent.synthesized = false
                        keyEvent.device_type = kFlutterKeyEventDeviceTypeKeyboard
                        let scalarValue = UInt32(truncatingIfNeeded: inputEvent.buttons)
                        if inputEvent.phase != 1, scalarValue != 0,
                           let scalar = Unicode.Scalar(scalarValue) {
                            String(Character(scalar)).withCString { cstr in
                                keyEvent.character = cstr
                                _ = FlutterEngineSendKeyEvent(eng, &keyEvent, nil, nil)
                            }
                        } else {
                            keyEvent.character = nil
                            _ = FlutterEngineSendKeyEvent(eng, &keyEvent, nil, nil)
                        }
                        continue
                    }

                    if inputEvent.type == Int32(DMABUF_INPUT_SCROLL) {
                        // Wheel scroll: deltas packed as two Float32 bit
                        // patterns in `buttons` (dx low, dy high), logical px.
                        let physX = inputEvent.x * pixelRatio
                        let physY = inputEvent.y * pixelRatio
                        let bits = UInt64(bitPattern: inputEvent.buttons)
                        let dx = Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
                        let dy = Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits >> 32)))
                        if !pointerAdded {
                            var addEvent = FlutterPointerEvent()
                            addEvent.struct_size = MemoryLayout<FlutterPointerEvent>.size
                            addEvent.phase = FlutterPointerPhase(rawValue: 4) // kAdd
                            addEvent.timestamp = Int(FlutterEngineGetCurrentTime() / 1000)
                            addEvent.x = physX
                            addEvent.y = physY
                            addEvent.device = 0
                            addEvent.signal_kind = kFlutterPointerSignalKindNone
                            addEvent.device_kind = kFlutterPointerDeviceKindMouse
                            addEvent.buttons = 0
                            addEvent.view_id = 0
                            FlutterEngineSendPointerEvent(eng, &addEvent, 1)
                            pointerAdded = true
                        }
                        var scrollEvent = FlutterPointerEvent()
                        scrollEvent.struct_size = MemoryLayout<FlutterPointerEvent>.size
                        scrollEvent.phase = FlutterPointerPhase(rawValue: 6) // kHover
                        scrollEvent.timestamp = Int(FlutterEngineGetCurrentTime() / 1000)
                        scrollEvent.x = physX
                        scrollEvent.y = physY
                        scrollEvent.device = 0
                        scrollEvent.signal_kind = kFlutterPointerSignalKindScroll
                        scrollEvent.scroll_delta_x = dx * pixelRatio
                        scrollEvent.scroll_delta_y = dy * pixelRatio
                        scrollEvent.device_kind = kFlutterPointerDeviceKindMouse
                        scrollEvent.buttons = 0
                        scrollEvent.view_id = 0
                        FlutterEngineSendPointerEvent(eng, &scrollEvent, 1)
                        continue
                    }

                    if inputEvent.type == Int32(DMABUF_INPUT_POINTER) {
                        let phase = inputEvent.phase
                        // Parent sends logical coords; engine expects physical pixels
                        let physX = inputEvent.x * pixelRatio
                        let physY = inputEvent.y * pixelRatio
                        // Synthesize kAdd if pointer hasn't been added yet
                        if !pointerAdded && phase != 4 /* kAdd */ {
                            var addEvent = FlutterPointerEvent()
                            addEvent.struct_size = MemoryLayout<FlutterPointerEvent>.size
                            addEvent.phase = FlutterPointerPhase(rawValue: 4) // kAdd
                            addEvent.timestamp = Int(FlutterEngineGetCurrentTime() / 1000)
                            addEvent.x = physX
                            addEvent.y = physY
                            addEvent.device = 0
                            addEvent.signal_kind = kFlutterPointerSignalKindNone
                            addEvent.device_kind = kFlutterPointerDeviceKindMouse
                            addEvent.buttons = 0
                            addEvent.view_id = 0
                            FlutterEngineSendPointerEvent(eng, &addEvent, 1)
                            pointerAdded = true
                        }
                        if pointerAdded && phase == 4 { continue } // Don't double-add

                        var ptrEvent = FlutterPointerEvent()
                        ptrEvent.struct_size = MemoryLayout<FlutterPointerEvent>.size
                        ptrEvent.phase = FlutterPointerPhase(rawValue: UInt32(phase))
                        ptrEvent.timestamp = Int(FlutterEngineGetCurrentTime() / 1000)
                        ptrEvent.x = physX
                        ptrEvent.y = physY
                        ptrEvent.device = 0
                        ptrEvent.signal_kind = kFlutterPointerSignalKindNone
                        ptrEvent.device_kind = kFlutterPointerDeviceKindMouse
                        ptrEvent.buttons = inputEvent.buttons
                        ptrEvent.view_id = 0
                        if GpuDmaBufRenderer.swapchainDebug && phase != 6 && phase != 3 {
                            FileHandle.standardError.write(Data(
                                "[GpuDmaBufRenderer] ptr phase=\(phase) x=\(physX) y=\(physY) buttons=\(inputEvent.buttons)\n".utf8))
                        }
                        FlutterEngineSendPointerEvent(eng, &ptrEvent, 1)
                    }
                }
            }
        }
    }
}
#endif
