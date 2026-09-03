// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import FlutterEmbedderBridge
import DmaBufBridge
import Foundation
import Glibc
import WaylandServerBridge  // wayland_server_dmabuf_modifier_importable

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - GL Constants
// ═══════════════════════════════════════════════════════════════════════════════

private let GL_TEXTURE_2D: UInt32       = 0x0DE1
private let GL_RGBA: UInt32             = 0x1908
private let GL_RGBA8: UInt32            = 0x8058
private let GL_UNSIGNED_BYTE: UInt32    = 0x1401
private let GL_TEXTURE_MIN_FILTER: UInt32 = 0x2801
private let GL_TEXTURE_MAG_FILTER: UInt32 = 0x2800
private let GL_NEAREST: Int32           = 0x2600
private let GL_LINEAR: Int32            = 0x2601
private let GL_UNPACK_ALIGNMENT: UInt32 = 0x0CF5

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - GL Function Types
// ═══════════════════════════════════════════════════════════════════════════════

private typealias GLGenTexturesFunc     = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
private typealias GLBindTextureFunc     = @convention(c) (UInt32, UInt32) -> Void
private typealias GLTexImage2DFunc      = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
// glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, type, pixels)
private typealias GLTexSubImage2DFunc   = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
private typealias GLTexParameteriFunc   = @convention(c) (UInt32, UInt32, Int32) -> Void
private typealias GLDeleteTexturesFunc  = @convention(c) (Int32, UnsafePointer<UInt32>?) -> Void
private typealias GLPixelStoreiFunc     = @convention(c) (UInt32, Int32) -> Void
private typealias EGLGetCurrentDisplayFunc = @convention(c) () -> UnsafeMutableRawPointer?

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - TextureEntry
// ═══════════════════════════════════════════════════════════════════════════════

/// Identity of an imported dma-buf: the buffer itself (device + inode) plus
/// the import parameters, since the same buffer may legitimately be imported
/// with different geometry after a resize.
private struct BufferKey: Hashable {
    let dev: UInt64
    let ino: UInt64
    let width: Int
    let height: Int
    let stride: Int
    let fourcc: UInt32
    let modifier: UInt64
}

/// Cached EGLImages per texture. Chrome triple buffers; a few extra slots
/// absorb a resize (old and new geometry briefly coexist).
private let kImageCacheLimit = 6

/// Identify the dma-buf behind `fd`. Returns nil if fstat fails, in which case
/// the caller falls back to importing unconditionally.
private func bufferIdentity(_ fd: Int32) -> (dev: UInt64, ino: UInt64)? {
    var st = stat()
    guard fstat(fd, &st) == 0 else { return nil }
    return (UInt64(st.st_dev), UInt64(st.st_ino))
}

/// Internal bookkeeping for a single registered texture.
private class TextureEntry {
    var pixelData: UnsafeMutableRawPointer?
    var width: Int = 0
    var height: Int = 0
    var glTextureName: UInt32 = 0
    var dirty: Bool = false

    /// Dimensions the GL texture's storage was last allocated at, so the CPU
    /// upload path can tell a re-upload from a resize. 0 = no storage yet.
    /// A client that keeps its size — which is every client, most frames —
    /// then re-uploads with glTexSubImage2D instead of reallocating.
    var glTexWidth: Int = 0
    var glTexHeight: Int = 0

    /// Optional GL renderer for GPU-based rendering (bypasses CPU pixel upload).
    var glRenderer: GLRenderer?

    /// DMA-BUF fields for zero-copy GPU buffer import.
    var dmaFd: Int32 = -1
    var dmaStride: Int = 0
    var dmaFourcc: UInt32 = 0
    var dmaModifier: UInt64 = (1 << 56) - 1  // DRM_FORMAT_MOD_INVALID
    var eglImage: UnsafeMutableRawPointer? = nil  // EGLImageKHR
    /// When true, populateTexture must re-resolve the EGLImage for the current
    /// buffer (cache hit rebinds; miss imports).
    var needsReimport: Bool = false
    /// The texture was given 1x1 black storage because its FIRST import
    /// failed (hostile or unimportable modifier). Without any storage the
    /// engine would sample an incomplete texture — driver-defined behaviour
    /// on a foreign-buffer path that is already in an error state. Reset by
    /// the first successful import (which replaces the storage wholesale).
    var hasFallbackTexel: Bool = false

