// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import FlutterEmbedderBridge
import Flutter
import FlutterSwiftBridge
import Foundation

/// Manages offscreen-rendered "external apps" and offscreen Flutter apps
/// that are composited into the desktop shell via the embedder's external
/// texture API.
///
/// This is the Linux equivalent of `ExternalAppManager` (macOS). Instead of
/// FlutterTexture + CVPixelBuffer, it uses `LinuxTextureRegistry` to manage
/// GL textures populated from raw RGBA pixel data.
class LinuxExternalAppManager {

    private let engine: OpaquePointer
    private let textureRegistry: LinuxTextureRegistry

    /// Active external apps keyed by their texture ID.
    private var externalApps: [Int64: ExternalAppEntry] = [:]

    /// Active GL-rendered external apps keyed by their texture ID.
    private var glExternalApps: [Int64: GLExternalAppEntry] = [:]

    /// Active Flutter apps keyed by their texture ID.
    private var flutterApps: [Int64: FlutterAppEntry] = [:]

    /// When true, renderers are driven by tickRender() from vsync instead of
    /// Foundation.Timer (required for DRM mode where RunLoop.main doesn't spin).
    private(set) var useVsyncDriven: Bool = false

    init(engine: OpaquePointer, textureRegistry: LinuxTextureRegistry) {
        self.engine = engine
        self.textureRegistry = textureRegistry
    }

    /// Enable vsync-driven rendering and register with FrameCallbackScheduler.
    /// Must be called before creating any apps.
    func enableVsyncDriven() {
        useVsyncDriven = true
        FrameCallbackScheduler.shared.register(self) { [weak self] in
            guard let self = self else { return }
            let now = FlutterEngineGetCurrentTime()
            self.tick(currentTimeNanos: now)
        }
    }

    // MARK: - External App (SoftwareRenderer / GLRenderer)

    /// Creates a new offscreen-rendered external app and registers it with
    /// the engine's texture system.
    ///
    /// In vsync-driven (DRM) mode, uses GLRenderer for GPU-based rendering.
    /// In GLFW mode, uses SoftwareRenderer with CPU pixel rendering.
    ///
    /// Returns the texture ID that can be passed to `TextureWidget`.
    func createExternalApp(width: Int = 640, height: Int = 480) -> Int64 {
        let textureId = textureRegistry.registerTexture(engine: engine)

        if useVsyncDriven {
            // GPU-rendered: GLRenderer renders directly to GL texture via FBO.
            let glRenderer = GLRenderer(width: width, height: height)
            glRenderer.glProcAddressResolver = textureRegistry.glProcAddressResolver
            textureRegistry.setGLRenderer(id: textureId, renderer: glRenderer)

            let entry = GLExternalAppEntry(
                renderer: glRenderer,
                textureId: textureId
            )
            glExternalApps[textureId] = entry

            // Kick off the render loop — markDirty schedules a frame which
            // triggers onBeginFrame → tick → advanceAnimation → markDirty → ...
            textureRegistry.markGLTextureDirty(engine: engine, id: textureId)
        } else {
            // CPU-rendered: SoftwareRenderer uploads pixels via glTexImage2D.
            let renderer = SoftwareRenderer(width: width, height: height)

            renderer.onFrameReady = { [weak self] (data, w, h) in
                guard let self = self else { return }
                self.textureRegistry.updatePixelData(
                    engine: self.engine,
                    id: textureId,
                    data: data,
                    width: w,
                    height: h
                )
            }

            let entry = ExternalAppEntry(
                renderer: renderer,
                textureId: textureId
            )
            externalApps[textureId] = entry

            // GLFW mode: delay renderer start to ensure engine has finished initial
            // frame rendering, then drive via Foundation.Timer on RunLoop.main.
            let delayedRenderer = renderer
            let block: (Timer) -> Void = { _ in
                delayedRenderer.start(fps: 30)
            }
            let sendableBlock = unsafeBitCast(block, to: (@Sendable (Timer) -> Void).self)
            let delayTimer = Timer(timeInterval: 2.0, repeats: false, block: sendableBlock)
            Foundation.RunLoop.main.add(delayTimer, forMode: .default)
            Foundation.RunLoop.main.add(delayTimer, forMode: .common)
        }

        return textureId
    }