    /// EGLImages already imported for this texture, keyed by the underlying
    /// dma-buf's identity. A client cycles a small buffer pool (Chrome triple
    /// buffers), so the same handful of buffers is committed over and over —
    /// importing each one once and rebinding is far cheaper than an
    /// eglCreateImageKHR + destroy of a 4K image on every commit.
    ///
    /// Keyed on the dma-buf INODE, not the fd number: we dup the fd at every
    /// commit and close the old dup, so the kernel recycles fd numbers between
    /// unrelated buffers (the same fd number has been observed as both a
    /// 3840x2020 toplevel and a 2000x724 popup). Two dups of one dma-buf share
    /// an inode; distinct dma-bufs never do.
    var imageCache: [BufferKey: UnsafeMutableRawPointer] = [:]
    /// Insertion order for `imageCache`, oldest first — evicted beyond
    /// `kImageCacheLimit`.
    var imageCacheOrder: [BufferKey] = []

    /// Buffer identities whose import was REJECTED (foreign/unimportable
    /// modifier). A failed import never spontaneously succeeds, so retrying
    /// it on every commit is pure waste — and worse than waste: a client
    /// cycling full-screen unimportable buffers at 60fps drove the AMD GL
    /// stack to an ENOMEM CS rejection and took the shell down (the PRIME
    /// incident, 2026-08-08). Recording the failure bounds the attempts to
    /// one per unique buffer. Same inode identity as imageCache; bounded the
    /// same way so a hostile client cannot grow it without bound.
    var importFailures: Set<BufferKey> = []
    var importFailureOrder: [BufferKey] = []

    /// When true, the registry owns dmaFd (a dup made at the Wayland commit
    /// boundary) and is responsible for closing it. Child-app fds stay owned
    /// by LinuxProcessAppManager (ownsFd = false).
    var ownsFd: Bool = false
    /// Owned fds replaced by a newer commit but possibly still referenced by
    /// an in-flight populateTexture. Closed by the next populateTexture call
    /// (single raster thread ⇒ the previous populate has finished with them).
    var retiredFds: [Int32] = []

    /// Target dimensions from compositor resize — used to stretch old texture
    /// to fill the new window area during resize lag (avoids black area).
    /// When 0, uses actual DMA-BUF dimensions.
    var targetWidth: Int = 0
    var targetHeight: Int = 0

    /// True for Wayland client surfaces. These have top-left pixel origin and
    /// need a 180° flip to counter the engine's kBottomLeft_GrSurfaceOrigin.
    var isWaylandSurface: Bool = false

    /// True for Wayland popup surfaces. Popups use premultiplied alpha
    /// (translucent backgrounds) and should NOT have their format overridden
    /// to XBGR. Toplevel surfaces have unused alpha (0x00) and need XBGR.
    var isPopupSurface: Bool = false