    /// Stops the renderer and unregisters the texture for the given ID.
    func destroyExternalApp(textureId: Int64) {
        if let entry = externalApps.removeValue(forKey: textureId) {
            entry.renderer.stop()
        } else {
            glExternalApps.removeValue(forKey: textureId)
        }
        textureRegistry.unregisterTexture(engine: engine, id: textureId)
    }

    // MARK: - Flutter App (LinuxOffscreenFlutterApp)

    /// Creates a new offscreen Flutter app that renders a real widget tree
    /// and registers it with the engine's texture system.
    ///
    /// Returns the texture ID that can be passed to `TextureWidget`.
    func createFlutterApp(width: Int = 640, height: Int = 480) -> Int64 {
        let offscreenApp = LinuxOffscreenFlutterApp(width: width, height: height)
        let textureId = textureRegistry.registerTexture(engine: engine)

        offscreenApp.onFrameReady = { [weak self] (data, w, h) in
            guard let self = self else { return }
            data.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress else { return }
                self.textureRegistry.updatePixelData(
                    engine: self.engine,
                    id: textureId,
                    data: ptr,
                    width: w,
                    height: h
                )
            }
        }

        let entry = FlutterAppEntry(
            offscreenApp: offscreenApp,
            textureId: textureId
        )
        flutterApps[textureId] = entry

        // Mount the demo widget and start rendering.
        // Wrap in Directionality since this is a standalone widget tree
        // (no MacosApp / MaterialApp ancestor to provide TextDirection).
        offscreenApp.mountWidget {
            Directionality(
                textDirection: TextDirection.ltr,
                child: FlutterDemoApp()
            )
        }

        if useVsyncDriven {
            // Kick off the render loop.
            FlutterEngineScheduleFrame(engine)
        } else {
            // GLFW mode: drive via Foundation.Timer on RunLoop.main.
            offscreenApp.start(fps: 30)
        }

        return textureId
    }

    // MARK: - Vsync-driven Tick

    /// Drives all active renderers from the vsync callback.
    /// Called by FrameCallbackScheduler from onBeginFrame.
    func tick(currentTimeNanos: UInt64) {
        // GL-rendered external apps: advance animation state on main thread,
        // then mark the texture dirty so the raster thread re-renders.
        for (textureId, entry) in glExternalApps {
            entry.renderer.advanceAnimation()
            textureRegistry.markGLTextureDirty(engine: engine, id: textureId)
            FrameCallbackScheduler.shared.noteTextureUpdate(textureId)
        }
        // CPU-rendered external apps (fallback).
        for (_, entry) in externalApps {
            entry.renderer.tickRender(currentTimeNanos: currentTimeNanos)
        }
        // CPU-rendered Flutter apps.
        for (_, entry) in flutterApps {
            entry.offscreenApp.tickRender(currentTimeNanos: currentTimeNanos)
        }
    }

    /// Stops the Flutter app and unregisters the texture for the given ID.
    func destroyFlutterApp(textureId: Int64) {
        guard let entry = flutterApps.removeValue(forKey: textureId) else { return }
        entry.offscreenApp.stop()
        textureRegistry.unregisterTexture(engine: engine, id: textureId)
    }
}

// MARK: - Entry Types

private struct ExternalAppEntry {
    let renderer: SoftwareRenderer
    let textureId: Int64
}

private struct GLExternalAppEntry {
    let renderer: GLRenderer
    let textureId: Int64
}

private struct FlutterAppEntry {
    let offscreenApp: LinuxOffscreenFlutterApp
    let textureId: Int64
}

#endif