    deinit {
        pixelData?.deallocate()
        // Close owned fds. populateTexture holds a strong reference to the
        // entry while importing, so deinit cannot race an in-flight import.
        if ownsFd && dmaFd >= 0 { Glibc.close(dmaFd) }
        for fd in retiredFds { Glibc.close(fd) }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - LinuxTextureRegistry
// ═══════════════════════════════════════════════════════════════════════════════

/// Central texture management for Linux.
///
/// Manages the lifecycle of external textures registered with the Flutter
/// embedder. Pixel data is written on the main thread (by SoftwareRenderer
/// or LinuxOffscreenFlutterApp) and read on the engine's raster thread
/// (via the GL texture frame callback).
///
/// Thread safety: NSLock protects the texture entry store. GL functions are
/// only called from the raster thread (inside the texture callback).
class LinuxTextureRegistry: @unchecked Sendable {

    /// Fired on the raster thread when a dma-buf EGLImage import fails
    /// (fourcc, modifier). WaylandIntegration wires this to demote the
    /// modifier from the linux-dmabuf advertisement — the EGL modifier
    /// query over-reports what zink can import, so the failed import is
    /// the ground truth that corrects the advertisement.
    /// nonisolated(unsafe): set once during startup wiring, read on the
    /// raster thread.
    nonisolated(unsafe) static var onDmaBufImportFailure: ((UInt32, UInt64) -> Void)?

    private let lock = NSLock()
    private var entries: [Int64: TextureEntry] = [:]
    private var nextId: Int64 = 1

    // GL function pointers — lazy-loaded on first use from the raster thread
    // (glfwGetProcAddress requires a current GL context, which is only
    // available on the raster thread when the engine calls our callback)
    private var _glLoaded = false
    private var _glGenTextures: GLGenTexturesFunc!
    private var _glBindTexture: GLBindTextureFunc!
    private var _glTexImage2D: GLTexImage2DFunc!
    private var _glTexSubImage2D: GLTexSubImage2DFunc!
    private var _glTexParameteri: GLTexParameteriFunc!
    private var _glDeleteTextures: GLDeleteTexturesFunc!
    private var _glPixelStorei: GLPixelStoreiFunc!
    private var _eglGetCurrentDisplay: EGLGetCurrentDisplayFunc!

    /// GL function loader — set before first use. In GLFW mode, defaults to
    /// glfwGetProcAddress. In DRM mode, set to fl_drm_view_get_proc_address.
    var glProcAddressResolver: ((UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)?

    // ─── Init ────────────────────────────────────────────────────────────

    init() {}

    /// Loads GL function pointers. Must be called with a GL context current
    /// (i.e., from the raster thread inside the texture frame callback).
    private func ensureGLLoaded() {
        guard !_glLoaded else { return }

        func loadGL<T>(_ name: String) -> T {
            guard let resolver = glProcAddressResolver else {
                fatalError("[LinuxTextureRegistry] No GL proc address resolver set")
            }
            guard let fn = name.withCString({ resolver($0) }) else {
                fatalError("[LinuxTextureRegistry] Failed to load GL function: \(name)")
            }
            return unsafeBitCast(fn, to: T.self)
        }

        _glGenTextures   = loadGL("glGenTextures")
        _glBindTexture   = loadGL("glBindTexture")
        _glTexImage2D    = loadGL("glTexImage2D")
        _glTexSubImage2D = loadGL("glTexSubImage2D")
        _glTexParameteri = loadGL("glTexParameteri")
        _glDeleteTextures = loadGL("glDeleteTextures")
        _glPixelStorei   = loadGL("glPixelStorei")
        _eglGetCurrentDisplay = loadGL("eglGetCurrentDisplay")
        _glLoaded = true
    }

    // ─── Registration ────────────────────────────────────────────────────

    /// Registers a new external texture with the engine.
    /// Returns a unique texture ID for use with TextureWidget.
    func registerTexture(engine: OpaquePointer) -> Int64 {
        lock.lock()
        let id = nextId
        nextId += 1
        entries[id] = TextureEntry()
        lock.unlock()

        FlutterEngineRegisterExternalTexture(engine, id)
        return id
    }

    /// Unregisters an external texture and schedules GL resource cleanup.
    func unregisterTexture(engine: OpaquePointer, id: Int64) {
        FlutterEngineUnregisterExternalTexture(engine, id)

        lock.lock()
        let entry = entries.removeValue(forKey: id)
        lock.unlock()

        if let entry = entry {
            if entry.glTextureName != 0 {
                lock.lock()
                _pendingDeleteTextures.append(entry.glTextureName)
                lock.unlock()
            }
            // Schedule EGLImage destruction. Everything this texture imported
            // lives in imageCache (entry.eglImage is one of its values, so it
            // must not be queued separately — that would double-destroy).
            lock.lock()
            if entry.imageCache.isEmpty {
                if let eglImage = entry.eglImage {
                    _pendingDestroyEglImages.append(eglImage)
                }
            } else {
                _pendingDestroyEglImages.append(contentsOf: entry.imageCache.values)
            }
            entry.imageCache.removeAll()
            entry.imageCacheOrder.removeAll()
            entry.eglImage = nil
            lock.unlock()
        }
    }

    private var _pendingDeleteTextures: [UInt32] = []
    private var _pendingDestroyEglImages: [UnsafeMutableRawPointer] = []

    /// Marks a texture as originating from a Wayland client surface.
    /// Wayland buffers use top-left origin and need a 180° flip to counter
    /// the engine's kBottomLeft_GrSurfaceOrigin assumption.
    func markAsWaylandSurface(id: Int64) {
        lock.lock()
        entries[id]?.isWaylandSurface = true
        lock.unlock()
    }

    func markAsPopupSurface(id: Int64) {
        lock.lock()
        entries[id]?.isPopupSurface = true
        lock.unlock()
    }

    // ─── GL Renderer ─────────────────────────────────────────────────────

    /// Attaches a GLRenderer to a texture. When set, populateTexture will
    /// use the renderer to render directly to the GL texture via FBO instead
    /// of uploading pixel data.
    func setGLRenderer(id: Int64, renderer: GLRenderer) {
        lock.lock()
        entries[id]?.glRenderer = renderer
        lock.unlock()
    }

    /// Marks a GL-rendered texture as needing a re-render and tells the
    /// engine the texture has new content.
    func markGLTextureDirty(engine: OpaquePointer, id: Int64) {
        FlutterEngineMarkExternalTextureFrameAvailable(engine, id)
        FlutterEngineScheduleFrame(engine)
    }

    /// The buffer is the same one, but what is inside it changed — a VM guest
    /// scans out into one dma-buf for the life of a resolution and only sends
    /// damage. Marks the entry dirty so populateTexture re-binds the EGLImage
    /// (some drivers need that to see a write they did not make), then tells
    /// the engine there is a new frame.
    func noteDmaBufContentChanged(engine: OpaquePointer, id: Int64) {
        lock.lock()
        entries[id]?.dirty = true
        lock.unlock()
        FlutterEngineMarkExternalTextureFrameAvailable(engine, id)
        FlutterEngineScheduleFrame(engine)
    }

    // ─── DMA-BUF Import ────────────────────────────────────────────────────

    /// Stores DMA-BUF fd and metadata for a texture. The actual EGLImage
    /// creation happens on the raster thread in populateTexture().
    func importDmaBuf(
        engine: OpaquePointer,
        id: Int64,
        fd: Int32,
        width: Int,
        height: Int,
        stride: Int,
        fourcc: UInt32,
        modifier: UInt64 = (1 << 56) - 1,
        ownsFd: Bool = false
    ) {
        lock.lock()
        guard let entry = entries[id] else {
            lock.unlock()
            if ownsFd && fd >= 0 { Glibc.close(fd) }
            return
        }
        // Retire the previous owned fd — an in-flight populateTexture may
        // still be importing from it, so it's closed by the NEXT populate.
        if entry.ownsFd && entry.dmaFd >= 0 && entry.dmaFd != fd {
            entry.retiredFds.append(entry.dmaFd)
        }
        entry.ownsFd = ownsFd
        entry.dmaFd = fd
        entry.width = width
        entry.height = height
        entry.dmaStride = stride
        entry.dmaFourcc = fourcc
        entry.dmaModifier = modifier
        entry.dirty = true
        lock.unlock()
        RecordingService.noteSourceContentChanged(textureId: id)

        FlutterEngineMarkExternalTextureFrameAvailable(engine, id)
        FlutterEngineScheduleFrame(engine)
    }

    /// Set target dimensions for a texture. During resize, the old texture
    /// is stretched to fill the new area (avoids black regions).
    func setTargetSize(id: Int64, width: Int, height: Int) {
        lock.lock()
        if let entry = entries[id] {
            entry.targetWidth = width
            entry.targetHeight = height
        }
        lock.unlock()
    }

    /// Re-imports a DMA-BUF after the child process resized its buffer.
    /// Marks the entry for reimport — the old EGLImage is kept alive until
    /// populateTexture creates the replacement, avoiding black frame flicker.
    func reimportDmaBuf(
        engine: OpaquePointer,
        id: Int64,
        fd: Int32,
        width: Int,
        height: Int,
        stride: Int,
        fourcc: UInt32,
        modifier: UInt64 = (1 << 56) - 1,
        ownsFd: Bool = false
    ) {
        lock.lock()
        guard let entry = entries[id] else {
            lock.unlock()
            if ownsFd && fd >= 0 { Glibc.close(fd) }
            return
        }
        // Keep old EGLImage alive (don't nil it) — populateTexture will
        // destroy it AFTER creating the new one, avoiding black frames.
        // Same deal for the previous owned fd: retire, don't close yet.
        if entry.ownsFd && entry.dmaFd >= 0 && entry.dmaFd != fd {
            entry.retiredFds.append(entry.dmaFd)
        }
        // populateTexture drains retiredFds, but only when the engine
        // actually samples this texture — a surface that keeps committing
        // while its texture goes unsampled (occluded, mid-teardown, engine
        // frame skipped) accumulates fds without bound, and a session was
        // observed at 939 stranded dups with libwayland spinning on EMFILE.
        // Close the oldest beyond a small window here instead: anything
        // eight generations stale cannot be referenced by an in-flight
        // populate, which only ever reads the current dmaFd (at most one
        // generation back).
        while entry.retiredFds.count > 8 {
            Glibc.close(entry.retiredFds.removeFirst())
        }
        entry.ownsFd = ownsFd
        entry.needsReimport = true
        entry.dmaFd = fd
        entry.width = width
        entry.height = height
        entry.dmaStride = stride
        entry.dmaFourcc = fourcc
        entry.dmaModifier = modifier
        entry.dirty = true
        lock.unlock()
        RecordingService.noteSourceContentChanged(textureId: id)

        FlutterEngineMarkExternalTextureFrameAvailable(engine, id)
        FlutterEngineScheduleFrame(engine)
    }

    // ─── Pixel Data Update ───────────────────────────────────────────────

    /// Updates the pixel data for a registered texture.
    /// Called on the main thread by the renderer.
    func updatePixelData(
        engine: OpaquePointer,
        id: Int64,
        data: UnsafeRawPointer,
        width: Int,
        height: Int
    ) {
        let byteCount = width * height * 4

        lock.lock()
        guard let entry = entries[id] else {
            lock.unlock()
            return
        }

        if entry.width != width || entry.height != height {
            entry.pixelData?.deallocate()
            entry.pixelData = UnsafeMutableRawPointer.allocate(
                byteCount: byteCount,
                alignment: MemoryLayout<UInt8>.alignment
            )
            entry.width = width
            entry.height = height
        }

        entry.pixelData?.copyMemory(from: data, byteCount: byteCount)
        entry.dirty = true
        lock.unlock()
        RecordingService.noteSourceContentChanged(textureId: id)

        // Tell the rasterizer the texture has new content (clears cached image).
        FlutterEngineMarkExternalTextureFrameAvailable(engine, id)
        // Trigger a full frame rebuild. Using ScheduleFrame instead of relying
        // on Mark's internal ScheduleFrame(false) avoids a Skia crash in
        // DrawLastLayerTrees on VMware SVGA3D (repeated re-render-same-tree
        // crashes after ~5 iterations due to GPU resource accumulation).
        FlutterEngineScheduleFrame(engine)
    }

    // ─── GL Texture Population (raster thread) ──────────────────────────

    /// Called by the engine's raster thread via the texture frame callback.
    /// Creates or updates the GL texture from stored pixel data.
    ///
    /// Returns true if a texture was successfully populated.
    func populateTexture(
        id: Int64,
        width: Int,
        height: Int,
        textureOut: UnsafeMutablePointer<FlutterOpenGLTexture>
    ) -> Bool {
        ensureGLLoaded()

        // Delete any pending textures (we have GL context here)
        lock.lock()
        let pendingDeletes = _pendingDeleteTextures
        _pendingDeleteTextures.removeAll()
        lock.unlock()

        for texName in pendingDeletes {
            var name = texName
            _glDeleteTextures(1, &name)
        }

        // Destroy pending EGLImages
        lock.lock()
        let pendingEglImages = _pendingDestroyEglImages
        _pendingDestroyEglImages.removeAll()
        lock.unlock()

        if !pendingEglImages.isEmpty, let display = _eglGetCurrentDisplay() {
            for image in pendingEglImages {
                dmabuf_destroy_egl_image(display, image)
            }
        }

        lock.lock()
        guard let entry = entries[id] else {
            lock.unlock()
            return false
        }

        // Create GL texture if needed
        if entry.glTextureName == 0 {
            var texName: UInt32 = 0
            _glGenTextures(1, &texName)
            entry.glTextureName = texName

            // Initialize with correct size for GL renderer, or 1x1 placeholder
            let initW: Int32 = entry.glRenderer != nil ? Int32(entry.glRenderer!.width) : 1
            let initH: Int32 = entry.glRenderer != nil ? Int32(entry.glRenderer!.height) : 1
            _glBindTexture(GL_TEXTURE_2D, texName)
            _glTexImage2D(GL_TEXTURE_2D, 0, Int32(GL_RGBA), initW, initH, 0,
                          GL_RGBA, GL_UNSIGNED_BYTE, nil)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
            _glBindTexture(GL_TEXTURE_2D, 0)
        }

        let texName = entry.glTextureName
        let glRenderer = entry.glRenderer

        // GL renderer path: render directly to texture via FBO (no CPU pixels).
        if let glRenderer = glRenderer {
            let texW = glRenderer.width
            let texH = glRenderer.height
            lock.unlock()

            if glRenderer.dirty {
                glRenderer.renderToTexture(texName)
            }

            textureOut.pointee.target = GL_TEXTURE_2D
            textureOut.pointee.name = texName
            textureOut.pointee.format = GL_RGBA8
            textureOut.pointee.user_data = nil
            textureOut.pointee.destruction_callback = nil
            textureOut.pointee.width = texW
            textureOut.pointee.height = texH
            return true
        }

        // DMA-BUF zero-copy path: import fd as EGLImage → bind to texture.
        if entry.dmaFd >= 0 {
            let dmaW = entry.width
            let dmaH = entry.height
            let dmaStride = entry.dmaStride
            let dmaFourcc = entry.dmaFourcc
            let dmaModifier = entry.dmaModifier
            let dmaFd = entry.dmaFd
            let existingImage = entry.eglImage
            let needsReimport = entry.needsReimport
            let isWayland = entry.isWaylandSurface
            let isDirty = entry.dirty
            entry.dirty = false
            entry.needsReimport = false
            // Safe point to close retired owned fds: this is the only thread
            // that imports from them, and any prior populate has finished.
            let retired = entry.retiredFds
            entry.retiredFds = []
            lock.unlock()
            for fd in retired { Glibc.close(fd) }

            // Resolve the EGLImage for the buffer now attached to this texture.
            // A client cycling its buffer pool re-commits the same few dma-bufs,
            // so the common case is a cache hit: rebind, no import.
            if existingImage == nil || needsReimport {
                // For Wayland toplevel surfaces, import with opaque format (XBGR/XRGB)
                // to ignore the alpha channel. Toplevel windows leave alpha=0x00
                // causing the "ghost window" effect if alpha blending is applied.
                // Popup surfaces keep ABGR — they use premultiplied alpha for
                // translucent backgrounds, drop shadows, and rounded corners.
                let isPopup = entry.isPopupSurface
                var importFourcc = dmaFourcc
                if isWayland && !isPopup {
                    let DRM_FORMAT_ABGR8888: UInt32 = 0x34324241
                    let DRM_FORMAT_XBGR8888: UInt32 = 0x34324258
                    let DRM_FORMAT_ARGB8888: UInt32 = 0x34325241
                    let DRM_FORMAT_XRGB8888: UInt32 = 0x34325258
                    if importFourcc == DRM_FORMAT_ABGR8888 { importFourcc = DRM_FORMAT_XBGR8888 }
                    else if importFourcc == DRM_FORMAT_ARGB8888 { importFourcc = DRM_FORMAT_XRGB8888 }
                }

                // Identify the buffer itself. Without an inode we cannot tell
                // one dma-buf from another (fd numbers get recycled), so fall
                // back to the old always-import behaviour.
                let key = bufferIdentity(dmaFd).map {
                    BufferKey(dev: $0.dev, ino: $0.ino, width: dmaW, height: dmaH,
                              stride: dmaStride, fourcc: importFourcc,
                              modifier: dmaModifier)
                }

                lock.lock()
                let cached = key.flatMap { entries[id]?.imageCache[$0] }
                // A buffer known to be unimportable: skip the doomed retry
                // (and the resource churn behind it — see importFailures).
                let knownBad = key.map { entries[id]?.importFailures.contains($0) ?? false }
                    ?? false
                lock.unlock()

                // A modifier we never advertised must not reach the AMD
                // driver: eglCreateImageKHR on a foreign tiled layout can
                // allocate-then-fail and, under GPU-memory pressure, abort
                // the shell with an amdgpu CS rejection (the PRIME incident).
                // Treat it exactly like a failed import — the buffer is
                // unimportable, so this is the truthful outcome anyway.
                // Wayland surfaces only; child-app buffers are always LINEAR
                // and skip this (they pass importable trivially regardless).
                let importable = wayland_server_dmabuf_modifier_importable(
                    importFourcc, dmaModifier) != 0

                var resolved = cached
                if resolved == nil && !knownBad && importable {
                    let eglDisplay = _eglGetCurrentDisplay()
                    resolved = dmabuf_import_egl_image_with_modifier(
                        eglDisplay, dmaFd, Int32(dmaW), Int32(dmaH),
                        Int32(dmaStride), importFourcc, dmaModifier
                    )
                    if let image = resolved, let key = key {
                        // Retain in the cache; evict oldest beyond the limit.
                        var evicted: [UnsafeMutableRawPointer] = []
                        lock.lock()
                        if let e = entries[id] {
                            e.imageCache[key] = image
                            e.imageCacheOrder.append(key)
                            while e.imageCacheOrder.count > kImageCacheLimit {
                                let old = e.imageCacheOrder.removeFirst()
                                // Never evict what we are about to bind.
                                if old == key { e.imageCacheOrder.append(old); break }
                                if let img = e.imageCache.removeValue(forKey: old) {
                                    evicted.append(img)
                                }
                            }
                        }
                        lock.unlock()
                        if !evicted.isEmpty, let display = _eglGetCurrentDisplay() {
                            for img in evicted { dmabuf_destroy_egl_image(display, img) }
                        }
                    }
                }

                if let image = resolved {
                    // Bind EGLImage directly — zero-copy, no CPU readback.
                    // Y-flip for Wayland is handled at the widget layer.
                    _glBindTexture(GL_TEXTURE_2D, texName)
                    dmabuf_bind_texture(image)
                    // Wayland clients (Chrome) may have slight size mismatches —
                    // use GL_LINEAR for smooth text. Child apps use pixel-perfect
                    // DmaBufConfigure sizing so GL_NEAREST is fine.
                    let filter = isWayland ? GL_LINEAR : GL_NEAREST
                    _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter)
                    _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter)
                    _glBindTexture(GL_TEXTURE_2D, 0)

                    // The previous image is owned by imageCache (or, when the
                    // buffer had no inode, was never cached) — the cache is the
                    // only thing that destroys images now, on eviction/teardown.
                    // Destroying here would free a buffer the pool still cycles.
                    if key == nil, needsReimport, let oldImage = existingImage,
                       oldImage != image, let display = _eglGetCurrentDisplay() {
                        dmabuf_destroy_egl_image(display, oldImage)
                    }

                    lock.lock()
                    entries[id]?.eglImage = image
                    lock.unlock()
                } else if !knownBad {
                    // No image: either the import was rejected, or we skipped
                    // it because the modifier was never advertised
                    // (`!importable`). Both are permanent for this buffer.
                    if importable {
                        // A buffer we DID try and EGL refused: demote its
                        // modifier so a compliant client re-allocates one that
                        // imports (the window would otherwise stay invisible).
                        // A never-advertised modifier gets no demote — it was
                        // never in the list to remove.
                        Self.onDmaBufImportFailure?(dmaFourcc, dmaModifier)
                    }
                    // Remember this buffer is unimportable so we never touch it
                    // again — the retry, not just the first attempt, is what
                    // drove the AMD driver to an ENOMEM CS rejection. Bounded
                    // like imageCache so a client cycling fresh buffers cannot
                    // grow the set without limit.
                    if let key = key {
                        lock.lock()
                        if let e = entries[id], e.importFailures.insert(key).inserted {
                            e.importFailureOrder.append(key)
                            while e.importFailureOrder.count > kImageCacheLimit {
                                let old = e.importFailureOrder.removeFirst()
                                e.importFailures.remove(old)
                            }
                        }
                        lock.unlock()
                    }
                    // The texture name has no storage and we still return it
                    // below. Give it one black texel so the engine samples
                    // something defined (a black window) instead of an
                    // incomplete texture. Established once; a later successful
                    // import replaces it wholesale.
                    if existingImage == nil {
                        var establish = false
                        lock.lock()
                        if let e = entries[id], !e.hasFallbackTexel {
                            e.hasFallbackTexel = true
                            establish = true
                        }
                        lock.unlock()
                        if establish {
                            var black: [UInt8] = [0, 0, 0, 0xFF]
                            _glBindTexture(GL_TEXTURE_2D, texName)
                            _glTexImage2D(GL_TEXTURE_2D, 0, Int32(GL_RGBA),
                                          1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                                          &black)
                            _glTexParameteri(GL_TEXTURE_2D,
                                             GL_TEXTURE_MIN_FILTER, GL_LINEAR)
                            _glTexParameteri(GL_TEXTURE_2D,
                                             GL_TEXTURE_MAG_FILTER, GL_LINEAR)
                            _glBindTexture(GL_TEXTURE_2D, 0)
                        }
                    }
                }
            }
            // For subsequent frames: re-bind only when content changed.
            else if isDirty {
                _glBindTexture(GL_TEXTURE_2D, texName)
                dmabuf_bind_texture(existingImage)
                _glBindTexture(GL_TEXTURE_2D, 0)
            }

            textureOut.pointee.target = GL_TEXTURE_2D
            textureOut.pointee.name = texName
            textureOut.pointee.format = GL_RGBA8
            textureOut.pointee.user_data = nil
            textureOut.pointee.destruction_callback = nil
            textureOut.pointee.width = dmaW
            textureOut.pointee.height = dmaH
            return true
        }

        // CPU pixel upload path (SoftwareRenderer / LinuxOffscreenFlutterApp / wl_shm).
        let hasData = entry.pixelData != nil && entry.width > 0 && entry.height > 0
        let dirty = entry.dirty && hasData

        if dirty {
            let texWidth = Int32(entry.width)
            let texHeight = Int32(entry.height)
            entry.dirty = false

            let pixelFormat = GL_RGBA
            _glBindTexture(GL_TEXTURE_2D, texName)
            _glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
            // Re-upload into existing storage when the size hasn't changed.
            // glTexImage2D *reallocates* the texture every call, so using it
            // per frame makes the driver orphan and re-create a 16MB image 24
            // times a second for a playing video — and once per commit for
            // every wl_shm client. glTexSubImage2D writes into the storage
            // that is already there. The full call still runs on the first
            // frame and on any resize, which is what establishes the format.
            if entry.glTexWidth == entry.width, entry.glTexHeight == entry.height,
               _glTexSubImage2D != nil {
                _glTexSubImage2D(
                    GL_TEXTURE_2D, 0, 0, 0,
                    texWidth, texHeight,
                    pixelFormat, GL_UNSIGNED_BYTE, entry.pixelData!
                )
            } else {
                _glTexImage2D(
                    GL_TEXTURE_2D, 0, Int32(GL_RGBA),
                    texWidth, texHeight, 0,
                    pixelFormat, GL_UNSIGNED_BYTE, entry.pixelData!
                )
                entry.glTexWidth = entry.width
                entry.glTexHeight = entry.height
            }
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
            _glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
            _glBindTexture(GL_TEXTURE_2D, 0)
        }

        let texW = hasData ? entry.width : 1
        let texH = hasData ? entry.height : 1

        lock.unlock()

        textureOut.pointee.target = GL_TEXTURE_2D
        textureOut.pointee.name = texName
        textureOut.pointee.format = GL_RGBA8
        textureOut.pointee.user_data = nil
        textureOut.pointee.destruction_callback = nil
        textureOut.pointee.width = texW
        textureOut.pointee.height = texH

        return true
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - C Callback
// ═══════════════════════════════════════════════════════════════════════════════

/// Static C-compatible callback for the embedder's `gl_external_texture_frame_callback`.
/// Extracts AppState from user_data and delegates to the texture registry.
let linuxTextureFrameCallback: @convention(c) (
    UnsafeMutableRawPointer?,   // user_data
    Int64,                      // texture_identifier
    Int,                        // width
    Int,                        // height
    UnsafeMutablePointer<FlutterOpenGLTexture>?  // texture_out
) -> Bool = { userData, textureId, width, height, textureOut in
    guard let userData = userData,
          let textureOut = textureOut else {
        return false
    }
    let state = Unmanaged<AppState>.fromOpaque(userData).takeUnretainedValue()
    guard let registry = state.textureRegistry else {
        return false
    }
    return registry.populateTexture(
        id: textureId,
        width: width,
        height: height,
        textureOut: textureOut
    )
}

#endif
